#!/usr/bin/env node
// API-existence lint for SpellCodaForever (taken over from VuloForeverUI's tools).
//
// Walks Core/, UI/ and Modules/ (scope-aware: a local, parameter or upvalue
// named like a global is not a global) and flags any use of a game API that
// does not exist on the 1.60.1 client:
//   global      a free (global) identifier read, `_G.X` or `_G["X"]`, that
//               nothing defines
//   constant    the same for an ALL_CAPS name
//   namespace   C_Foo where the client has no C_Foo
//   member      C_Foo.Bar (also bit./string./table./math./coroutine.) where
//               the namespace exists and Bar is not in it
//   enum        Enum.Foo or Enum.Foo.Bar that does not exist
//   event       an ALL_CAPS string literal passed to a call whose name contains
//               "Event" (RegisterEvent, RegisterUnitEvent, UnregisterEvent,
//               RegisterEventOnce, our own wrappers; also through
//               `for _, e in ipairs({...})` and a list local of the file), or
//               compared with a variable named `event`, that is not an event
//   hook        hooksecurefunc("Name", ...) on a global that does not exist
//   deprecated  exists only through a deprecation shim (loadDeprecationFallbacks)
//   removed     the client's own UI sets it to nil before addons load
//
// Two sources, both pinned to a commit and folded into the committed snapshot
// tools/forever-api.json, so the normal run is OFFLINE:
//   Ketho/BlizzardInterfaceResources `forever`  GlobalAPI (C functions, Lua
//       library, C_ namespaces), FrameXML functions, Frames, Mixins, LuaEnum,
//       Events, GlobalStrings/enUS
//   Gethe/wow-ui-source `forever`  the globals FrameXML defines that no list
//       carries (see scanUiSource)
// `--update` refreshes both and prints what changed -- that diff is the API
// changelog between two client builds.
//
//   node apilint.js                      report what is new since the baseline
//   node apilint.js --all                report everything, baseline ignored
//   node apilint.js --guarded            also list the guarded (tolerated) reads
//   node apilint.js --write-baseline     accept the current findings
//   node apilint.js --update             refresh the snapshot to both branch heads
//        [--sha=<lists commit>] [--ui-sha=<UI source commit>]   ... or to these
//   node apilint.js file.lua ...         lint these files instead of the addon
//
// GUARDED reads are informational and never fail: the code already survives
// the name being absent. The heuristic, and where it stops:
//   - the read IS the tested operand: `if X then`, `X and ..`, `X or ..`,
//     `not X`, `X == nil` / `X ~= nil`, `type(X)`, `pcall(X, ..)`
//   - the read sits inside `if X then <here> end`, or right of `X and <here>`
//   - the read follows `if not X then return end` in the same block
//   - `local f = X` and the SAME FUNCTION tests `f` anywhere
// Keys are syntactic (`C_Foo.Bar`, `_G.X` == `X`), so a test through another
// alias, a helper function, or a table field set elsewhere is not seen and the
// read is reported as unguarded. A test on the condition side counts for the
// whole condition, so `if X() and X then` passes although X() runs first. An
// `else` branch gets nothing (it runs when the test FAILED). Good enough to
// sort "may crash" from "already tolerates absence", not a proof.

const fs = require('fs');
const path = require('path');
const luaparse = require('luaparse');

const ROOT = path.resolve(__dirname, '..');
const TOC = path.join(ROOT, 'SpellCodaForever.toc');
const SNAPSHOT = path.join(__dirname, 'forever-api.json');
const BASELINE = path.join(__dirname, 'apilint-baseline.json');
const REPO = 'Ketho/BlizzardInterfaceResources';
const BRANCH = 'forever';
const SCAN_DIRS = ['Core', 'UI', 'Modules'];
// TOC-loaded code that is not ours to lint but defines globals we may read
const DEFINE_ONLY_DIRS = ['Libs', 'Dev'];

// Not in any generated list, but part of every Lua environment in the client.
// Each entry here was checked absent from GlobalAPI.lua before being added.
const LUA_EXTRA = new Set(['_G', '_VERSION', 'self']);
// Member reads on a C-side namespace that are data, not functions
const MEMBER_OK = new Set(['math.huge', 'math.pi']);

const ALL_CAPS = /^[A-Z][A-Z0-9_]*$/;

// ---------------------------------------------------------------------------
// Snapshot
// ---------------------------------------------------------------------------

function strVal(n) {
    if (!n || n.type !== 'StringLiteral') return null;
    if (typeof n.value === 'string') return n.value;
    const raw = n.raw || '';
    if (raw.startsWith('[')) {
        const m = /^\[(=*)\[([\s\S]*)\]\1\]$/.exec(raw);
        return m ? m[2] : raw;
    }
    return raw.slice(1, -1);
}

function eachNode(node, cb) {
    if (!node || typeof node !== 'object') return;
    if (Array.isArray(node)) { for (const n of node) eachNode(n, cb); return; }
    if (node.type) cb(node);
    for (const k of Object.keys(node)) {
        if (k === 'type' || k === 'loc' || k === 'range') continue;
        eachNode(node[k], cb);
    }
}

const parseRes = (src) => luaparse.parse(src, { luaVersion: '5.1', comments: false });
const allStrings = (src) => {
    const out = [];
    eachNode(parseRes(src), (n) => { const s = strVal(n); if (s !== null) out.push(s); });
    return out;
};
const uniqSort = (a) => [...new Set(a)].sort();

