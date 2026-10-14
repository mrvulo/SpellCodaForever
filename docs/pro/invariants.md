# Invariants

Each rule: why it exists, when it was decided, and what guards it.
Guard: `check` = `tools/check.py` fails if broken · `code` = one shared code path · `manual` = review / in-game.
Source: `user` (quote) · `code` · commit · `R-xx` (learned from a regression).

## Identity and packaging

| ID | Rule | Why | Decided · Source | Guard |
|---|---|---|---|---|
| I-01 | Saved variables are `SpellCodaForeverDB` / `SpellCodaForeverCharDB`; upstream's `__sc_p_acc` / `__sc_p_char` are renamed on every merge | Renaming loses every player's settings; sharing upstream's names collides with the original addon | 2026-09-28 · user: "könnnen wir das noch anpassen" | check |
| I-02 | `core.addon_name = "SpellCodaForever"`; slash commands `/sc /spellcoda /scf /spellcodaforever` | ADDON_LOADED matches the folder name | 2026-09-28 · user: "SpellCodaForever nennen" | manual |
| I-03 | Forever only: one TOC, `## Interface: 16001`, data from `Data/` (upstream's Camelot); no Vanilla/TBC data shipped | Half the package size; other clients are upstream's job | 2026-09-28 · user · 2026-10-10 size question | check (TOC) |
| I-04 | TOC: title `SpellCoda |cff9b6cffForever|r`, `X-Curse-Project-ID: 1716723`, icon `Interface\AddOns\SpellCodaForever\Media\icon` | CurseForge upload and addon list | 2026-09-28 / 2026-10-05 · user | check (icon file) |
| I-05 | `## Version` in the TOC equals `version_minor` in `Core/core.lua` | Window title and data checks read the code version | 2026-09-28 · code | check |
| I-06 | Release only after the user tested in game or says "bring es raus"; tag `vX.YY` triggers the packager | Users get the zip automatically | 2026-09-28 · user | manual |
| I-07 | Commits carry no Co-Authored-By line | CurseForge shows commit text | user (VuloForeverUI rule, 2026-09-28) | manual |
| I-08 | Never name an addon a feature was modelled on (code, comments, strings, commits, changelog, memory); upstream SpellCoda/jezzi23 is credited in README/LICENSE | User rule for all their addons | 2026-10-03 · user rule | check (names) |
| I-09 | `tools/`, `branding/`, `docs/`, `CLAUDE.md`, `README.md`, `CHANGELOG-release.md` never ship (`.pkgmeta`) | Package stays the addon only | 2026-09-28 · code | manual |

## Look and UI

| ID | Rule | Why | Decided · Source | Guard |
|---|---|---|---|---|
| I-10 | Window: Blizzard metal frame (`ButtonFrameTemplateNoPortrait` NineSlice) over rock, gold title in the top band, red panel-button tabs (`create_blizz_tab`, Lock/UnlockHighlight), scale grip bottom right | User chose the Blizzard look | 2026-09-28 · user: "Ui fenster in blizzard style" | manual |
| I-11 | Upstream's tab art (`create_tab_button`, `select_tab`, `layout_tabs`) never comes back into `UI/ui.lua` | It replaced our tabs in the 0.53 merge and crashed with ours | 2026-10-09 · R-07 | manual |
| I-12 | Spellbook: our tab sits right of the category tabs, attached on `ADDON_LOADED Blizzard_PlayerSpells` (`Core/core.lua`) and in `post_login_load` (`UI/ui.lua`); the old right-edge side tab is gone; spellbook button overlays come from upstream's `overlay.hook_spell_book` | User placed it where the "?" tab was | 2026-10-03 · user | manual |
| I-13 | Spellbook page writes nothing Blizzard owns; tab, covers and pages are our frames parented to `PlayerSpellsFrame` | Taint | 2026-10-03 · code | manual |
| I-14 | Spellbook page: prices with 10% discount from Honored with a trainer town of the class (`trainer_factions`), rounded per spell; sections Now available / Missing requirement / Coming soon / Not yet available / Known / Ignored; own search box and settings menu | User asked for these (F015–F017) | 2026-10-10 · user: "bau 1 bis 3" | manual |
| I-15 | The ignore list is `config.settings.spells_ignore_list`, shared by the Spells tab and the spellbook page; both refresh each other | One list, two views | 2026-10-10 · code | code |
| I-16 | Weapon skills and weapon masters are kept by hand in `UI/weapon_skills.lua`, not in `Data/` | Trainer lists are server side; `Data/` is overwritten by the upstream merge | 2026-10-10 · code | manual |

## Data and calculation

| ID | Rule | Why | Decided · Source | Guard |
|---|---|---|---|---|
| I-20 | Calculation code and `Data/` come from upstream SpellCoda via `tools/upstream_merge.py`; our look, modules and fixes stay; never a 1:1 copy | User: "du darfst den code vom original übernehmen aber nicht 1:1" | 2026-10-09 · user | manual |
| I-21 | Every upstream file has its place in `tools/layout.json`; moving a shared file updates it in the same commit | The merge script maps paths through it | 2026-10-10 · code | manual |
| I-22 | Spells the client does not have (`GetSpellInfo` nil) are skipped in the Spells tab and the spellbook page; rank 0 shows the client's rank text | Crash in 0.47 | 2026-10-04 · R-02 | code |
| I-23 | Item stats come from the client (`GetItemStats` mapped via `sc.item_stat_effects`, upstream 0.13); weapon DPS of known weapons from the client, weapon damage/speed/school of weapons missing from `Data/` or with unreadable stats via our `tooltip_weapon_stats` (patterns from client global strings incl. positional `%1$s`; ruRU templates with `|3` grammar escapes skipped; tested under a fengari Lua VM for enUS/deDE/frFR/ruRU) — never upstream's simpler parser, which calls every school physical | The client ships only ~half of Classic's gear in its item tables, the rest comes from the server | 2026-10-10 / 2026-10-11 / 2026-10-14 · user | manual |
| I-24 | Flat bonuses against a creature type are read from item stats (`apply_creature_stats`) | Upstream's data has no fields for them | 2026-10-09 · user: "bau den kreaturen-bonus nach" | manual |
| I-25 | In combat auras are secret: `Calc/buffs.lua` keeps the last readable snapshot per unit on top of upstream's scan | Buffs vanished from the calculation in combat | 2026-10-09 · code | manual |
| I-26 | Secret values are never used in arithmetic/comparison; go through `sc.api.num/str/flag/readable` or `sc.utils.secret_or/is_secret` | Forever errors on secrets | 2026-10-02 · R-01 | check (apilint partial) |
| I-27 | `Libs/LibUIDropDownMenu` stays at rev 133 | rev 135 treats Forever (16001) as Classic Era, calls a missing color picker API and via LibStub replaces other addons' copies | 2026-10-09 · R-06 | manual |
| I-28 | Player settings that store paths (overlay font in `Media/`) get a migration in `Core/config.lua` when the file moves | Overlay text would vanish | 2026-10-10 · code | manual |

## Locales

| ID | Rule | Why | Decided · Source | Guard |
|---|---|---|---|---|
| I-30 | German, French, Spanish (esES + esMX) and Russian carry all strings; new `L["..."]` keys go into `Locales/locale_strings.lua` and those five files | User picked the four biggest WoW languages | 2026-10-06 · user | check (key list for our modules) |
| I-31 | No duplicate and no obsolete keys in locale files; no raw `"` in values | Duplicate wins silently; obsolete keys showed in the in-game tool | 2026-10-09 · R-08 | check |
