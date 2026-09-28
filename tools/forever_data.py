"""Patch SpellCoda's generated spell data with values from the WoW Forever client.

SpellCoda's data is generated from the Classic Era client by a generator that is
not public. Forever changed many spells (damage, coefficients, levels, costs).
This script keeps the generated structure and only replaces numbers whose origin
is unambiguous: a value in the Era-generated data that equals the matching field
of the Era client's DB2 tables is replaced by the same field of the Forever
client's DB2 tables. Anything that cannot be traced this way stays untouched and
is listed in the report.

    python tools/forever_data.py                  # patch generated/vanilla
    python tools/forever_data.py --build 1.60.1.xxxxx
    python tools/forever_data.py --dry-run        # report only

Source data: tools/era_source/<class>.lua (the untouched Era generated files).
DB2 tables are fetched as CSV from wago.tools and cached in tools/db2_cache.
"""
import argparse, csv, io, math, os, re, sys, urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
ERA_BUILD = '1.15.9.69547'
DEFAULT_FOREVER_BUILD = '1.60.1.70009'
CLASSES = 'druid hunter mage paladin priest rogue shaman warlock warrior'.split()
TABLES = ['SpellEffect', 'SpellLevels', 'SpellMisc', 'SpellCastTimes', 'SpellDuration', 'SpellPower', 'SpellName']


def fetch(table, build):
    cache = os.path.join(HERE, 'db2_cache')
    os.makedirs(cache, exist_ok=True)
    path = os.path.join(cache, f'{table}_{build}.csv')
    if not os.path.exists(path):
        url = f'https://wago.tools/db2/{table}/csv?build={build}'
        print('download', url)
        with urllib.request.urlopen(url) as r, open(path, 'wb') as f:
            f.write(r.read())
    with open(path, encoding='utf-8') as f:
        return list(csv.DictReader(f))


def fl(v):
    try:
        return float(v)
    except (TypeError, ValueError):
        return 0.0


# (effect, aura) pairs that do the same job in both clients although the id differs:
# Era scripts Holy Light and Flash of Light (77), Forever uses a plain heal (10)
EQUIVALENT_KINDS = {
    (('77', '0'), ('10', '0')),
}


class Client:
    """The spell fields this script needs, normalized across both DB2 formats."""

    def __init__(self, build, retail_format):
        self.build = build
        self.effects = {}
        for r in fetch('SpellEffect', build):
            if r.get('DifficultyID', '0') != '0':
                continue
            if retail_format:
                # Forever: EffectBasePointsF with a relative Variance around it
                base = fl(r['EffectBasePointsF'])
                var = fl(r['Variance'])
                lo, hi = round(base * (1 - var / 2)), round(base * (1 + var / 2))
                # fixed aura amount, only when there is no random range
                amount = base if var == 0 else None
            else:
                # Era: EffectBasePoints + 1 .. EffectBasePoints + EffectDieSides
                base, die = fl(r['EffectBasePoints']), fl(r['EffectDieSides'])
                lo, hi = (base + 1, base + die) if die > 0 else (base, base)
                amount = lo if die <= 1 else None
            self.effects[(int(r['SpellID']), int(r['EffectIndex']))] = {
                'min': lo, 'max': hi, 'amount': amount,
                # what the effect does; the same index may do something else in the other client
                'kind': (r['Effect'], r['EffectAura'], r['EffectMiscValue_0']),
                'coef': fl(r['EffectBonusCoefficient']),
                'per_lvl': fl(r['EffectRealPointsPerLevel']),
                'period': fl(r['EffectAuraPeriod']) / 1000,
            }
        self.levels = {}
        for r in fetch('SpellLevels', build):
            if r.get('DifficultyID', '0') == '0':
                self.levels[int(r['SpellID'])] = {
                    'base': int(fl(r['BaseLevel'])), 'spell': int(fl(r['SpellLevel'])), 'max': int(fl(r['MaxLevel']))}
        cast_times = {int(r['ID']): fl(r['Base']) / 1000 for r in fetch('SpellCastTimes', build)}
        durations = {int(r['ID']): fl(r['Duration']) / 1000 for r in fetch('SpellDuration', build)}
        self.cast = {}
        self.dur = {}
        spell_col = 'SpellID'
        for r in fetch('SpellMisc', build):
            if r.get('DifficultyID', '0') != '0' or spell_col not in r:
                continue
            sid = int(r[spell_col])
            self.cast[sid] = cast_times.get(int(fl(r['CastingTimeIndex'])))
            self.dur[sid] = durations.get(int(fl(r['DurationIndex'])))
        self.cost = {}
        for r in fetch('SpellPower', build):
            if r.get('OrderIndex', '0') == '0':
                self.cost[int(r['SpellID'])] = fl(r['ManaCost'])
        self.names = {int(r['ID']): r['Name_lang'] for r in fetch('SpellName', build)} if retail_format else {}

    def effect_indices(self, sid):
        return sorted(i for (s, i) in self.effects if s == sid)

    def counterpart(self, sid, idx, other):
        """This client's effect doing what effect idx of spell sid does in the other client."""
        theirs = other.effects.get((sid, idx))
        if not theirs:
            return None
        same = self.effects.get((sid, idx))
        if same and (same['kind'] == theirs['kind'] or
                     (theirs['kind'][:2], same['kind'][:2]) in EQUIVALENT_KINDS):
            return same
        # effects were reordered: take the only effect of the same kind
        found = [self.effects[(sid, i)] for i in self.effect_indices(sid)
                 if self.effects[(sid, i)]['kind'] == theirs['kind']]
        return found[0] if len(found) == 1 else None