function buildSnapshot(raw, sha) {
    // GlobalAPI.lua: return {GlobalAPI, LuaAPI}, "C_Item.GetItemInfo" style
    const globals = [], namespaces = {};
    for (const s of allStrings(raw.GlobalAPI)) {
        const dot = s.indexOf('.');
        if (dot < 0) { globals.push(s); continue; }
        const ns = s.slice(0, dot), fn = s.slice(dot + 1);
        (namespaces[ns] = namespaces[ns] || []).push(fn);
        globals.push(ns);
    }
    for (const k of Object.keys(namespaces)) namespaces[k] = uniqSort(namespaces[k]);

    // FrameXML.lua / Frames.lua: return {main, LoadOnDemand}; both count --
    // a load-on-demand name is real once its addon is loaded
    const framexml = uniqSort(allStrings(raw.FrameXML));
    const frames = uniqSort(allStrings(raw.Frames));
    const mixins = uniqSort(allStrings(raw.Mixins));
    const events = uniqSort(allStrings(raw.Events));

    // LuaEnum.lua: Enum = {...}, Constants = {...}, LE_* = n
    const enums = {}, constants = [];
    for (const st of parseRes(raw.LuaEnum).body) {
        if (st.type !== 'AssignmentStatement') continue;
        st.variables.forEach((v, i) => {
            if (v.type !== 'Identifier') return;
            constants.push(v.name);
            const init = st.init[i];
            if (v.name !== 'Enum' || !init || init.type !== 'TableConstructorExpression') return;
            for (const f of init.fields) {
                if (f.type !== 'TableKeyString') continue;
                const members = [];
                if (f.value.type === 'TableConstructorExpression') {
                    for (const m of f.value.fields) if (m.type === 'TableKeyString') members.push(m.key.name);
                }
                enums[f.key.name] = uniqSort(members);
            }
        });
    }

    // GlobalStrings/enUS.lua: NAME = "..." and _G["NAME"] = "...", one per
    // line. Read line by line, not parsed: the generated file is not valid Lua
    // (1.60.1 ships a string named `Tests Iacobellis`, with a space), and one
    // bad line must not cost us the other 25000.
    const strings = [];
    for (const line of raw.GlobalStrings.split(/\r?\n/)) {
        const m = /^(?:([A-Za-z_][A-Za-z0-9_]*)|_G\["([A-Za-z_][A-Za-z0-9_]*)"\])\s*=/.exec(line);
        if (m) strings.push(m[1] || m[2]);
    }

    const sorted = {};
    for (const k of Object.keys(enums).sort()) sorted[k] = enums[k];
    const sortedNs = {};
    for (const k of Object.keys(namespaces).sort()) sortedNs[k] = namespaces[k];
    return {
        source: REPO + '@' + BRANCH,
        sha,
        fetched: new Date().toISOString().slice(0, 10),
        globals: uniqSort(globals),
        namespaces: sortedNs,
        enums: sorted,
        events,
        frames,
        framexml,
        mixins,
        constants: uniqSort(constants),
        strings: uniqSort(strings),
    };
}

// ---------------------------------------------------------------------------
// Globals the client's own UI code defines
// ---------------------------------------------------------------------------
// The generated lists carry functions, frames, mixins and strings, but not the
// global TABLES and frames FrameXML creates (SlashCmdList, RAID_CLASS_COLORS,
// DEFAULT_CHAT_FRAME, Minimap, StaticPopupDialogs, ...). Those come from the
// client source itself: Gethe/wow-ui-source, branch `forever`, pinned like the
// lists. The forever branch ALSO ships the classic FrameXML, so the TOCs are
// resolved the way the client does for game type camelot -- a name defined only
// in a file that never loads here must not count as existing:
//   [AllowLoadGameType a, b]   loads if a or b is camelot or mainline (the
//                              family; `[ExcludeLoadGameType camelot]` is how a
//                              mainline file opts out)
//   [Family] / [Game]          Mainline/ and Camelot/
//   [AllowLoad glue]           login screens only, skipped
//   [AllowLoadTextLocale X]    only when X is enUS
//   ## UseSecureEnvironment    the addon's Lua runs in a private environment:
//                              only files marked [LoadIntoEnvironment global]
//                              count, and from the others only explicit
//                              `_G.X = ...` exports
// XML files are followed through <Script file> and <Include file>.
const UI_REPO = 'Gethe/wow-ui-source';
const GAME_TYPES = new Set(['camelot', 'mainline']);

function untar(buf) {
    const out = new Map();
    let off = 0, longName = null;
    while (off + 512 <= buf.length) {
        const h = buf.subarray(off, off + 512);
        if (h.every((b) => b === 0)) break;
        const str = (a, b) => h.subarray(a, b).toString('utf8').replace(/\0.*$/s, '');
        let name = str(0, 100);
        const prefix = str(345, 500);
        if (prefix) name = prefix + '/' + name;
        const size = parseInt(str(124, 136).trim() || '0', 8);
        const type = String.fromCharCode(h[156] || 48);
        const data = buf.subarray(off + 512, off + 512 + size);
        off += 512 + Math.ceil(size / 512) * 512;
        if (type === 'x') {
            const m = /\d+ path=([^\n]*)\n/.exec(data.toString('utf8'));
            if (m) longName = m[1];
            continue;
        }
        if (type === 'L') { longName = data.toString('utf8').replace(/\0.*$/s, ''); continue; }
        if (type === 'g') continue;
        if (longName) { name = longName; longName = null; }
        if (type === '0' || type === '\0') out.set(name, data);
    }
    return out;
}

