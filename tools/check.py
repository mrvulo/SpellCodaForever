"""Pre-release checks for SpellCodaForever. Run before every commit that ships:

    python tools/check.py

Every check guards something that broke, or nearly broke, before. A failing
check means: do not commit or release until it is green. See CLAUDE.md.

Needs node and `npm install` in tools/ once (luaparse for the Lua checks).
"""
import json
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
TOC = os.path.join(ROOT, 'SpellCodaForever.toc')

# Lua files that exist on purpose without a TOC line
NOT_LOADED = {
    'Data/fake.lua',   # generator output for test runs only
}
# addon names that must never appear in shippable files (reference addons the
# features were modelled on); see CLAUDE.md "Naming"
FORBIDDEN_NAMES = re.compile(r"WhatsTraining|What's Training", re.I)
SAVED_VARS = ('SpellCodaForeverDB', 'SpellCodaForeverCharDB')

failures = []


def fail(check, msg):
    failures.append(f'[{check}] {msg}')


def rel(p):
    return os.path.relpath(p, ROOT).replace(os.sep, '/')


def toc_lines():
    return [l.strip() for l in open(TOC, encoding='utf-8')]


def toc_files():
    return [l for l in toc_lines() if l and not l.startswith('#')]


def addon_lua_files():
    """Every .lua the package ships (tools/ and branding/ never ship)."""
    out = []
    for d, dirs, files in os.walk(ROOT):
        r = rel(d)
        dirs[:] = [x for x in dirs if not x.startswith('.') and
                   (r != '.' or x not in ('tools', 'branding', 'node_modules'))]
        out += [rel(os.path.join(d, f)) for f in files if f.endswith('.lua')]
    return out


def check_toc():
    listed = toc_files()
    for f in listed:
        if not os.path.isfile(os.path.join(ROOT, f)):
            fail('toc', f'listed but missing: {f}')
    listed_set = set(listed)
    for f in addon_lua_files():
        if f.startswith('Libs/'):
            continue
        if f not in listed_set and f not in NOT_LOADED:
            fail('toc', f'not loaded by the TOC: {f}')
    meta = {l.split(':', 1)[0][3:].strip(): l.split(':', 1)[1].strip()
            for l in toc_lines() if l.startswith('## ') and ':' in l}
    sv = (meta.get('SavedVariables', ''), meta.get('SavedVariablesPerCharacter', ''))
    if sv != SAVED_VARS:
        fail('toc', f'saved variables changed: {sv}, expected {SAVED_VARS} (renaming loses every setting)')
    core = open(os.path.join(ROOT, 'Core', 'core.lua'), encoding='utf-8').read()
    major = re.search(r'^local version_major\s*=\s*(\d+);', core, re.M).group(1)
    minor = re.search(r'^local version_minor\s*=\s*(\d+);', core, re.M).group(1)
    if meta.get('Version') != f'{major}.{minor}':
        fail('toc', f'## Version {meta.get("Version")} != core.lua {major}.{minor}')
    icon = meta.get('IconTexture', '').replace('\\', '/')
    if icon and not os.path.isfile(os.path.join(ROOT, icon.split('AddOns/SpellCodaForever/', 1)[-1] + '.tga')):
        fail('toc', f'IconTexture file missing: {icon}')


def check_names():
    for f in addon_lua_files() + ['SpellCodaForever.toc', 'CHANGELOG-release.md']:
        text = open(os.path.join(ROOT, f), encoding='utf-8').read()
        if FORBIDDEN_NAMES.search(text):
            fail('names', f'reference addon named in {f}')
        if f.endswith('.lua') and re.search(r'__sc_p_(acc|char)\b', text):
            fail('names', f'upstream saved variable name in {f}; this addon uses {SAVED_VARS}')


def check_locales():
    keys_file = open(os.path.join(ROOT, 'Locales', 'locale_strings.lua'), encoding='utf-8').read()
    known = set(re.findall(r'^  "((?:[^"\\]|\\.)*)",\s*$', keys_file, re.M))
    for f in sorted(x for x in os.listdir(os.path.join(ROOT, 'Locales')) if x != 'locale_strings.lua'):
        seen = {}
        for n, line in enumerate(open(os.path.join(ROOT, 'Locales', f), encoding='utf-8'), 1):
            m = re.match(r'^L\["((?:[^"\\]|\\.)*)"\]\s*=', line)
            if m:
                if m.group(1) in seen:
                    fail('locale', f'{f}:{n} duplicate key (line {seen[m.group(1)]} is silently overwritten): {m.group(1)}')
                if m.group(1) not in known:
                    fail('locale', f'{f}:{n} obsolete key, not in Locales/locale_strings.lua: {m.group(1)}')
                seen[m.group(1)] = n
    # keys our own modules use must be localizable
    for f in ('UI/spellbook.lua', 'Core/api.lua', 'UI/verify.lua'):
        text = open(os.path.join(ROOT, f), encoding='utf-8').read()
        for key in re.findall(r'\bL\["((?:[^"\\]|\\.)*)"\]', text):
            if key not in known:
                fail('locale', f'{f}: L["{key}"] missing from Locales/locale_strings.lua')


def run(check, cmd):
    r = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True, encoding='utf-8', errors='replace')
    if r.returncode != 0:
        out = (r.stdout + r.stderr).strip().splitlines()
        fail(check, '\n    '.join(out[-25:]))


def check_lua():
    files = [f for f in toc_files() if f.endswith('.lua')]
    script = (
        "const lp=require('luaparse');const fs=require('fs');let bad=0;"
        "for(const f of process.argv.slice(1)){try{lp.parse(fs.readFileSync(f,'utf8'),{luaVersion:'5.2'})}"
        "catch(e){console.log(f+': '+e.message);bad=1}}process.exit(bad)")
    env = dict(os.environ, NODE_PATH=os.path.join(HERE, 'node_modules'))
    r = subprocess.run(['node', '-e', script] + files, cwd=ROOT, capture_output=True, text=True,
                       env=env, encoding='utf-8', errors='replace')
    if r.returncode != 0:
        fail('syntax', (r.stdout + r.stderr).strip())
    own = [os.path.join(ROOT, f) for f in files if not f.startswith('Libs/') and not f.startswith('Data/')]
    r = subprocess.run(['node', os.path.join(HERE, 'apilint.cjs')] + own,
                       cwd=HERE, capture_output=True, text=True, env=env, encoding='utf-8', errors='replace')
    if r.returncode != 0:
        fail('api', '\n    '.join((r.stdout + r.stderr).strip().splitlines()[-25:]))


def main():
    # failure text quotes locale files; the Windows console is not UTF-8 by default
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')
    check_toc()
    check_names()
    check_locales()
    check_lua()
    run('exports', [sys.executable, os.path.join(HERE, 'check_exports.py')])
    if failures:
        print('\n'.join(failures))
        print(f'\nFAILED: {len(failures)} problem(s)')
        return 1
    print('all checks passed')
    return 0


if __name__ == '__main__':
    sys.exit(main())