def close(a, b, rel=0.002, absolute=0.0015):
    return abs(a - b) <= max(absolute, rel * max(abs(a), abs(b)))


def fmt(v, integer=False):
    if integer:
        return str(int(round(v)))
    s = f'{v:.4f}'.rstrip('0').rstrip('.')
    return s if s not in ('', '-0') else '0'


VALUE_RE = re.compile(r'^(\t+)([a-z_0-9]+) = (-?[0-9.e+-]+),\s*$')


def patch_class(text, era, fv, report):
    start = text.index('sc.spells = {')
    end = text.index('\n};', start)
    lines = text[start:end].split('\n')

    spell_id = None
    comp = None           # 'direct' / 'periodic' at depth 2
    block = []            # (line index, key, value) of the current block
    spell_fields = {}     # depth 2 numeric fields of the current spell
    comps = {}

    def flush_spell():
        if spell_id is None:
            return
        changes = []
        used_effects = set()
        eidx_era = era.effect_indices(spell_id)
        for name, fields in comps.items():
            vals = {k: (i, v) for i, k, v in fields}
            if 'min' not in vals or 'max' not in vals:
                continue
            lo, hi = vals['min'][1], vals['max'][1]
            match = None
            for e in eidx_era:
                if e in used_effects:
                    continue
                ee = era.effects[(spell_id, e)]
                if name == 'periodic' and 'tick_time' in vals and not close(ee['period'], vals['tick_time'][1]):
                    continue
                if close(ee['min'], lo, absolute=0.5) and close(ee['max'], hi, absolute=0.5):
                    match = e
                    break
            if match is None:
                report['untraced'].append(f'{spell_id} {name}: {lo}-{hi}')
                continue
            fe = fv.counterpart(spell_id, match, era)
            if not fe:
                report['missing'].append(f'{spell_id} {name}: effect {match} gone or changed in Forever')
                continue
            used_effects.add(match)
            ee = era.effects[(spell_id, match)]
            new = {'min': (fe['min'], True), 'max': (fe['max'], True)}
            if 'coef' in vals and close(ee['coef'], vals['coef'][1]):
                new['coef'] = (fe['coef'], False)
            if 'per_lvl' in vals and close(ee['per_lvl'], vals['per_lvl'][1]):
                new['per_lvl'] = (fe['per_lvl'], False)
            if name == 'periodic':
                if 'tick_time' in vals and fe['period'] > 0:
                    new['tick_time'] = (fe['period'], False)
                if 'dur' in vals and era.dur.get(spell_id) and close(era.dur[spell_id], vals['dur'][1]) \
                        and fv.dur.get(spell_id):
                    new['dur'] = (fv.dur[spell_id], False)
            for key, (value, integer) in new.items():
                i, old = vals[key]
                if not close(old, value, absolute=0.0005):
                    lines[i] = re.sub(r'= [^,]+,', f'= {fmt(value, integer)},', lines[i], count=1)
                    changes.append(f'{name}.{key} {fmt(old)} -> {fmt(value, integer)}')

        # spell level fields
        el, fl_ = era.levels.get(spell_id), fv.levels.get(spell_id)
        if el and fl_:
            for key, col in (('lvl_req', None), ('lvl_max', 'max')):
                if key not in spell_fields:
                    continue
                i, old = spell_fields[key]
                cols = [col] if col else ['spell', 'base']
                for c in cols:
                    if el[c] and old == el[c] and fl_[c] and fl_[c] != old:
                        lines[i] = re.sub(r'= [^,]+,', f'= {fl_[c]},', lines[i], count=1)
                        changes.append(f'{key} {old} -> {fl_[c]}')
                        break
        # cast time
        if 'cast_time' in spell_fields and era.cast.get(spell_id) is not None and fv.cast.get(spell_id) is not None:
            i, old = spell_fields['cast_time']
            if old > 0 and close(era.cast[spell_id], old, absolute=0.01) and not close(fv.cast[spell_id], old, absolute=0.01):
                lines[i] = re.sub(r'= [^,]+,', f'= {fmt(fv.cast[spell_id])},', lines[i], count=1)
                changes.append(f'cast_time {fmt(old)} -> {fmt(fv.cast[spell_id])}')
        # cost (rage and energy costs are stored x10 in DB2)
        if 'cost' in spell_fields and spell_id in era.cost and spell_id in fv.cost:
            i, old = spell_fields['cost']
            for scale in (1, 10):
                if old > 0 and close(era.cost[spell_id] / scale, old, absolute=0.01):
                    new_cost = fv.cost[spell_id] / scale
                    if not close(new_cost, old, absolute=0.01):
                        lines[i] = re.sub(r'= [^,]+,', f'= {fmt(new_cost, True)},', lines[i], count=1)
                        changes.append(f'cost {fmt(old)} -> {fmt(new_cost, True)}')
                    break
        if changes:
            name = fv.names.get(spell_id, '?')
            report['changed'].append(f'{spell_id} {name}: ' + ', '.join(changes))

    for idx, line in enumerate(lines):
        m = re.match(r'^\t\[(\d+)\] = \{\s*$', line)
        if m:
            flush_spell()
            spell_id, comp, comps, spell_fields = int(m.group(1)), None, {}, {}
            continue
        if spell_id is None:
            continue
        m = re.match(r'^\t\t(direct|periodic) = \{\s*$', line)
        if m:
            comp = m.group(1)
            comps[comp] = []
            continue
        if comp and re.match(r'^\t\t\},?\s*$', line):
            comp = None
            continue
        m = VALUE_RE.match(line)
        if m:
            depth, key, value = len(m.group(1)), m.group(2), fl(m.group(3))
            if comp and depth == 3:
                comps[comp].append((idx, key, value))
            elif depth == 2:
                spell_fields[key] = (idx, value)
    flush_spell()
    return text[:start] + '\n'.join(lines) + text[end:]


