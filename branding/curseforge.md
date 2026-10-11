# CurseForge – SpellCoda Forever

Copy each block into the matching CurseForge field (editor set to **Markdown**).

## Summary

Spell calculator for World of Warcraft: Forever – damage, healing, DPS/HPS, efficiency and stat weights in your tooltips, on your action bars and in your spellbook.

## Description

**SpellCoda Forever** is the spell calculator SpellCoda, built for **World of Warcraft: Forever**. It shows what your spells really do with your current gear, talents and buffs – in tooltips, as overlays on your action buttons and spellbook icons, and in a full calculator window. On top of that it adds a SpellCoda page to your spellbook that tells you what to learn next, what it costs and where to train it.

### Spell calculator

- Damage, healing, DPS/HPS, efficiency per mana, expected crit/hit and stat weights
- Metrics in spell tooltips and as overlays on action bar and spellbook icons (all configurable)
- Applies your buffs, debuffs, talents, equipment and hidden auras
- Item evaluation in tooltips and an item upgrade planner with before/after comparison
- Calculator window: try theoretical items, stats, buffs and talents
- Bonuses against one creature type ("+X spell damage against Undead") are counted when you target that creature type

### Spellbook page

Open your spellbook and click the **SpellCoda** tab next to the category tabs.

- Every spell you can still learn, sorted into **Now available**, **Missing requirement** (previous rank not learned yet), **Coming soon** and **Not yet available**
- Rank, level and training cost per spell, with the total for everything you can learn right now
- Trainer prices include the **10% reputation discount** once you are Honored with a trainer town of your class
- Search box, right click to ignore a spell, settings menu to show or reset ignored spells
- **Weapon skills** (sword button): every weapon skill your class can learn, its price and the weapon masters of your faction with town and coordinates – left click sets a map waypoint to the cheapest one

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

- `/sc` – open the window (also `/scf`, `/spellcoda`, `/spellcodaforever`)
- `/sc calc`, `/sc tooltip`, `/sc overlay`, `/sc loadout`, `/sc profile`, `/sc settings` – open that tab
- `/sc verify` – compare the addon's spell data with the in-game spell descriptions
- `/sc reset` – reset all settings and reload

### Links

- Source and issues: [github.com/mrvulo/SpellCodaForever](https://github.com/mrvulo/SpellCodaForever)

### Credits

Based on [SpellCoda](https://github.com/jezzi23/spellcoda) by jezzi23, released under the MIT License, including its spell and item data. All credit for the original calculator goes to its author; this project adapts it for World of Warcraft: Forever and adds the spellbook page.
