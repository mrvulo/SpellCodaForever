# SpellCoda Forever 0.59

- Item comparisons now read every item's stats, armor included, straight from the game instead of estimating them from item level and quality, so random enchantments ("of the Owl", "of the Bear") come out right.
- Mana per 5 and spell penetration from your equipped items are now counted.
- Weapon and ammo damage now comes from the game's own damage per second instead of a formula. Weapons the game data lacks are still read from their tooltip.
- The red "Item missing from SpellCoda dataset" line is gone. A short note only appears if a weapon's or ammo's damage really cannot be read; that item is then not compared.
- Smaller download: the spell and item data shrank by about 300 KB.
- Less CPU while the spellbook is open and while hovering items; the SpellCoda spellbook page rebuilds once instead of once per event or keystroke.
- New `/sc perf [seconds]`: shows how much CPU time and memory SpellCoda uses.