# Talent, buff and passive effects: {"category", effect, VALUE, subjects, flags, effect_index}.
# VALUE is the DB2 amount of that effect times a unit scale (percent -> 0.01, sign, ...).
AURA_TABLES = ['talent_effects', 'class_buffs', 'class_hostile_buffs', 'class_friendly_buffs',
               'passives', 'shapeshift_passives', 'player_buffs', 'hostile_buffs', 'friendly_buffs',
               'item_effects', 'set_effects', 'enchant_effects']
AURA_RE = re.compile(r'^(\t\t\t\{"[a-z_]+", [^,]+, )(-?[0-9.e+-]+)(, (?:nil|\{[^}]*\}), \d+, )(-?\d+)(\},?\s*)$')
AURA_SCALES = (1, -1, 0.01, -0.01, 0.001, -0.001, 0.1, -0.1, 10, -10, 100, -100)


def same_value(a, b):
    return abs(a - b) <= max(1e-6, 1e-4 * abs(b))


def fmt_aura(v):
    if abs(v - round(v)) < 1e-9:
        return str(int(round(v)))
    s = f'{v:.6f}'.rstrip('0').rstrip('.')
    return s


def patch_auras(text, era, fv, report):
    for table in AURA_TABLES:
        m = re.search(r'^(?:sc\.|local )' + table + r' = \{\n', text, re.M)
        if not m:
            continue
        start = m.end()
        end = start + re.search(r'^\};', text[start:], re.M).start()
        lines = text[start:end].split('\n')
        spell_id = None
        for idx, line in enumerate(lines):
            h = re.match(r'^\t\[(\d+)\] = \{', line)
            if h:
                spell_id = int(h.group(1))
                continue
            e = AURA_RE.match(line)
            if not e or spell_id is None:
                continue
            value, eff_idx = fl(e.group(2)), int(e.group(4))
            if eff_idx < 0:
                continue  # addon-made aura, not from client data
            ee = era.effects.get((spell_id, eff_idx))
            if not ee or not ee['amount']:
                report['aura_untraced'] += 1
                continue
            scale = next((k for k in AURA_SCALES if same_value(ee['amount'] * k, value)), None)
            if scale is None:
                report['aura_untraced'] += 1
                continue
            fe = fv.counterpart(spell_id, eff_idx, era)
            if not fe or fe['amount'] is None:
                report['aura_untraced'] += 1
                if (spell_id, eff_idx) in fv.effects:
                    report['aura_restructured'].append(f'{table} {spell_id} {fv.names.get(spell_id, "?")} [{eff_idx}]')
                continue
            new = fe['amount'] * scale
            report['aura_traced'] += 1
            if not same_value(new, value):
                lines[idx] = e.group(1) + fmt_aura(new) + e.group(3) + e.group(4) + e.group(5)
                name = fv.names.get(spell_id, '?')
                report['aura_changed'].append(
                    f'{table} {spell_id} {name} [{eff_idx}]: {fmt_aura(value)} -> {fmt_aura(new)}')
        text = text[:start] + '\n'.join(lines) + text[end:]
    return text


