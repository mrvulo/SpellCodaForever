# CurseForge – SpellEfficiency Forever

Copy each block into the matching CurseForge field (editor set to **Markdown**).

## Project name

SpellEfficiency Forever

## Summary

Unofficial fork of SpellCoda by jezzi23 for World of Warcraft: Forever – damage, healing, DPS/HPS, efficiency and stat weights in your tooltips, on your action bars and in your spellbook.

## Description

> **Unofficial fork** of [SpellCoda](https://www.curseforge.com/wow/addons/spellcoda) by **jezzi23**. The calculator, its spell and item data and most of the code are his work. The **official SpellCoda supports World of Warcraft: Forever** as well – if you only want the calculator, use the original. This fork adds its own spellbook page and translations.

**SpellEfficiency Forever** is based on the spell calculator SpellCoda, adapted for **World of Warcraft: Forever**. It shows what your spells really do with your current gear, talents and buffs – in tooltips, as overlays on your action buttons and spellbook icons, and in a full calculator window. On top of that it adds a page to your spellbook that tells you what to learn next, what it costs and where to train it – spells, weapon skills and profession recipes.

### Spell calculator

- Damage, healing, DPS/HPS, efficiency per mana, expected crit/hit and stat weights
- Metrics in spell tooltips and as overlays on action bar and spellbook icons (all configurable)
- Applies your buffs, debuffs, talents, equipment and hidden auras
- Item evaluation in tooltips and an item upgrade planner with before/after comparison
- Calculator window: try theoretical items, stats, buffs and talents
- Bonuses against one creature type ("+X spell damage against Undead") are counted when you target that creature type

### Spellbook page

Open your spellbook and click the **SpellEfficiency** tab next to the category tabs.

- Every spell you can still learn, sorted into **Now available**, **Missing requirement** (previous rank not learned yet), **Coming soon** and **Not yet available**
- Rank, level and training cost per spell, with the total for everything you can learn right now
- Trainer prices include the **10% reputation discount** once you are Honored with a trainer town of your class
- Search box, right click to ignore a spell, settings menu to show or reset ignored spells
- **Weapon skills** (sword button): every weapon skill your class can learn, its price and the weapon masters of your faction with town and coordinates – left click sets a map waypoint to the cheapest one
- **Professions** (note button): the recipes your professions can still learn; opening a profession trainer once records the skill, price and level it asks, for all your characters
- Group spells by section or level, weapon skills by section or town, recipes by section or profession; hover a heading for the section's total cost

### Built for Forever

- Spell and item data for the Forever client, including the new Forever trainer spells
- Items the client does not ship in its files (about half of Classic's gear) are still evaluated: stats, weapon damage, speed and damage school are read from the item itself
- Works with the client's restricted values in combat: the last known buffs are kept instead of showing errors
- Blizzard-style window
- Fully translated into **English, German, French, Spanish and Russian**

### Caveats

- This is **not** a simulation tool. Use a simulator to optimize your character for fixed rotations.
- Spells are calculated per cast. Random effects (e.g. Nature's Grace, Illumination, Clearcasting) are included as averages where possible.
- Wrong values only get fixed when they are reported – please open an issue on GitHub.
- Do not run it together with the original SpellCoda: both use the same windows and commands. The addon warns you if both are enabled.

### Commands

- `/sc` – open the window (also `/scf`, `/spellefficiency`, `/spellcoda`, `/spellcodaforever`)
- `/sc calc`, `/sc tooltip`, `/sc overlay`, `/sc loadout`, `/sc profile`, `/sc settings` – open that tab
- `/sc verify` – compare the addon's spell data with the in-game spell descriptions
- `/sc reset` – reset all settings and reload

### Links

- Source and issues: [github.com/mrvulo/SpellCodaForever](https://github.com/mrvulo/SpellCodaForever)

### Credits

Based on [SpellCoda](https://github.com/jezzi23/spellcoda) by jezzi23 (Copyright (c) 2020-2026 jezzi23), released under the MIT License, including its spell and item data. All credit for the calculator goes to its author. This is **not** the official SpellCoda; it adapts it for World of Warcraft: Forever and adds the spellbook page.
