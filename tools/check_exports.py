"""Every sc.<module>.<name> the addon reads must be defined somewhere.

A merge or refactor that drops or renames a module export leaves callers
reading nil; Lua only fails when that line runs. This lists each
sc.<module>.<name> read that no file assigns.

    python tools/check_exports.py
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# entries the generated data carries for some classes only; every read is
# guarded by an existence check
OPTIONAL = {
    ('lookups', 'averaged_procs'),
}


def toc_files():
    toc = os.path.join(ROOT, 'SpellCodaForever.toc')
    for line in open(toc, encoding='utf-8'):
        line = line.strip()
        if line.endswith('.lua') and not line.startswith('#') and not line.startswith('lib/'):
            yield line


def main():
    defined = set()
    reads = []
    for rel in toc_files():
        text = open(os.path.join(ROOT, rel), encoding='utf-8').read()
        # local module tables published as sc.<module>
        aliases = dict(re.findall(r'^sc\.(\w+)\s*=\s*(\w+)\s*;?\s*$', text, re.M))
        for module, local in aliases.items():
            # assigned anywhere, also inside functions (not a comparison)
            for name in re.findall(r'(?<![\w.])%s\.(\w+)\s*=(?!=)' % re.escape(local), text):
                defined.add((module, name))
            for name in re.findall(r'^\s*function %s[.:](\w+)' % re.escape(local), text, re.M):
                defined.add((module, name))
        for module, name in re.findall(r'\bsc\.(\w+)\.(\w+)\s*=(?!=)', text):
            defined.add((module, name))
        for module, name in re.findall(r'^function sc\.(\w+)[.:](\w+)', text, re.M):
            defined.add((module, name))
        # tables built in place: sc.x = { name = ..., }
        for module, body in re.findall(r'^sc\.(\w+)\s*=\s*\{(.*?)^\};', text, re.M | re.S):
            for name in re.findall(r'^\s*(\w+)\s*=', body, re.M):
                defined.add((module, name))
        for n, line in enumerate(text.split('\n'), 1):
            code = line.split('--', 1)[0]
            for module, name in re.findall(r'\bsc\.(\w+)\.(\w+)', code):
                reads.append((rel, n, module, name))

    modules = {m for m, _ in defined}
    missing = [(f, n, m, k) for f, n, m, k in reads
               if m in modules and (m, k) not in defined and (m, k) not in OPTIONAL]
    for f, n, m, k in missing:
        print(f'{f}:{n}  sc.{m}.{k} is read but never defined')
    print(f'{len(reads)} reads checked, {len(missing)} undefined')
    return 1 if missing else 0


if __name__ == '__main__':
    sys.exit(main())
