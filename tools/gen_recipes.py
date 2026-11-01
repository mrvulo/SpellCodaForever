"""Generate Professions/recipes.lua from the client tables of a WoW: Forever build.

    python tools/gen_recipes.py [build]        (default: the build below)

Downloads the tables it needs from wago.tools into tools/db2_cache/ (ignored by git)
once per build. What the client tables hold, and what they do not:

- every recipe of a profession (SkillLineAbility, acquire method 0 = learned from
  someone or something; 1 and 2 are learned on their own, 3 are removed recipes);
  profession ranks and specializations have no skill-up colors and are left out
- the skill needed for recipes taught by an item: the recipe item's RequiredSkillRank
- the skill-up colors (TrivialSkillLineRankLow/High)

The skill and price a trainer asks for are server side. The addon records them when
the player opens a profession trainer (UI/professions.lua).
"""
import csv
import os
import re
import sys
import urllib.request

BUILD = "1.60.1.70707"
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CACHE = os.path.join(ROOT, "tools", "db2_cache")
OUT = os.path.join(ROOT, "Professions", "recipes.lua")

# skill line -> English name (comments only; the addon reads the client's names)
PROFESSIONS = {
    171: "Alchemy", 164: "Blacksmithing", 333: "Enchanting", 202: "Engineering",
    182: "Herbalism", 165: "Leatherworking", 186: "Mining", 393: "Skinning",
    197: "Tailoring", 185: "Cooking", 129: "First Aid", 356: "Fishing",
}

ALLIANCE_RACES = {1, 3, 4, 7, 11, 22, 25, 29, 30, 32, 34, 37}
HORDE_RACES = {2, 5, 6, 8, 9, 10, 26, 27, 28, 31, 35, 36}

# names of recipes and recipe items no player can get (whole words, so
# "Flask of the Old Gods" and "Greatest" stay)
JUNK = re.compile(r"\b(deprecated|test|qa|unused|dnd|dnt)\b|\[ph\]|\(old\)", re.IGNORECASE)
JUNK_OLD = re.compile(r"\bOLD\b")


def table(name, build):
    os.makedirs(CACHE, exist_ok=True)
    path = os.path.join(CACHE, f"{name}_{build}.csv")
    if not os.path.exists(path):
        url = f"https://wago.tools/db2/{name}/csv?build={build}"
        print("download", url)
        # the default Python user agent is refused
        request = urllib.request.Request(url, headers={"User-Agent": "curl/8"})
        with urllib.request.urlopen(request, timeout=120) as r, open(path, "wb") as f:
            f.write(r.read())
    with open(path, encoding="utf-8", newline="") as f:
        return list(csv.DictReader(f))


def junk(name):
    return bool(JUNK.search(name) or JUNK_OLD.search(name))


def side_of(mask):
    """'A', 'H' or None for a race mask (0 or -1 = everyone); bit n-1 is race n."""
    v = int(mask or 0)
    if v in (0, -1):
        return None
    v &= (1 << 64) - 1
    races = {i + 1 for i in range(64) if v >> i & 1}
    if races and races <= ALLIANCE_RACES:
        return "A"
    if races and races <= HORDE_RACES:
        return "H"
    return None


def lua_str(s):
    return s.replace("\\", "\\\\").replace("\n", " ")


def main():
    build = sys.argv[1] if len(sys.argv) > 1 else BUILD
    names = {int(r["ID"]): r["Name_lang"] for r in table("SpellName", build)}
    items = {int(r["ID"]): r for r in table("Item", build)}
    sparse = {int(r["ID"]): r for r in table("ItemSparse", build)}
    effects = {int(r["ID"]): r for r in table("ItemEffect", build)}

    # recipe spell -> recipe items that teach it
    taught = {}
    for r in table("ItemXItemEffect", build):
        item_id = int(r["ItemID"])
        item, effect = items.get(item_id), effects.get(int(r["ItemEffectID"]))
        info = sparse.get(item_id)
        if not item or not effect or not info or item["ClassID"] != "9" or effect["TriggerType"] != "6":
            continue
        if junk(info["Display_lang"]):
            continue
        taught.setdefault(int(effect["SpellID"]), []).append(info)

    recipes = {sl: [] for sl in PROFESSIONS}
    seen = set()
    for r in table("SkillLineAbility", build):
        sl, spell = int(r["SkillLine"]), int(r["Spell"])
        if sl not in PROFESSIONS or r["AcquireMethod"] != "0" or spell in seen:
            continue
        name = names.get(spell)
        if not name or junk(name):
            continue
        seen.add(spell)
        side = side_of(r["RaceMasks_0"])
        req, item_id = 0, 0
        for info in sorted(taught.get(spell, []), key=lambda i: (int(i["RequiredSkillRank"] or 0), int(i["ID"]))):
            if int(info["RequiredSkill"] or 0) not in (0, sl):
                continue
            item_side = side_of(info["AllowableRace_0"])
            if side and item_side and item_side != side:
                continue
            req, item_id = int(info["RequiredSkillRank"] or 0), int(info["ID"])
            side = side or item_side
            break
        low, high = int(r["TrivialSkillLineRankLow"]), int(r["TrivialSkillLineRankHigh"])
        # no skill-ups and no recipe item: profession ranks and specializations,
        # which come from the trainer recording instead
        if low == 0 and high == 0 and not item_id:
            continue
        recipes[sl].append((low, req, spell, high, item_id, side, name))

    lines = [
        "local _, sc = ...;",
        "",
        f"-- GENERATED by tools/gen_recipes.py from the client tables of build {build}. Do not edit.",
        "-- skill line -> recipes: { spell, skill from the recipe item (0: trainer, quest or",
        "-- unknown), yellow from, grey from, recipe item (0: none), side (nil, \"Alliance\", \"Horde\") }",
        f'sc.recipes_build = "{build}";',
        "sc.recipes = {",
    ]
    total = 0
    for sl in sorted(recipes, key=lambda s: PROFESSIONS[s]):
        rows = sorted(recipes[sl])
        lines.append(f"    [{sl}] = {{ -- {PROFESSIONS[sl]}")
        for low, req, spell, high, item_id, side, name in rows:
            s = "" if not side else (', "Alliance"' if side == "A" else ', "Horde"')
            lines.append(f"        {{ {spell}, {req}, {low}, {high}, {item_id}{s} }}, -- {lua_str(name)}")
        lines.append("    },")
        total += len(rows)
    lines.append("};")
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines) + "\n")
    with_item = sum(1 for sl in recipes for r in recipes[sl] if r[4])
    print(f"{total} recipes, {with_item} from recipe items -> {os.path.relpath(OUT, ROOT)}")


if __name__ == "__main__":
    main()