# ---------------------------------------------------------------------------------------------
# Items. Forever stores weapon damage and armor the retail way (derived from item level and
# quality through ItemDamage*/ItemArmor* tables) and turned most "Equip:" spells into item stats.

class Items:
    def __init__(self):
        rd = lambda t, b: fetch(t, b)
        self.era = {r['ID']: r for r in rd('ItemSparse', ERA_BUILD)}
        self.fv = {r['ID']: r for r in rd('ItemSparse', FOREVER_BUILD[0])}
        self.fv_item = {r['ID']: r for r in rd('Item', FOREVER_BUILD[0])}
        self.dmg = {t: {r['ItemLevel']: r for r in rd('ItemDamage' + t, FOREVER_BUILD[0])}
                    for t in ('OneHand', 'TwoHand', 'OneHandCaster', 'TwoHandCaster',
                              'Ranged', 'Thrown', 'Wand', 'Ammo')}
        self.armor_total = {r['ItemLevel']: r for r in rd('ItemArmorTotal', FOREVER_BUILD[0])}
        self.armor_quality = {r['ID']: r for r in rd('ItemArmorQuality', FOREVER_BUILD[0])}
        self.armor_shield = {r['ItemLevel']: r for r in rd('ItemArmorShield', FOREVER_BUILD[0])}
        self.armor_location = {r['ID']: r for r in rd('ArmorLocation', FOREVER_BUILD[0])}
        self.era_equip = {}
        for r in rd('ItemEffect', ERA_BUILD):
            if r['TriggerType'] == '1':
                self.era_equip.setdefault(r['ParentItemID'], set()).add(int(r['SpellID']))
        effects = {r['ID']: r for r in rd('ItemEffect', FOREVER_BUILD[0])}
        self.fv_equip = {}
        for r in rd('ItemXItemEffect', FOREVER_BUILD[0]):
            e = effects.get(r['ItemEffectID'])
            if e and e['TriggerType'] == '1':
                self.fv_equip.setdefault(r['ItemID'], set()).add(int(e['SpellID']))

    def weapon(self, item_id):
        """Forever min, max, speed of a weapon or ammo, None if not derivable."""
        f, it = self.fv.get(item_id), self.fv_item.get(item_id)
        if not f or not it:
            return None
        inv, sub = int(f['InventoryType']), int(it['SubclassID'])
        caster = int(fl(f['Flags_1'])) & 0x200 != 0
        if inv in (13, 21, 22):
            table = 'OneHandCaster' if caster else 'OneHand'
        elif inv == 17:
            table = 'TwoHandCaster' if caster else 'TwoHand'
        elif inv in (15, 26):
            table = 'Wand' if sub == 19 else 'Ranged'
        elif inv == 25:
            table = 'Thrown'
        elif inv == 24:
            table = 'Ammo'
        else:
            return None
        row = self.dmg[table].get(f['ItemLevel'])
        if not row:
            return None
        dps = fl(row['Quality_' + f['OverallQualityID']])
        if table == 'Ammo':
            return dps, dps, None
        speed = fl(f['ItemDelay']) / 1000
        avg, var = dps * speed, fl(f['DmgVariance'])
        # min rounds down, max to nearest (reproduces the Era values of unchanged weapons)
        return math.floor(avg * (1 - var / 2) + 1e-6), math.floor(avg * (1 + var / 2) + 0.5), speed

    def changed(self, item_id, fields):
        """True when Forever changed any of the fields that the value is derived from."""
        e, f = self.era.get(item_id), self.fv.get(item_id)
        return bool(e and f) and any(fl(e[k]) != fl(f[k]) for k in fields)

    def armor(self, item_id):
        f, it = self.fv.get(item_id), self.fv_item.get(item_id)
        if not f or not it or it['ClassID'] != '4':
            return None
        q, lvl, inv, sub = f['OverallQualityID'], f['ItemLevel'], int(f['InventoryType']), int(it['SubclassID'])
        if sub == 6:
            row = self.armor_shield.get(lvl)
            return round(fl(row['Quality_' + q])) if row else None
        if inv == 16:
            sub = 1          # cloaks count as cloth
        if inv == 20:
            inv = 5          # robes use the chest modifier
        cols = {1: ('Cloth', 'Clothmodifier'), 2: ('Leather', 'Leathermodifier'),
                3: ('Mail', 'Chainmodifier'), 4: ('Plate', 'Platemodifier')}
        if sub not in cols:
            return None
        total, loc, qual = self.armor_total.get(lvl), self.armor_location.get(str(inv)), self.armor_quality.get(lvl)
        if not (total and loc and qual):
            return None
        return round(fl(total[cols[sub][0]]) * fl(loc[cols[sub][1]]) * fl(qual['Qualitymod_' + q]))


