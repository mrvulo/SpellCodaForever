"""Take a new upstream SpellCoda version into this repo.

    python tools/upstream_merge.py v0.12.2897 v0.12.2900

FROM is the upstream tag this repo was last merged with (CLAUDE.md, "merge base"),
TO the new one. Upstream is cloned once into tools/.upstream (gitignored).

What it does, using tools/layout.json for the path mapping:
  1. code: `git merge-file` per mapped file (ours, base = FROM, theirs = TO); conflicts
     stay in the file as <<<<<<< ours / >>>>>>> upstream markers
  2. data: replaces Data/ with upstream's generated Camelot data at TO
  3. Locales/locale_strings.lua: upstream's list plus the keys only this addon uses
  4. renames upstream's saved variable names to ours
  5. reports upstream files that changed but have no mapping (new modules, libs)
It never commits. Afterwards: resolve conflicts, diff each file against upstream's
version for leftovers, run tools/check.py, update the merge base in CLAUDE.md.
"""
import json
import os
import re
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
UPSTREAM_URL = 'https://github.com/jezzi23/spellcoda.git'
CLONE = os.path.join(HERE, '.upstream')
SAVED_VARS = {'__sc_p_acc': 'SpellCodaForeverDB', '__sc_p_char': 'SpellCodaForeverCharDB'}
# upstream paths that never apply to this Forever-only addon
IGNORED = re.compile(r'^(TBC/|Vanilla/|SpellCoda.*\.toc$|README|LICENSE|\.github/|\.gitmodules$|font/)')
KEY = re.compile(r'^  "((?:[^"\\]|\\.)*)",\s*$', re.M)


def git(*args, cwd=CLONE, check=True):
    r = subprocess.run(['git', *args], cwd=cwd, capture_output=True, text=True,
                       encoding='utf-8', errors='replace')
    if check and r.returncode != 0:
        sys.exit(f'git {" ".join(args)} failed: {r.stderr.strip()}')
    return r.stdout


def show(rev, path, repo=CLONE):
    r = subprocess.run(['git', 'show', f'{rev}:{path}'], cwd=repo, capture_output=True)
    return r.stdout if r.returncode == 0 else None


def lf(data):
    return data.replace(b'\r\n', b'\n')


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    old, new = sys.argv[1], sys.argv[2]
    layout = json.load(open(os.path.join(HERE, 'layout.json'), encoding='utf-8'))

    if not os.path.isdir(CLONE):
        subprocess.run(['git', 'clone', '-q', UPSTREAM_URL, CLONE], check=True)
    git('fetch', '-q', '--tags', 'origin')
    git('submodule', 'update', '-q', '--init')
    if git('status', '--porcelain', cwd=ROOT).strip():
        print('note: the working tree has uncommitted changes')

    tmp = os.path.join(HERE, '.upstream_tmp')
    os.makedirs(tmp, exist_ok=True)
    conflicts = {}
    for up_path, our_path in layout['code'].items():
        base, theirs = show(old, up_path), show(new, up_path)
        if theirs is None:
            print(f'GONE upstream: {up_path} (ours: {our_path}) - decide by hand')
            continue
        if base is not None and lf(base) == lf(theirs):
            continue
        base_file, theirs_file = os.path.join(tmp, 'base'), os.path.join(tmp, 'theirs')
        open(base_file, 'wb').write(lf(base or b''))
        open(theirs_file, 'wb').write(lf(theirs))
        ours = os.path.join(ROOT, our_path)
        r = subprocess.run(['git', 'merge-file', '-L', 'ours', '-L', 'base', '-L', 'upstream',
                            ours, base_file, theirs_file])
        conflicts[our_path] = r.returncode
        print(f'merged {up_path} -> {our_path}: {r.returncode} conflict(s)')

    changed = git('diff', '--name-only', old, new).split()
    mapped = set(layout['code']) | {'generated'}
    for path in changed:
        if path in mapped or IGNORED.match(path):
            continue
        if path.startswith('lib/'):
            print(f'LIB changed upstream: {path} - review by hand (see CLAUDE.md on library versions)')
        else:
            print(f'UNMAPPED upstream change: {path} - add to tools/layout.json or port by hand')

    # data: upstream's generated Camelot folder replaces Data/
    gen_old = git('rev-parse', f'{old}:generated').strip()
    gen_new = git('rev-parse', f'{new}:generated').strip()
    gen_repo = os.path.join(CLONE, 'generated')
    git('fetch', '-q', 'origin', cwd=gen_repo)
    data_dst = os.path.join(ROOT, layout['data']['generated/Camelot/'])
    for name in git('ls-tree', '--name-only', f'{gen_new}:Camelot', cwd=gen_repo).split():
        open(os.path.join(data_dst, name), 'wb').write(lf(show(gen_new, f'Camelot/{name}', gen_repo)))
    print(f'data replaced from generated {gen_old[:7]} -> {gen_new[:7]}')

    # localizable keys: upstream's new list plus the keys only we use
    ours_path = os.path.join(ROOT, layout['data']['generated/locale_strings.lua'])
    ours_text = open(ours_path, encoding='utf-8').read()
    up_old = KEY.findall((show(gen_old, 'locale_strings.lua', gen_repo) or b'').decode('utf-8'))
    up_new_text = show(gen_new, 'locale_strings.lua', gen_repo).decode('utf-8').replace('\r\n', '\n')
    up_new = set(KEY.findall(up_new_text))
    extra = [k for k in KEY.findall(ours_text) if k not in up_new and k not in set(up_old)]
    i = up_new_text.index('}) do')
    up_new_text = up_new_text[:i] + ''.join(f'  "{k}",\n' for k in extra) + up_new_text[i:]
    open(ours_path, 'w', encoding='utf-8', newline='\n').write(up_new_text)
    print(f'locale keys: upstream {len(up_new)}, ours only {len(extra)}')

    # saved variables keep our names
    for our_path in conflicts:
        p = os.path.join(ROOT, our_path)
        s = open(p, encoding='utf-8', newline='').read()
        for a, b in SAVED_VARS.items():
            s = s.replace(a, b)
        open(p, 'w', encoding='utf-8', newline='').write(s)

    open_conflicts = {p: n for p, n in conflicts.items() if n}
    print('\nconflicts to resolve:' if open_conflicts else '\nno conflicts')
    for p, n in open_conflicts.items():
        print(f'  {p}: {n}')
    print('next: resolve, diff each file against upstream for leftovers, python tools/check.py,'
          f' set the merge base in CLAUDE.md to {new}')


if __name__ == '__main__':
    main()