function scanUiSource(tar) {
    // path below Interface/AddOns, lower-cased -> text
    const files = new Map();
    for (const [name, data] of tar) {
        const i = name.indexOf('/Interface/AddOns/');
        if (i < 0) continue;
        files.set(name.slice(i + '/Interface/AddOns/'.length).toLowerCase(), data.toString('utf8'));
    }
    const listFile = [...tar.keys()].find((n) => /\/Interface\/ui-toc-list\.txt$/.test(n));
    const tocs = tar.get(listFile).toString('utf8').split(/\r?\n/)
        .map((l) => l.trim().replace(/\\/g, '/').replace(/^Interface\/AddOns\//i, '')).filter(Boolean);

    const globals = new Set(), prefixes = new Set(), suffixes = new Set(), deprecated = new Set(), removed = new Set();
    const stats = { addons: 0, files: 0, skipped: 0, luaErrors: 0, handlerErrors: 0, deprecated: 0 };
    const seen = new Set();
    const list = (v) => v.split(',').map((s) => s.trim().toLowerCase()).filter(Boolean);

    // conditions of one TOC line / header: false = does not load here
    function loads(conds) {
        let env = null;
        const re = /\[(\w+)\s*([^\]]*)\]/g;
        let m;
        while ((m = re.exec(conds)) !== null) {
            const k = m[1].toLowerCase(), v = list(m[2]);
            if (k === 'allowloadgametype' && !v.some((x) => GAME_TYPES.has(x))) return false;
            if (k === 'excludeloadgametype' && v.some((x) => GAME_TYPES.has(x))) return false;
            if (k === 'allowload' && !v.some((x) => x === 'game' || x === 'both')) return false;
            if (k === 'allowloadtextlocale' && !v.includes('enus')) return false;
            if (k === 'loadintoenvironment') env = v[0];
        }
        return { env };
    }

    function luaGlobals(src, secure, handler) {
        let ast;
        // 5.2 mode: luaparse's 5.1 grammar rejects `break;` (a semicolon after
        // break is legal 5.1, and FrameXML writes it 270 times); some files
        // also start with a byte-order mark
        if (src.charCodeAt(0) === 0xFEFF) src = src.slice(1);
        try { ast = luaparse.parse(src, { luaVersion: '5.2', scope: true }); }
        catch (e) {
            if (handler) { stats.handlerErrors++; return; }
            stats.luaErrors++;
            // column-0 definitions still tell us most of what the file defines
            if (secure) return;
            for (const line of src.split(/\r?\n/)) {
                const m = /^(?:function\s+([A-Za-z_]\w*)\s*\(|([A-Za-z_]\w*)\s*=[^=])/.exec(line);
                if (m) globals.add(m[1] || m[2]);
            }
            return;
        }
        // Deprecation shims open with `if not GetCVarBool("loadDeprecationFallbacks")
        // then return end`. The CVar defaults to 1, so what they define does
        // exist -- but only as a fallback that a player can switch off and the
        // next build can drop, i.e. exactly the old API rule 1 forbids. Kept as
        // a list of its own, reported as `deprecated`.
        let target = globals;
        for (const st of ast.body) {
            if (st.type !== 'IfStatement' || st.clauses.length !== 1 || !exits(st.clauses[0].body)) continue;
            let dep = false;
            eachNode(st.clauses[0].condition, (n) => { if (strVal(n) === 'loadDeprecationFallbacks') dep = true; });
            if (dep) { stats.deprecated++; target = deprecated; break; }
        }
        const add = (n) => { if (n && /^[A-Za-z_]\w*$/.test(n)) target.add(n); };
        const topLevel = new Set(ast.body);
        eachNode(ast, (n) => {
            if (n.type === 'AssignmentStatement') {
                n.variables.forEach((v, i) => {
                    const raw = exprKeyRaw(v);
                    const name = v.type === 'Identifier' && !v.isLocal && !secure ? v.name
                        : raw && raw.startsWith('_G.') ? raw.split('.')[1] : null;
                    if (!name) return;
                    // `X = nil` at file level takes a name OUT of the addon
                    // environment (EnvironmentCleanup does it to
                    // loadstring_untainted and the store API, which the lists
                    // still carry because the client defines them first)
                    const init = n.init[i];
                    if (init && init.type === 'NilLiteral') { if (topLevel.has(n) && !secure) removed.add(name); }
                    else add(name);
                });
            } else if (!secure && n.type === 'FunctionDeclaration' && !n.isLocal && n.identifier
                       && n.identifier.type === 'Identifier' && !n.identifier.isLocal) {
                add(n.identifier.name);
            } else if (!secure && n.type === 'CallExpression' && n.base.type === 'Identifier' && n.base.name === 'CreateFrame') {
                const s = strVal(n.arguments[1]);
                if (s && s.startsWith('$parent')) suffixes.add(s.slice(7)); else add(s);
            } else if (n.type === 'BinaryExpression' && n.operator === '..') {
                // "ActionButton"..i  /  parent:GetName().."Tab": frames named at
                // run time. Kept as patterns, see isUiName in the lint.
                const l = strVal(n.left), r = strVal(n.right);
                if (l && /^[A-Za-z_]\w*$/.test(l)) prefixes.add(l);
                if (r && /^[A-Za-z_]\w*$/.test(r)) suffixes.add(r);
            }
        });
    }

    const unxml = (s) => s.replace(/&lt;/g, '<').replace(/&gt;/g, '>').replace(/&quot;/g, '"')
        .replace(/&apos;/g, "'").replace(/&amp;/g, '&');

    function xmlFile(rel, secure) {
        if (seen.has(rel.toLowerCase())) return;
        seen.add(rel.toLowerCase());
        const src = files.get(rel.toLowerCase());
        if (src === undefined) { stats.skipped++; return; }
        const dir = rel.includes('/') ? rel.slice(0, rel.lastIndexOf('/') + 1) : '';
        const text = src.replace(/<!--[\s\S]*?-->/g, '').replace(/<!\[CDATA\[[\s\S]*?\]\]>/g, '');
        const stack = [];
        const re = /<(\/?)([A-Za-z_][\w:.-]*)((?:\s+[\w:.-]+\s*=\s*"[^"]*")*)\s*(\/?)>/g;
        let m;
        while ((m = re.exec(text)) !== null) {
            const [, close, tag, attrs, selfClose] = m;
            if (close) {
                const i = stack.map((s) => s.tag).lastIndexOf(tag);
                if (i >= 0) stack.length = i;
                continue;
            }
            const a = {};
            attrs.replace(/([\w:.-]+)\s*=\s*"([^"]*)"/g, (_, k, v) => { a[k.toLowerCase()] = v; });
            const virt = /^true$/i.test(a.virtual || '') || stack.some((s) => s.virt);
            if ((tag === 'Script' || tag === 'Include') && a.file) {
                const p = (dir + a.file.replace(/\\/g, '/')).replace(/[^/]+\/\.\.\//g, '');
                if (/\.xml$/i.test(p)) xmlFile(p, secure); else luaFile(p, secure);
            } else if (a.name && a.name.startsWith('$parent')) {
                suffixes.add(a.name.slice(7));
            } else if (a.name && !a.name.includes('$') && !secure
                       // a Font is a global object even when declared virtual
                       && (!virt || tag === 'Font' || tag === 'FontFamily')) {
                globals.add(a.name);
            }
            if (!selfClose) stack.push({ tag, virt });
        }
        // inline handlers and <Script> blocks: `GENERAL_CHAT_DOCK = self` in an
        // OnLoad is how some globals come to exist
        const hre = /<(On\w+|Script)\b[^>]*?(?<!\/)>([\s\S]*?)<\/\1>/g;
        while ((m = hre.exec(text)) !== null) {
            if (m[2].trim()) luaGlobals(unxml(m[2]), secure, true);
        }
    }

    function luaFile(rel, secure) {
        const key = rel.toLowerCase();
        if (seen.has(key)) return;
        seen.add(key);
        const src = files.get(key);
        if (src === undefined) { stats.skipped++; return; }
        stats.files++;
        luaGlobals(src, secure);
    }

    for (const toc of tocs) {
        const src = files.get(toc.toLowerCase());
        if (src === undefined) continue;
        const dir = toc.slice(0, toc.lastIndexOf('/') + 1);
        const lines = src.split(/\r?\n/);
        let ok = true, secureAddon = false;
        for (const line of lines) {
            const h = /^##\s*([\w-]+)\s*:\s*([^\[]*)(.*)$/.exec(line);
            if (!h) continue;
            const k = h[1].toLowerCase(), v = list(h[2]);
            if (h[3] && !loads(h[3])) continue;       // a header that does not apply here
            if (k === 'allowloadgametype' && !v.some((x) => GAME_TYPES.has(x))) ok = false;
            if (k === 'excludeloadgametype' && v.some((x) => GAME_TYPES.has(x))) ok = false;
            if (k === 'allowload' && !v.some((x) => x === 'game' || x === 'both')) ok = false;
            if (k === 'usesecureenvironment' && v[0] === '1') secureAddon = true;
        }
        if (!ok) continue;
        stats.addons++;
        for (const line of lines) {
            if (/^\s*#/.test(line) || !line.trim()) continue;
            const m = /^\s*(\S+)(.*)$/.exec(line);
            const cond = loads(m[2]);
            if (!cond) continue;
            const secure = secureAddon ? cond.env !== 'global' : cond.env === 'secure';
            const file = dir + m[1].replace(/\[Family\]/gi, 'Mainline').replace(/\[Game\]/gi, 'Camelot').replace(/\\/g, '/');
            if (/\.xml$/i.test(file)) xmlFile(file, secure);
            else if (/\.lua$/i.test(file)) luaFile(file, secure);
        }
    }
    return { globals, prefixes, suffixes, deprecated, removed, stats };
}

// One entry per line: the file is committed, and a new build should show up
// in git as a readable list of added and removed names.
function writeSnapshot(snap) {
    const q = JSON.stringify;
    // no indentation on the 60000 name lines: a fifth of the file otherwise
    const arr = (a, ind) => a.length ? '[\n' + a.map((s) => q(s)).join(',\n') + '\n' + ind + ']' : '[]';
    const obj = (o) => '{\n' + Object.keys(o).map((k) => '    ' + q(k) + ': ' + arr(o[k], '    ')).join(',\n') + '\n  }';
    const parts = [];
    for (const k of Object.keys(snap)) {
        const v = snap[k];
        if (Array.isArray(v)) parts.push('  ' + q(k) + ': ' + arr(v, '  '));
        else if (v && typeof v === 'object') parts.push('  ' + q(k) + ': ' + obj(v));
        else parts.push('  ' + q(k) + ': ' + q(v));
    }
    fs.writeFileSync(SNAPSHOT, '{\n' + parts.join(',\n') + '\n}\n');
}

function flatNs(snap) {
    const out = [];
    for (const [k, fns] of Object.entries(snap.namespaces || {})) for (const f of fns) out.push(k + '.' + f);
    return out;
}
function flatEnums(snap) {
    const out = [];
    for (const [k, ms] of Object.entries(snap.enums || {})) {
        out.push('Enum.' + k);
        for (const m of ms) out.push('Enum.' + k + '.' + m);
    }
    return out;
}

function printDiff(prev, next) {
    if (!prev) { console.log('no previous snapshot - nothing to compare'); return; }
    const sets = [
        ['globals', (s) => s.globals],
        ['FrameXML functions', (s) => s.framexml],
        ['frames', (s) => s.frames],
        ['namespace functions', flatNs],
        ['enums', flatEnums],
        ['events', (s) => s.events],
        ['UI-defined globals', (s) => s.ui],
        ['deprecation fallbacks', (s) => s.deprecated],
        ['removed by the UI at load', (s) => s.removed],
    ];
    let any = false;
    for (const [label, get] of sets) {
        const a = new Set(get(prev) || []), b = new Set(get(next) || []);
        const added = [...b].filter((x) => !a.has(x)).sort();
        const removed = [...a].filter((x) => !b.has(x)).sort();
        if (!added.length && !removed.length) continue;
        any = true;
        console.log('\n' + label + ': +' + added.length + ' -' + removed.length);
        for (const x of added) console.log('  + ' + x);
        for (const x of removed) console.log('  - ' + x);
    }
    const sa = new Set(prev.strings || []), sb = new Set(next.strings || []);
    const sAdd = [...sb].filter((x) => !sa.has(x)).length, sRem = [...sa].filter((x) => !sb.has(x)).length;
    if (sAdd || sRem) { any = true; console.log('\nglobal strings: +' + sAdd + ' -' + sRem + ' (not listed)'); }
    if (!any) console.log('no API change (lists ' + prev.sha.slice(0, 7) + ' -> ' + next.sha.slice(0, 7)
        + ', UI source ' + (prev.uiSha || '?').slice(0, 7) + ' -> ' + (next.uiSha || '?').slice(0, 7) + ')');
}

async function update(argv) {
    const get = async (url, json) => {
        const res = await fetch(url, { headers: { 'User-Agent': 'vuloforeverui-apilint' } });
        if (!res.ok) throw new Error(url + ' -> HTTP ' + res.status);
        return json ? res.json() : res.text();
    };
    const head = async (repo, arg) => {
        const a = argv.find((x) => x.startsWith(arg + '='));
        if (a) return a.slice(arg.length + 1);
        const sha = (await get('https://api.github.com/repos/' + repo + '/commits/' + BRANCH, true)).sha;
        console.log('newest ' + repo + ' ' + BRANCH + ' commit: ' + sha);
        return sha;
    };
    const sha = await head(REPO, '--sha');
    const uiSha = await head(UI_REPO, '--ui-sha');

    const base = 'https://raw.githubusercontent.com/' + REPO + '/' + sha + '/Resources/';
    const names = { GlobalAPI: 'GlobalAPI.lua', FrameXML: 'FrameXML.lua', Frames: 'Frames.lua',
        Mixins: 'Mixins.lua', Events: 'Events.lua', LuaEnum: 'LuaEnum.lua', GlobalStrings: 'GlobalStrings/enUS.lua' };
    const raw = {};
    for (const [k, f] of Object.entries(names)) { raw[k] = await get(base + f, false); }
    const next = buildSnapshot(raw, sha);

    const tgz = await fetch('https://codeload.github.com/' + UI_REPO + '/tar.gz/' + uiSha,
        { headers: { 'User-Agent': 'vuloforeverui-apilint' } });
    if (!tgz.ok) throw new Error(UI_REPO + ' tarball -> HTTP ' + tgz.status);
    const tar = untar(require('zlib').gunzipSync(Buffer.from(await tgz.arrayBuffer())));
    const verFile = [...tar.keys()].find((n) => /^[^/]+\/version\.txt$/.test(n));
    const ui = scanUiSource(tar);
    const listed = new Set([...next.globals, ...next.frames, ...next.mixins, ...next.constants, ...next.strings]);
    for (const f of next.framexml) listed.add(f.split('.')[0]);
    // only what the lists do not already carry: keeps the file small and the
    // diff between builds about real changes
    next.ui = [...ui.globals].filter((n) => !listed.has(n)).sort();
    next.deprecated = [...ui.deprecated].filter((n) => !listed.has(n) && !ui.globals.has(n)).sort();
    next.removed = [...ui.removed].filter((n) => !ui.globals.has(n)).sort();
    next.uiSource = UI_REPO + '@' + BRANCH;
    next.uiSha = uiSha;
    next.uiBuild = verFile ? tar.get(verFile).toString('utf8').trim() : '?';
    next.uiPrefixes = [...ui.prefixes].sort();
    next.uiSuffixes = [...ui.suffixes].sort();
    console.log('UI source ' + next.uiBuild + ': ' + ui.stats.addons + ' addons and ' + ui.stats.files
        + ' Lua files load for camelot (' + ui.stats.luaErrors + ' unparsed, read by line), '
        + next.ui.length + ' globals beyond the lists; ' + ui.stats.skipped + ' referenced files missing, '
        + ui.stats.handlerErrors + ' XML handlers unparsed; ' + ui.stats.deprecated + ' deprecation shims define '
        + next.deprecated.length + ' fallback-only names');

    const prev = fs.existsSync(SNAPSHOT) ? JSON.parse(fs.readFileSync(SNAPSHOT, 'utf8')) : null;
    printDiff(prev, next);
    const { source, fetched, uiSource, uiBuild, ...rest } = next;
    writeSnapshot({ source, sha: next.sha, uiSource, uiSha, uiBuild, fetched, ...rest });
    console.log('\nwrote ' + path.relative(ROOT, SNAPSHOT) + ' (' + sha.slice(0, 7) + ', '
        + next.globals.length + ' globals, ' + Object.keys(next.namespaces).length + ' namespaces, '
        + next.events.length + ' events, ' + Object.keys(next.enums).length + ' enums)');
}

// ---------------------------------------------------------------------------
// Lint
// ---------------------------------------------------------------------------

let _api = null;
function loadApi() {
    if (_api) return _api;
    if (!fs.existsSync(SNAPSHOT)) return null;
    const snap = JSON.parse(fs.readFileSync(SNAPSHOT, 'utf8'));
    const known = new Set([...snap.globals, ...snap.frames, ...snap.mixins, ...snap.constants,
        ...snap.strings, ...(snap.ui || []), ...LUA_EXTRA]);
    for (const f of snap.framexml) known.add(f.split('.')[0]);
    for (const r of snap.removed || []) known.delete(r);
    const ns = {};
    for (const [k, fns] of Object.entries(snap.namespaces)) ns[k] = new Set(fns);
    const enums = {};
    for (const [k, ms] of Object.entries(snap.enums)) enums[k] = new Set(ms);
    // Frames the client names at run time: "ActionButton"..i gives
    // ActionButton1..n, and a template child "$parentResizeButton" (or a
    // parent:GetName().."Tab") gives ChatFrame1ResizeButton. A name counts if
    // it is a known name followed by a recorded suffix, or a recorded prefix
    // followed by digits -- recursively, so ChatFrame1Tab resolves too.
    const prefixes = new Set(snap.uiPrefixes || []), suffixes = new Set(snap.uiSuffixes || []);
    // Only a FRAME may carry a suffix: GetItem + "Info" must not make
    // GetItemInfo exist just because some file concatenates .."Info".
    const frameish = new Set([...snap.frames, ...(snap.ui || [])]);
    const memo = new Map();
    const isFrameName = (n, depth) => {
        if (frameish.has(n)) return true;
        const key = n + '|' + depth;
        if (memo.has(key)) return memo.get(key);
        let ok = false;
        const d = /^(.*?)(\d+)$/.exec(n);
        if (d && prefixes.has(d[1])) ok = true;
        for (let i = n.length - 1; !ok && i > 0 && depth < 4; i--) {
            if (suffixes.has(n.slice(i)) && isFrameName(n.slice(0, i), depth + 1)) ok = true;
        }
        memo.set(key, ok);
        return ok;
    };
    const removed = new Set(snap.removed || []);
    const isUiName = (n) => !removed.has(n) && (known.has(n) || isFrameName(n, 0));
    _api = { snap, known, ns, enums, events: new Set(snap.events), isUiName, removed,
        deprecated: new Set(snap.deprecated || []) };
    return _api;
}

function walkLua(dir, out) {
    if (!fs.existsSync(dir)) return out;
    for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
        const p = path.join(dir, e.name);
        if (e.isDirectory()) walkLua(p, out);
        else if (e.name.endsWith('.lua')) out.push(p);
    }
    return out;
}

// 5.2 grammar: this codebase writes `break;`, which the 5.1 grammar rejects
const parseFile = (f) => luaparse.parse(fs.readFileSync(f, 'utf8'),
    { luaVersion: '5.2', scope: true, locations: true, comments: false });

// Names the addon (and its bundled libraries) defines itself: bare global
// writes, _G.X = ..., CreateFrame(type, "Name"), and the TOC saved variables.
function ownGlobals(files) {
    // LibStub.lua writes itself as _G[LIBSTUB_MAJOR], a computed key
    const own = new Set(['LibStub']);
    if (fs.existsSync(TOC)) {
        for (const line of fs.readFileSync(TOC, 'utf8').split(/\r?\n/)) {
            const m = /^##\s*SavedVariables(?:PerCharacter)?\s*:\s*(.*)$/.exec(line);
            if (m) for (const v of m[1].split(',')) if (v.trim()) own.add(v.trim());
        }
    }
    for (const f of files) {
        let ast;
        try { ast = parseFile(f); } catch (e) { continue; }
        eachNode(ast, (n) => {
            if (n.type === 'AssignmentStatement') {
                for (const v of n.variables) {
                    if (v.type === 'Identifier' && !v.isLocal) own.add(v.name);
                    const k = exprKey(v);
                    if (k && v.type !== 'Identifier' && /^_G\./.test(exprKeyRaw(v))) own.add(k.split('.')[0]);
                }
            } else if (n.type === 'FunctionDeclaration' && !n.isLocal && n.identifier
                       && n.identifier.type === 'Identifier' && !n.identifier.isLocal) {
                own.add(n.identifier.name);
            } else if (n.type === 'CallExpression' && n.base.type === 'Identifier' && n.base.name === 'CreateFrame') {
                const s = strVal(n.arguments[1]);
                if (s && /^[A-Za-z_][A-Za-z0-9_]*$/.test(s)) own.add(s);
            }
        });
    }
    return own;
}

// `C_Foo.Bar`, `_G["X"]` -> "X", `a.b.c`; null for anything computed
function exprKeyRaw(n) {
    if (!n) return null;
    if (n.type === 'Identifier') return n.name;
    if (n.type === 'MemberExpression' && n.indexer === '.') {
        const b = exprKeyRaw(n.base);
        return b === null ? null : b + '.' + n.identifier.name;
    }
    if (n.type === 'IndexExpression') {
        const s = strVal(n.index);
        const b = exprKeyRaw(n.base);
        return (s === null || b === null) ? null : b + '.' + s;
    }
    return null;
}
function exprKey(n) {
    const k = exprKeyRaw(n);
    return k && k.startsWith('_G.') ? k.slice(3) : k;
}

// keys an expression tests for truth / existence
function tested(e, out) {
    out = out || new Set();
    if (!e) return out;
    const k = exprKey(e);
    if (k) { out.add(k); return out; }
    if (e.type === 'LogicalExpression') { tested(e.left, out); tested(e.right, out); }
    else if (e.type === 'UnaryExpression' && e.operator === 'not') tested(e.argument, out);
    else if (e.type === 'BinaryExpression' && (e.operator === '==' || e.operator === '~=')) {
        for (const [a, b] of [[e.left, e.right], [e.right, e.left]]) {
            if (b.type === 'NilLiteral') tested(a, out);
            if (isTypeCall(a)) tested(a.arguments[0], out);
        }
    } else if (isTypeCall(e)) tested(e.arguments[0], out);
    return out;
}
// keys known to EXIST after `if <e> then return end` falls through
function negTested(e, out) {
    out = out || new Set();
    if (!e) return out;
    if (e.type === 'UnaryExpression' && e.operator === 'not') tested(e.argument, out);
    else if (e.type === 'LogicalExpression' && e.operator === 'or') { negTested(e.left, out); negTested(e.right, out); }
    else if (e.type === 'BinaryExpression' && e.operator === '==') {
        if (e.right.type === 'NilLiteral') tested(e.left, out);
        if (e.left.type === 'NilLiteral') tested(e.right, out);
    }
    return out;
}
const isTypeCall = (e) => e && e.type === 'CallExpression' && e.base.type === 'Identifier'
    && e.base.name === 'type' && !e.base.isLocal && e.arguments.length > 0;
const union = (g, s) => { if (!s.size) return g; const n = new Set(g); for (const x of s) n.add(x); return n; };
const exits = (body) => {
    const last = body[body.length - 1];
    if (!last) return false;
    if (last.type === 'ReturnStatement' || last.type === 'BreakStatement') return true;
    return last.type === 'CallStatement' && last.expression.base.type === 'Identifier' && last.expression.base.name === 'error';
};

function lintFile(file, rel, api, own) {
    let ast;
    try { ast = parseFile(file); } catch (e) { return { hits: [], parseError: e.message }; }
    const hits = [];
    const pending = [];              // reads assigned to a local: guarded if the function tests it
    const fnTests = new Map();       // function node -> keys tested anywhere inside it
    const lists = new Map();         // key -> [string literals] of a table constructor
    const fnStack = [ast];

    const noteTests = (keys) => { for (const f of fnStack) { const s = fnTests.get(f) || new Set(); for (const k of keys) s.add(k); fnTests.set(f, s); } };
    const hit = (kind, name, node, guarded, extra) => {
        const h = { file: rel, line: node.loc.start.line, kind, name, guarded: !!guarded };
        hits.push(h);
        if (extra && extra.local && !guarded) pending.push({ h, local: extra.local, fn: fnStack[fnStack.length - 1] });
    };
    const isKnown = (name) => own.has(name) || api.isUiName(name);

    // table constructors of plain strings, for `for _, e in ipairs(LIST) do X:RegisterEvent(e)`
    eachNode(ast, (n) => {
        const pairsOf = (vars, inits) => vars.forEach((v, i) => {
            const init = inits[i];
            if (!init || init.type !== 'TableConstructorExpression') return;
            const ss = init.fields.filter((f) => f.type === 'TableValue').map((f) => f.value)
                .filter((x) => strVal(x) !== null);
            const k = exprKey(v);
            if (k && ss.length) lists.set(k, ss);
        });
        if (n.type === 'LocalStatement' || n.type === 'AssignmentStatement') pairsOf(n.variables, n.init || []);
    });

    function checkEventLiteral(lit) {
        const s = strVal(lit);
        if (s === null || !ALL_CAPS.test(s)) return;
        if (!api.events.has(s)) hit('event', s, lit, false);
    }
    function checkEventArg(a, ctx) {
        if (!a) return;
        if (a.type === 'StringLiteral') return checkEventLiteral(a);
        if (a.type === 'Identifier' && ctx.loops.has(a.name)) for (const lit of ctx.loops.get(a.name)) checkEventLiteral(lit);
    }

    // a read of a global name (possibly through _G), with its member chain
    function globalRead(name, rest, node, g, extra) {
        if (name === '_G' && rest.length === 0) return;
        const guardedName = g.has(name);
        if (!isKnown(name)) {
            const kind = api.deprecated.has(name) ? 'deprecated' : api.removed.has(name) ? 'removed'
                : /^C_/.test(name) ? 'namespace' : ALL_CAPS.test(name) ? 'constant' : 'global';
            hit(kind, name, node, guardedName, rest.length ? null : extra);
            return;
        }
        if (rest.length === 0) return;
        const m = rest[0], full = name + '.' + m;
        if (api.ns[name] && !own.has(name)) {
            if (!api.ns[name].has(m) && !MEMBER_OK.has(full)) hit('member', full, node, g.has(full), rest.length === 1 ? extra : null);
        } else if (name === 'Enum') {
            if (!api.enums[m]) hit('enum', full, node, g.has(full), rest.length === 1 ? extra : null);
            else if (rest.length > 1 && !api.enums[m].has(rest[1])) {
                const f2 = full + '.' + rest[1];
                hit('enum', f2, node, g.has(f2), rest.length === 2 ? extra : null);
            }
        }
    }

    // MemberExpression / IndexExpression chain rooted in a global identifier
    function member(e, ctx, extra) {
        const segs = [];
        let n = e;
        while (n.type === 'MemberExpression' || n.type === 'IndexExpression') { segs.unshift(n); n = n.base; }
        // the literal chain from the root up to the first computed index:
        // `Enum.PowerType[x]` checks Enum.PowerType, `_G[name]` checks nothing
        const chain = [];
        let broken = false;
        for (const s of segs) {
            const name = s.type === 'MemberExpression' ? s.identifier.name : strVal(s.index);
            if (name === null) { expr(s.index, ctx); broken = true; }
            else if (!broken) chain.push(name);
        }
        if (n.type !== 'Identifier') return expr(n, ctx);
        if (n.isLocal) return;
        let root = n.name;
        if (root === '_G') { if (!chain.length) return; root = chain.shift(); }
        globalRead(root, chain, e, ctx.g, extra);
    }

    function expr(e, ctx, extra) {
        if (!e) return;
        switch (e.type) {
        case 'Identifier':
            if (!e.isLocal) globalRead(e.name, [], e, ctx.g, extra);
            return;
        case 'MemberExpression':
        case 'IndexExpression':
            return member(e, ctx, extra);
        case 'CallExpression':
        case 'StringCallExpression':
        case 'TableCallExpression': {
            expr(e.base, ctx);
            const args = e.type === 'CallExpression' ? e.arguments
                : e.type === 'StringCallExpression' ? [e.argument] : [e.arguments];
            const callee = e.base.type === 'MemberExpression' ? e.base.identifier.name
                : e.base.type === 'Identifier' ? e.base.name : null;
            let guardFirst = false;
            if (callee === 'type' || callee === 'pcall') guardFirst = true;
            if (callee && /Event/.test(callee)) args.forEach((a) => checkEventArg(a, ctx));
            if (callee === 'pcall' && args[0] && args[0].type === 'MemberExpression' && /Event/.test(args[0].identifier.name)) {
                args.slice(1).forEach((a) => checkEventArg(a, ctx));
            }
            if (callee === 'hooksecurefunc' && args.length === 2) {
                const s = strVal(args[0]);
                if (s !== null && !isKnown(s)) hit('hook', s, args[0], false);
            }
            args.forEach((a, i) => {
                if (i === 0 && guardFirst) {
                    const ks = tested(a);
                    noteTests(ks);
                    expr(a, { ...ctx, g: union(ctx.g, ks) });
                } else expr(a, ctx);
            });
            return;
        }
        case 'LogicalExpression': {
            const lt = tested(e.left);
            noteTests(lt);
            const gl = union(ctx.g, lt);
            expr(e.left, { ...ctx, g: gl }, extra);
            expr(e.right, e.operator === 'and' ? { ...ctx, g: gl } : ctx, e.operator === 'or' ? extra : null);
            return;
        }
        case 'UnaryExpression':
            if (e.operator === 'not') {
                const t = tested(e.argument); noteTests(t);
                return expr(e.argument, { ...ctx, g: union(ctx.g, t) });
            }
            return expr(e.argument, ctx);
        case 'BinaryExpression': {
            if (e.operator === '==' || e.operator === '~=') {
                for (const [a, b] of [[e.left, e.right], [e.right, e.left]]) {
                    if (a.type === 'Identifier' && a.name === 'event' && b.type === 'StringLiteral') checkEventLiteral(b);
                }
                const t = tested(e); noteTests(t);
                expr(e.left, { ...ctx, g: union(ctx.g, t) });
                expr(e.right, { ...ctx, g: union(ctx.g, t) });
                return;
            }
            expr(e.left, ctx); expr(e.right, ctx);
            return;
        }
        case 'FunctionExpression':
        case 'FunctionDeclaration':   // luaparse's type for `function() ... end` as a value
            return fnBody(e, e.body, ctx);
        case 'TableConstructorExpression':
            for (const f of e.fields) {
                if (f.type === 'TableKey') expr(f.key, ctx);
                expr(f.value, ctx);
            }
            return;
        default:
            return;   // literals, varargs
        }
    }

    function fnBody(node, body, ctx) {
        fnStack.push(node);
        block(body, ctx);
        fnStack.pop();
    }

    function block(stmts, ctx) {
        let cur = ctx;
        for (const s of stmts) {
            stmt(s, cur);
            if (s.type === 'IfStatement' && s.clauses.length === 1 && exits(s.clauses[0].body)) {
                const ks = negTested(s.clauses[0].condition);
                if (ks.size) { noteTests(ks); cur = { ...cur, g: union(cur.g, ks) }; }
            }
        }
    }

    function cond(c, body, ctx) {
        const ks = tested(c);
        noteTests(ks);
        const inner = { ...ctx, g: union(ctx.g, ks) };
        expr(c, inner);
        block(body, inner);
    }

    function stmt(s, ctx) {
        switch (s.type) {
        case 'LocalStatement':
            s.init.forEach((e, i) => {
                const local = s.variables.length === 1 && s.init.length === 1 ? s.variables[0].name : null;
                expr(e, ctx, local ? { local } : null);
            });
            return;
        case 'AssignmentStatement':
            s.init.forEach((e) => expr(e, ctx));
            for (const v of s.variables) {
                if (v.type === 'Identifier') continue;    // a write, not a read
                // `X.y = ...` reads X; the written member itself is not a read
                let b = v.base;
                if (v.type === 'IndexExpression') expr(v.index, ctx);
                if (b.type === 'Identifier' && b.name === '_G') continue;
                expr(b, ctx);
            }
            return;
        case 'CallStatement':
            return expr(s.expression, ctx);
        case 'FunctionDeclaration': {
            const id = s.identifier;
            if (id && id.type !== 'Identifier') {
                let b = id.base;
                while (b.type === 'MemberExpression') b = b.base;
                if (b.type === 'Identifier' && !b.isLocal && !isKnown(b.name)) globalRead(b.name, [], b, ctx.g);
            }
            return fnBody(s, s.body, ctx);
        }
        case 'IfStatement':
            for (const c of s.clauses) {
                if (c.type === 'ElseClause') block(c.body, ctx);
                else cond(c.condition, c.body, ctx);
            }
            return;
        case 'WhileStatement':
            return cond(s.condition, s.body, ctx);
        case 'RepeatStatement': {
            block(s.body, ctx);
            const ks = tested(s.condition); noteTests(ks);
            return expr(s.condition, { ...ctx, g: union(ctx.g, ks) });
        }
        case 'DoStatement':
            return block(s.body, ctx);
        case 'ForNumericStatement':
            expr(s.start, ctx); expr(s.end, ctx); expr(s.step, ctx);
            return block(s.body, ctx);
        case 'ForGenericStatement': {
            s.iterators.forEach((e) => expr(e, ctx));
            let inner = ctx;
            const it = s.iterators[0];
            if (it && it.type === 'CallExpression' && it.base.type === 'Identifier'
                && (it.base.name === 'ipairs' || it.base.name === 'pairs') && it.arguments[0]) {
                const a = it.arguments[0];
                let ss = null;
                if (a.type === 'TableConstructorExpression') {
                    ss = a.fields.filter((f) => f.type === 'TableValue').map((f) => f.value).filter((x) => strVal(x) !== null);
                } else {
                    const k = exprKey(a);
                    if (k && lists.has(k)) ss = lists.get(k);
                }
                const v = s.variables[1];
                if (ss && ss.length && v) {
                    const loops = new Map(ctx.loops); loops.set(v.name, ss);
                    inner = { ...ctx, loops };
                }
            }
            return block(s.body, inner);
        }
        case 'ReturnStatement':
            return s.arguments.forEach((e) => expr(e, ctx));
        default:
            return;
        }
    }

    block(ast.body, { g: new Set(), loops: new Map() });
    for (const p of pending) {
        const t = fnTests.get(p.fn);
        if (t && t.has(p.local)) p.h.guarded = true;
    }
    return { hits };
}

// All occurrences, folded to one finding per file + kind + name. A finding is
// guarded only if EVERY occurrence in that file is.
function lint(opts) {
    opts = opts || {};
    const api = loadApi();
    if (!api) return { error: 'no snapshot (run: node tools/apilint.js --update)' };
    const scan = opts.files || SCAN_DIRS.flatMap((d) => walkLua(path.join(ROOT, d), []));
    const defineOnly = DEFINE_ONLY_DIRS.flatMap((d) => walkLua(path.join(ROOT, d), []));
    const own = ownGlobals([...walkLua(path.join(ROOT, 'Core'), []), ...walkLua(path.join(ROOT, 'UI'), []),
        ...walkLua(path.join(ROOT, 'Modules'), []), ...defineOnly, ...(opts.files || [])]);
    const byKey = new Map();
    const errors = [];
    for (const f of scan) {
        const rel = path.relative(ROOT, f).split(path.sep).join('/');
        const r = lintFile(f, rel, api, own);
        if (r.parseError) { errors.push(rel + ': ' + r.parseError); continue; }
        for (const h of r.hits) {
            const key = h.file + '|' + h.kind + '|' + h.name;
            let e = byKey.get(key);
            if (!e) { e = { file: h.file, kind: h.kind, name: h.name, lines: [], open: [], guarded: true }; byKey.set(key, e); }
            if (!e.lines.includes(h.line)) e.lines.push(h.line);
            if (!h.guarded) { e.guarded = false; if (!e.open.includes(h.line)) e.open.push(h.line); }
        }
    }
    // a finding shows the lines that are NOT guarded; a guarded one shows all
    for (const e of byKey.values()) if (!e.guarded) e.lines = e.open;
    const all = [...byKey.values()].sort((a, b) => a.file.localeCompare(b.file) || a.lines[0] - b.lines[0]);
    const findings = all.filter((x) => !x.guarded);
    const guarded = all.filter((x) => x.guarded);
    let baseline = [];
    if (!opts.ignoreBaseline && fs.existsSync(BASELINE)) baseline = JSON.parse(fs.readFileSync(BASELINE, 'utf8')).accepted || [];
    const accepted = new Set(baseline.map((b) => b.file + '|' + b.kind + '|' + b.name));
    const fresh = findings.filter((x) => !accepted.has(x.file + '|' + x.kind + '|' + x.name));
    return { sha: api.snap.sha, files: scan.length, findings, fresh, guarded, errors, baselined: findings.length - fresh.length };
}

const KIND_TEXT = {
    global: 'global not on this client',
    constant: 'ALL_CAPS global in no list',
    namespace: 'unknown C_ namespace',
    member: 'not in this namespace',
    enum: 'unknown Enum',
    event: 'unknown event',
    hook: 'hooked global not on this client',
    deprecated: 'only a deprecation fallback, gone with loadDeprecationFallbacks 0',
    removed: 'the client UI sets it to nil before addons load',
};
const fmt = (x) => x.file + ':' + x.lines.slice(0, 4).join(',') + (x.lines.length > 4 ? ',..' : '')
    + '  ' + x.name + '  (' + KIND_TEXT[x.kind] + ')';

// Prints the report body (no section header) and returns true on failure.
function report(r, opts) {
    opts = opts || {};
    const log = opts.log || console.log;
    if (r.error) { log('  ' + r.error + ' - skipped'); return false; }
    for (const e of r.errors) log('  PARSE ' + e);
    const shown = opts.all ? r.findings : r.fresh;
    for (const x of shown) log('  API-MISSING ' + fmt(x));
    if (opts.guarded) for (const x of r.guarded) log('  guarded    ' + fmt(x));
    const tail = r.files + ' files, ' + r.guarded.length + ' guarded read(s) tolerated'
        + (r.baselined ? ', ' + r.baselined + ' accepted in the baseline' : '');
    if (shown.length === 0) log('clean (' + tail + ')');
    else log('  ' + shown.length + ' finding(s); ' + tail);
    return r.fresh.length > 0;
}

function writeBaseline(r) {
    const accepted = r.findings.map((x) => ({ file: x.file, kind: x.kind, name: x.name }));
    fs.writeFileSync(BASELINE, JSON.stringify({ snapshot: r.sha, accepted }, null, 2) + '\n');
    console.log('wrote ' + path.relative(ROOT, BASELINE) + ' (' + accepted.length + ' accepted)');
}

module.exports = { lint, report, loadApi };

if (require.main === module) {
    const argv = process.argv.slice(2);
    if (argv.includes('--update')) {
        update(argv).catch((e) => { console.error('update failed: ' + e.message); process.exit(1); });
    } else {
        const files = argv.filter((a) => !a.startsWith('--')).map((a) => path.resolve(a));
        const r = lint({ files: files.length ? files : null, ignoreBaseline: argv.includes('--all') });
        if (argv.includes('--write-baseline')) { writeBaseline(r); process.exit(0); }
        console.log('== API existence (forever ' + (r.sha || '?').slice(0, 7) + ') ==');
        const fail = report(r, { all: argv.includes('--all'), guarded: argv.includes('--guarded') });
        console.log('\n' + (fail ? 'RESULT: FAIL' : 'RESULT: OK'));
        process.exit(fail ? 1 : 0);
    }
}