def table_span(text, name):
    m = re.search(r'^(?:sc\.|local )' + name + r' = \{\n', text, re.M)
    if not m:
        return None
    start = m.end()
    return start, start + re.search(r'^\};', text[start:], re.M).start()


def patch_items(text, items, known_effect_spells, report):
    # which equip spells an item has: drop spells Forever removed (mostly turned into item
    # stats, the addon reads those from the client), add new ones the addon has data for
    span = table_span(text, 'items')
    if span:
        start, end = span
        out = []
        for line in text[start:end].split('\n'):
            m = re.match(r'^\t\[(\d+)\] = \{([0-9,\- ]*)\},\s*$', line)
            if not m or m.group(1) not in items.fv:
                out.append(line)
                continue
            iid = m.group(1)
            old = [int(x) for x in m.group(2).split(',') if x.strip()]
            fv_equip = items.fv_equip.get(iid, set())
            new = [s for s in old if s in fv_equip or s not in items.era_equip.get(iid, set())]
            new += sorted(s for s in fv_equip if s in known_effect_spells and s not in new)
            if new != old:
                report['item_changed'].append(f'items {iid}: {old} -> {new}')
            if new:
                out.append(f'\t[{iid}] = {{' + ''.join(f'{s},' for s in new) + '},')
        text = text[:start] + '\n'.join(out) + text[end:]

    span = table_span(text, 'weapons')
    if span:
        start, end = span
        lines = text[start:end].split('\n')
        for idx, line in enumerate(lines):
            m = re.match(r'^\t\[(\d+)\] = \{(-?[0-9.]+), (-?[0-9.]+), (-?[0-9.]+)(.*)$', line)
            if not m:
                continue
            iid = m.group(1)
            e, w = items.era.get(iid), items.weapon(iid)
            if not e or not w or not items.changed(iid, ('ItemLevel', 'ItemDelay', 'OverallQualityID', 'DmgVariance')):
                continue
            lo, hi, speed = fl(m.group(2)), fl(m.group(3)), fl(m.group(4))
            if not (close(fl(e['MinDamage_0']), lo, absolute=0.5) and close(fl(e['MaxDamage_0']), hi, absolute=0.5)):
                continue
            new_speed = speed
            if w[2] is not None and close(fl(e['ItemDelay']) / 1000, speed, absolute=0.01):
                new_speed = w[2]
            if not (close(w[0], lo, absolute=0.5) and close(w[1], hi, absolute=0.5) and close(new_speed, speed, absolute=0.001)):
                lines[idx] = f'\t[{iid}] = {{{fmt(w[0], True)}, {fmt(w[1], True)}, {fmt(new_speed)}{m.group(5)}'
                report['item_changed'].append(f'weapons {iid}: {fmt(lo)}-{fmt(hi)} {fmt(speed)} -> '
                                              f'{fmt(w[0], True)}-{fmt(w[1], True)} {fmt(new_speed)}')
        text = text[:start] + '\n'.join(lines) + text[end:]

    span = table_span(text, 'armor')
    if span:
        start, end = span
        lines = text[start:end].split('\n')
        for idx, line in enumerate(lines):
            m = re.match(r'^\t\[(\d+)\] = (-?[0-9.]+),\s*$', line)
            if not m:
                continue
            iid, value = m.group(1), fl(m.group(2))
            e, a = items.era.get(iid), items.armor(iid)
            if e is None or a is None or not close(fl(e['Resistances_0']), value, absolute=0.5):
                continue
            if not items.changed(iid, ('ItemLevel', 'OverallQualityID', 'InventoryType')):
                continue
            if not close(a, value, absolute=0.5):
                lines[idx] = f'\t[{iid}] = {a},'
                report['item_changed'].append(f'armor {iid}: {fmt(value)} -> {a}')
        text = text[:start] + '\n'.join(lines) + text[end:]
    return text


