# Features

Status: idea · planned · building · review · test-in-game · done · dropped

| ID | Feature | Status | Version | Main files |
|---|---|---|---|---|
| F001 | Forever port: client API via `sc.api`, secret values, C_Traits talents | done | 0.44 | Core/api.lua |
| F002 | Release pipeline: tags → GitHub workflow → CurseForge | done | 0.44 | .github/, .pkgmeta |
| F003 | Own saved variable names | done | 0.45 | SpellCodaForever.toc, Core/config.lua |
| F004 | Blizzard-style window, red tabs, scale grip | done | 0.45 / 0.53 | UI/ui.lua |
| F005 | Spellbook tab + page of learnable spells | done | 0.47 | UI/spellbook.lua |
| F006 | Spells the client lacks are skipped | done | 0.48 | UI/ui.lua, UI/spellbook.lua |
| F007 | Forever trainer spells in the lists (Fire Nova, totems …) | done (now from upstream data) | 0.49–0.52 | Data/ |
| F008 | Own addon icon | done | 0.51 | Media/icon.tga |
| F009 | Translations de/fr/es/ru complete | done | 0.51 / 0.54 | Locales/ |
| F010 | Upstream SpellCoda 0.12 data and calculation merged | done | 0.53 / 0.55 | Calc/, Data/ |
| F011 | Flat creature-type bonuses from items | done | 0.53 | Calc/equipment.lua, Calc/calc.lua |
| F012 | Warning when the original SpellCoda is enabled too | done | 0.53 | Core/core.lua |
| F013 | Checks: `tools/check.py`, apilint, export check | done | 0.53 | tools/ |
| F014 | Folder structure + `tools/upstream_merge.py` + `tools/layout.json` | done | 0.56 | tools/ |
| F015 | Spellbook page: trainer prices with reputation discount | done | 0.56 | UI/spellbook.lua |
| F016 | Spellbook page: "Missing requirement" section | done | 0.56 | UI/spellbook.lua |
| F017 | Spellbook page: search, right-click ignore, settings menu | done | 0.56 | UI/spellbook.lua |
| F018 | Items missing from the data: stats from the link | done | 0.56 | Calc/equipment.lua |
| F019 | Weapon skills view, weapon masters with waypoints | done | 0.57 | UI/weapon_skills.lua, UI/spellbook.lua |
| F020 | Weapons missing from the data: damage/speed/school from the tooltip | done | 0.58 | Calc/equipment.lua |
| F021 | Class trainer locations (where the class trainers stand) | idea | — | — |
| F022 | Spellbook page: tile view grouped by level | idea | — | — |
| F023 | Minimap/data broker count of learnable spells | idea | — | — |
| F024 | Spellbook page: page buttons instead of mouse wheel only | idea | — | — |
| F025 | Spellbook page: dark theme when a UI skin darkens the book | idea | — | — |
| F026 | Spellbook page: "show known spells" toggle (weapons have it) | idea | — | — |
| F027 | ruRU: weapons with a damage school (wands) parse from the tooltip | idea | — | Calc/equipment.lua |
| F028 | Our strings in itIT, koKR, ptBR, ptPT, zhCN, zhTW | idea | — | Locales/ |
| F029 | CurseForge description updated to the current features | review (user pastes it on CurseForge) | 0.58 | branding/curseforge.md |
| F030 | Item stats of every item read from the client (`GetItemStats`) instead of formulas; replaces our link fallback, data ~745→436 KB (upstream 0.13.2907) | test-in-game | 0.59 | Calc/equipment.lua, Data/ |
| F031 | Damage of known weapons and ammo: exact DPS from the client instead of ilvl tables, tooltip as fallback (upstream 0.13.2907) | test-in-game | 0.59 | Calc/equipment.lua |
| F032 | Item tooltip: hint only when weapon/ammo damage is unreadable (upstream 0.13.2907) | test-in-game | 0.59 | UI/tooltip.lua, Locales/ |
| F033 | Item armor from the item (`RESISTANCE0_NAME` item stat in upstream 0.13 data; armor formula gone) | test-in-game | 0.59 | Calc/equipment.lua |
| F034 | `/sc perf [seconds]`: CPU per frame, share of all addons, slow frames, memory and garbage rate from the client profiler | test-in-game | 0.59 | UI/perf.lua |
| F035 | Less CPU: no full recompute every tick while the spellbook is open (page display / OnShow force one instead), item tooltip updates at the overlay rate, spellbook page rebuilds coalesced per frame with name-only lookups | test-in-game | 0.59 | Calc/loadouts.lua, UI/tooltip.lua, UI/overlay.lua, UI/spellbook.lua |

## Open questions, only answerable in game

- F020: does a missing-data weapon's tooltip damage already include a weapon enchant ("+3 Weapon Damage")? Then `apply_damage_enchant` counts it twice.
- F015: Revered / Exalted give more than 10%? (only Honored = 10% confirmed)
- F019: Bixi Wobblebonk's discount faction: Ironforge (47, used) or Gnomeregan (54)?
- F010: Fire Nova rank 1 — upstream data 48–56 coef 0.1 vs Forever DB2 408423 46–54 coef 0.214; compare with the in-game tooltip.
- F030: item 272061 (equip mp5 10): comparison shows +10 mp5, not +20 (equip spell and item stat counted once)?
- F030: enchanted item with "apply enchant" on: enchant stats counted once?
- F031: ammo tooltip "Adds X damage per second" equals SpellCoda's ammo value; no red ammo line on normal arrows/bullets?
- F035: `/sc perf 30` with the spellbook open, before (0.58/main) and after: per-frame time lower? Spellbook numbers right after closing, changing gear, reopening on the same page?
