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

## Layout — mirrors upstream on purpose

Shared with upstream SpellCoda (keep names and places; this is what makes upstream merges cheap):
`buffs calc calc_defs config core equipment loadouts localization overlay override public
spells_feed talents tooltip ui utils .lua`, `Camelot/` (Forever mechanics, overrides, scaling),
`generated/Camelot/` (spell/item data from upstream's generator), `generated/locale_strings.lua`,
`locale/`, `lib/`, `font/`.

Ours only:
- `api.lua` — `sc.api`, the addon-local client wrappers and secret helpers (`num`, `str`,
  `flag`, `readable`). Never add global shims.
- `spellbook.lua` — the SpellCoda tab in the spellbook tab row and the parchment page of
  learnable spells (Now available / Coming soon / Not yet available).
- `verify.lua` — `/sc verify`, compares the data with the client's spell descriptions.
- `media/icon.tga` — addon icon (TOC, minimap, spellbook tab, options). Genuine 32-bit TGA.
- `tools/`, `branding/`, `.github/`, `.pkgmeta`, `CHANGELOG-release.md` — never in the package.

## Things that must not break (each was decided by the user)

- Saved variables `SpellCodaForeverDB` / `SpellCodaForeverCharDB`. Upstream code uses
  `__sc_p_acc` / `__sc_p_char`: rename on every merge. Renaming ours loses all settings.
- `core.addon_name = "SpellCodaForever"`; slash commands `/sc /spellcoda /scf /spellcodaforever`.
- Window look: Blizzard metal frame (`ButtonFrameTemplateNoPortrait` NineSlice) over rock, gold
  title in the top band, red panel-button tabs (`create_blizz_tab`), scale grip bottom right.
  Upstream has its own tab art (`create_tab_button`, `select_tab`, `layout_tabs`): never bring
  those back into ui.lua, our tabs use LockHighlight/UnlockHighlight.
- Spellbook: our tab sits right of the category tabs (`spellbook.lua`), attached on
  `ADDON_LOADED Blizzard_PlayerSpells` (core.lua) and in `post_login_load` (ui.lua). The old
  right-edge side tab is gone. Overlays on spellbook buttons come from upstream's
  `overlay.hook_spell_book`.
- Spells the client does not have (`GetSpellInfo` nil) are skipped in the Spells tab and the
  spellbook page. Spells with rank 0 show the client's rank text.
- Combat: auras are secret in combat; `buffs.lua` keeps the last readable snapshot per unit
  (ours, on top of upstream's scan). Tooltip widths/sizes go through `num`/`secret_or`.
- Locales: German, French, Spanish (esES + esMX) and Russian carry our strings. New `L["..."]`
  keys: add to `generated/locale_strings.lua` and those locale files. No raw `"` in values.
- Item bonuses against one creature type ("+X spell damage against Undead") are read from the
  item stats in `equipment.lua` (`apply_creature_stats`); upstream's data has no fields for them.
- `lib/LibUIDropDownMenu` stays at rev 133: rev 135 takes Forever (16001) for Classic Era and
  calls a color picker API the client lacks, and through LibStub it would replace other
  addons' copies.
- TOC: title `SpellCoda |cff9b6cffForever|r`, `X-Curse-Project-ID: 1716723`, icon
  `Interface\AddOns\SpellCodaForever\media\icon`.

## Naming

Never name another addon a feature was modelled on — code, comments, strings, commits,
changelog, memory. Upstream SpellCoda/jezzi23 is credited (README, LICENSE) and may be named.
Commits carry **no Co-Authored-By line** (CurseForge shows commit text).

## Release

1. Bump `## Version` in the TOC **and** `version_minor` in core.lua.
2. Rewrite `CHANGELOG-release.md` (player-facing, English).
3. `python tools/check.py` green.
4. Commit on `main`, `git tag vX.YY`, push main and the tag. The GitHub workflow (BigWigs
   packager) builds the zip and uploads to CurseForge; check the run succeeded.
Release only after the user tested, or when they say so.

## Taking upstream changes

Upstream: `https://github.com/jezzi23/spellcoda`, data in `jezzi23/spellcoda-generated`
(`Camelot/` folder). Current merge base: **v0.12.2892** (generated b4dbf85). Procedure:
1. Clone upstream at the old base tag and the new tag (with submodule).
2. Per shared file: `git merge-file ours base theirs` (base = old tag, theirs = new tag).
3. Resolve: calculation logic from upstream; our look, our modules and our fixes stay. After
   resolving, `diff theirs merged` per file and remove every leftover of a replaced approach
   (variables that no longer exist were the main crash source last time).
4. Data: replace `generated/Camelot/*` with upstream's; merge `generated/locale_strings.lua`
   keeping our extra keys.
5. Rename saved variables, run `tools/check.py`, adversarial review, in-game test.
6. Update the merge base above.

## Client pitfalls (Forever 1.60.1)

- Secret values: never do arithmetic/comparison on unit health/power, aura fields in combat,
  tooltip region sizes after secure fills. Use `sc.api.num/str/flag/readable` or
  `sc.utils.secret_or/is_secret`.
- `GetCoinTextureString` global is gone: `C_CurrencyInfo.GetCoinTextureString` (`sc.api`).
- Spellbook lives in load-on-demand `PlayerSpellsFrame` (`Blizzard_PlayerSpells`).
- Rage costs in DB2 are tenths of a point.

## Shell pitfalls

- Bash heredocs eat backslashes here: write Lua/Python containing `\` with the Write/Edit tools.
- Files are LF in the repo; git warns about CRLF on Windows, harmless.
