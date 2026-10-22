# Decisions

Append only. Newest at the bottom. `assumed` = Claude chose a default, the user can overrule.
Format: date · decision · source · feature

- 2026-09-28 · Rename to SpellCodaForever, Forever only, keep improving · user: "SpellCodaForever nennen und für WoW Forever kompatibel machen" · F001
- 2026-09-28 · Remove the original's Discord/GitHub/CurseForge references from the addon · user: "ja nimm den discord hinweis auch raus" · F001
- 2026-09-28 · Spell data from the Forever client, verified by a `/sc verify` command first · user: "ja leg los, fang mit dem prüfbefehl an" · F001 (pipeline replaced 2026-10-09)
- 2026-09-28 · Also patch talent/buff values, item values and creature-type bonuses · user · F001, F011
- 2026-09-28 · Version numbering continues at 0.44 · user · —
- 2026-09-28 · CurseForge project 1716723, public GitHub repo, automatic packager on tags · user: "ja mach öffentlich" · F002
- 2026-09-28 · Own saved variable names · user · F003
- 2026-09-28 · Blizzard-style window · user · F004
- 2026-10-02 · Junction from the Forever AddOns folder to the repo · user · —
- 2026-10-03 · SpellCoda tab where the other addon's "?" tab was, page like its trainer list; total above the rule, title "SpellCoda Forever" · user · F005
- 2026-10-04 · Add Forever trainer spells as list entries first (A), calculation later (B) · user: "ja mach A" · F007
- 2026-10-05 · Own icon everywhere (TOC, minimap, tab, options) · user · F008
- 2026-10-06 · Translate into the four biggest WoW languages: de, fr, es, ru · user · F009
- 2026-10-09 · Take upstream SpellCoda 0.12 data and calculation, merged, "not 1:1" · user: "übernimm seine daten", "aber nicht 1:1" · F010
- 2026-10-09 · Own data pipeline (`tools/forever_data.py`, era source) removed; spell data comes from upstream's generated Camelot data · follows from the line above · F010
- 2026-10-09 · Restructure and keep a memory so changes stop breaking things · user · F013, F014
- 2026-10-09 · Rebuild the creature-type bonus on upstream's item code · user · F011
- 2026-10-09 · LibUIDropDownMenu stays at rev 133 (upstream's 135 harmful on Forever) · assumed after review · I-27
- 2026-10-09 · Warn when the original SpellCoda is enabled at the same time · assumed after review · F012
- 2026-10-09 · Complete fr/es/ru translations · user · F009
- 2026-10-10 · Full folder restructure with a merge script and layout map · user: "Komplett neu ordnen" · F014
- 2026-10-10 · Build spellbook page items 1–3: reputation discount, missing requirement, search + ignore · user: "bau 1 bis 3" · F015–F017
- 2026-10-10 · Weapon skills and weapon master locations · user · F019
- 2026-10-11 · Weapons missing from the data read from the item tooltip · user: "ja bau das" · F020
- 2026-10-11 · Project memory in `docs/pro/` · user: "ja leg docs/pro an" · —
- 2026-10-11 · CurseForge description rewritten for 0.58, kept in `branding/curseforge.md` · user: "mach die CurseForge-Beschreibung aktuell" · F029
- 2026-10-14 · Take upstream 0.13.2907 (item stats and weapon DPS from the client) as 0.59; keep our locale-aware weapon tooltip parser and creature bonuses; no source named in changelog/commits · user: "ja" · F030–F033
- 2026-10-15 · Performance pass: measure with `/sc perf`; only small upstream edits (one-line gates), larger ones (aura scan reuse, ACTIONBAR_SLOT_CHANGED) left out for merge cost · user: "ja mach die 3" · F034, F035
- 2026-10-16 · Release 0.59 on the user's word, F030–F035 stay test-in-game until reported · user: "release" · F030–F035
- 2026-10-22 · Take upstream 0.15.2935 as 0.60; keep our spellbook page, upstream's spellbook catalogue tab stays in the code but is never started (init_spellbook_tab not called) to keep future merges small; upstream's combat aura handling replaces our `aura_snapshot`; our secret guards in `dynamic_loadout` kept · user: "ja mach als 0.60" · F036–F042
- 2026-10-22 · Release 0.60 on the user's word, F036–F042 stay test-in-game until reported · user: "release" · F036–F042
