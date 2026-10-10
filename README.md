# SpellCoda Forever

Spell calculator for **World of Warcraft: Forever** — damage, healing, DPS/HPS, efficiency and
stat weights in your tooltips, on your action bars and in a full calculator window.

[CurseForge](https://wow.curseforge.com/projects/1716723) ·
[Releases](https://github.com/mrvulo/SpellCodaForever/releases)

## Features

- Spell metrics in tooltips and as overlays on action bar and spellbook icons
- Calculator window: item planner, stat changes, talents and buffs, with before/after comparison
- Item evaluation in tooltips and an item upgrade planner
- SpellCoda tab in the spellbook: every spell you can still learn, grouped into
  *Now available*, *Coming soon* and *Not yet available*, with rank, level and training cost
- Blizzard-style window, translated into German, French, Spanish and Russian

Commands: `/sc` (open), `/sc verify` (compare the addon's spell data with the game).

## Credits

Based on [SpellCoda](https://github.com/jezzi23/spellcoda) by jezzi23, released under the MIT
License, including its spell and item data. This project adapts it for World of Warcraft: Forever.

## Development

- `python tools/check.py` — all pre-release checks (needs node; run `npm install` in `tools/` once)
- `python tools/upstream_merge.py <old tag> <new tag>` — take a new upstream SpellCoda version
- Rules, layout and release/merge procedures: see `CLAUDE.md`