def effect_spells(text):
    """Spell ids the file has item effect data for."""
    span = table_span(text, 'item_effects')
    if not span:
        return set()
    return {int(x) for x in re.findall(r'^\t\[(\d+)\] = \{', text[span[0]:span[1]], re.M)}


FOREVER_BUILD = [DEFAULT_FOREVER_BUILD]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--build', default=DEFAULT_FOREVER_BUILD)
    ap.add_argument('--dry-run', action='store_true')
    args = ap.parse_args()
    FOREVER_BUILD[0] = args.build

    era = Client(ERA_BUILD, retail_format=False)
    fv = Client(args.build, retail_format=True)
    report = {'changed': [], 'untraced': [], 'missing': [], 'item_changed': [],
              'aura_changed': [], 'aura_restructured': [], 'aura_traced': 0, 'aura_untraced': 0}
    items = Items()
    shared_effect_spells = effect_spells(io.open(os.path.join(HERE, 'era_source', 'all.lua'), encoding='utf-8').read())
    out_dir = os.path.join(ROOT, 'generated', 'vanilla')
    for cls in CLASSES + ['all']:
        src = io.open(os.path.join(HERE, 'era_source', cls + '.lua'), encoding='utf-8').read()
        before = len(report['changed'])
        before_aura = len(report['aura_changed'])
        patched = src
        if cls != 'all':
            patched = patch_class(patched, era, fv, report)
        patched = patch_auras(patched, era, fv, report)
        before_items = len(report['item_changed'])
        patched = patch_items(patched, items, effect_spells(patched) | shared_effect_spells, report)
        print(f'{"":8s} {len(report["item_changed"]) - before_items:4d} item values changed')
        print(f'{cls:8s} {len(report["changed"]) - before:4d} spells, '
              f'{len(report["aura_changed"]) - before_aura:4d} talent/buff values changed')
        if not args.dry_run:
            io.open(os.path.join(out_dir, cls + '.lua'), 'w', encoding='utf-8', newline='').write(patched)

    if not args.dry_run:
        # record which Forever build the spell values come from
        defs_path = os.path.join(out_dir, 'defs.lua')
        defs = io.open(defs_path, encoding='utf-8').read()
        line = f'sc.forever_data_build = "{args.build}";\n'
        defs = re.sub(r'sc\.forever_data_build = "[^"]*";\n', '', defs)
        anchor = 'sc.client_version_src = '
        i = defs.index('\n', defs.index(anchor)) + 1
        defs = defs[:i] + line + defs[i:]
        io.open(defs_path, 'w', encoding='utf-8', newline='').write(defs)

    with io.open(os.path.join(HERE, 'forever_data_report.txt'), 'w', encoding='utf-8') as f:
        f.write(f'Forever {args.build} vs Era {ERA_BUILD}\n')
        for k in ('changed', 'aura_changed', 'item_changed', 'aura_restructured', 'missing', 'untraced'):
            f.write(f'\n== {k} ({len(report[k])})\n')
            f.write('\n'.join(report[k]) + '\n')
        f.write(f'\ntalent/buff values traced {report["aura_traced"]}, untraced {report["aura_untraced"]}\n')
    print('spells changed', len(report['changed']), 'missing', len(report['missing']),
          'untraced', len(report['untraced']))
    print('talent/buff values changed', len(report['aura_changed']), 'traced', report['aura_traced'],
          'untraced', report['aura_untraced'])


if __name__ == '__main__':
    main()
