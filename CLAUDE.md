# SpellCodaForever

SpellCoda (spell calculator by jezzi23, MIT) for **WoW: Forever only** — Interface 16001, the
Mainline 12.x client with secret values. Public repo `mrvulo/SpellCodaForever`, CurseForge
project 1716723. The user plays in German; answer in German, short.

## Before every commit that ships

```
python tools/check.py
```

Must print `all checks passed`. It checks: TOC lists every file and every file exists, saved
variable names, `## Version` = `core.lua` version, Lua syntax (5.2 grammar), every API/global
exists on Forever (`tools/apilint.cjs`, baseline `tools/apilint-baseline.json`), every
`sc.<module>.<name>` read is defined somewhere (`tools/check_exports.py`), duplicate locale keys,
reference-addon names. First time: `cd tools && npm install`.

A green check is not a test. After nontrivial changes run an adversarial review (subagent with a
numbered attack list), then the user tests in game (`/reload`; new texture files need a full
client restart). The AddOns folder `_classic_beta_\Interface\AddOns\SpellCodaForever` is a
junction to this repo.

## Layout

```
SpellCodaForever.toc
Core/      api (ours), utils, config, core, public, localization, override
Calc/      calc, calc_defs, buffs, talents, equipment, loadouts
Calc/Forever/  Forever mechanics, overrides, scaling (upstream's Camelot/)
UI/        ui, tooltip, overlay, spells_feed, spellbook (ours), verify (ours)
Data/      spell/item data from upstream's generator (upstream's generated/Camelot/)
Locales/   one file per language + locale_strings.lua (the localizable key list)
Libs/      LibStub, CallbackHandler, LibDataBroker, LibDBIcon, LibUIDropDownMenu
Media/     icon.tga (ours), Oswald-Bold.ttf + OFL.txt
tools/     check.py, upstream_merge.py, layout.json, apilint (never shipped)
branding/  logo sources (never shipped)
```

`tools/layout.json` maps every upstream file to its place here; `tools/upstream_merge.py`
uses it. Moving or renaming a shared file means updating `layout.json` in the same commit.
Paths that player settings store (the font in `Media/`) need a migration in `Core/config.lua`
when they move (see the font one there).

Ours only:
- `Core/api.lua` — `sc.api`, the addon-local client wrappers and secret helpers (`num`,
  `str`, `flag`, `readable`). Never add global shims.
- `UI/spellbook.lua` — the SpellCoda tab in the spellbook tab row and the parchment page of
  learnable spells (Now available / Coming soon / Not yet available).
- `UI/verify.lua` — `/sc verify`, compares the data with the client's spell descriptions.
- `Media/icon.tga` — addon icon (TOC, minimap, spellbook tab, options). Genuine 32-bit TGA.
- `tools/`, `branding/`, `.github/`, `.pkgmeta`, `CHANGELOG-release.md`, docs — never packaged.

## Project memory (`docs/pro/`)

Read before every change, update in the same commit as the code:

- [invariants.md](docs/pro/invariants.md) — everything that must not break, with why and guard
- [regressions.md](docs/pro/regressions.md) — fixed bugs per area; read the entries for the area you touch
- [features.md](docs/pro/features.md) — feature index, idea backlog, open in-game questions
- [decisions.md](docs/pro/decisions.md) — append-only log of the user's choices

"Was ist noch offen?" is answered from `features.md`, not from memory. Code done but not tested
in game is `test-in-game`, never `done`.

The hardest rules (details and the rest in invariants.md):
- Saved variables `SpellCodaForeverDB` / `SpellCodaForeverCharDB` (I-01).
- Our window look and tabs stay; upstream's tab code never returns to `UI/ui.lua` (I-10, I-11).
- Calculation and `Data/` come from upstream via the merge script, never 1:1 (I-20, I-21).
- Secret values only through `sc.api` / `sc.utils.secret_or` (I-26).
- `Libs/LibUIDropDownMenu` stays at rev 133 (I-27).
- New locale keys go into de/fr/es(+MX)/ru and `locale_strings.lua` (I-30).

## Naming

Never name another addon a feature was modelled on — code, comments, strings, commits,
changelog, memory. Upstream SpellCoda/jezzi23 is credited (README, LICENSE) and may be named.
Commits carry **no Co-Authored-By line** (CurseForge shows commit text).

## Release

1. Bump `## Version` in the TOC **and** `version_minor` in `Core/core.lua`.
2. Rewrite `CHANGELOG-release.md` (player-facing, English).
3. `python tools/check.py` green.
4. Commit on `main`, `git tag vX.YY`, push main and the tag. The GitHub workflow (BigWigs
   packager) builds the zip and uploads to CurseForge; check the run succeeded.
Release only after the user tested, or when they say so.

## Taking upstream changes

Upstream: `https://github.com/jezzi23/spellcoda`, data in `jezzi23/spellcoda-generated`
(`Camelot/` folder). Current merge base: **v0.13.2907** (generated 6309d52).

1. On a branch: `python tools/upstream_merge.py <merge base> <new tag>`. It merges every mapped
   file (`git merge-file`), replaces `Data/`, merges `Locales/locale_strings.lua` keeping our
   keys, renames the saved variables and lists unmapped upstream changes and library changes.
2. Resolve conflicts: calculation logic from upstream; our look, our modules and our fixes stay.
   Known recurring conflict: the item link hook in `UI/ui.lua` (ours hooks
   `ChatFrameUtil.InsertLink`, keep ours). After resolving, diff each file against upstream's
   version and remove every leftover of a replaced approach (variables that no longer exist
   were the main crash source in the 0.53 merge).
3. `python tools/check.py`, adversarial review for bigger merges, in-game test.
4. Update the merge base above.

## Client pitfalls (Forever 1.60.1)

- Secret values: never do arithmetic/comparison on unit health/power, aura fields in combat,
  tooltip region sizes after secure fills. Use `sc.api.num/str/flag/readable` or
  `sc.utils.secret_or/is_secret`.
- `GetCoinTextureString` global is gone: `C_CurrencyInfo.GetCoinTextureString` (`sc.api`).
- Spellbook lives in load-on-demand `PlayerSpellsFrame` (`Blizzard_PlayerSpells`).
- Rage costs in DB2 are tenths of a point.

## Shell pitfalls

- Bash heredocs eat backslashes here: write Lua/Python containing `\` with the Write/Edit tools.
- `.gitattributes` keeps the working copy LF. Without it git checks files out as CRLF and
  `git merge-file` against upstream (LF) turns every file into one big conflict.
