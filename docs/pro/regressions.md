# Regressions

Every bug fixed. Before touching an area, read its entries.
Second entry with the same symptom → add a guard (checker or single code path), link the invariant.

| ID | Date | Area | Symptom | Root cause | Guard |
|---|---|---|---|---|---|
| R-01 | 2026-10-02 | UI/tooltip | "numeric conversion on a secret number" ×144 hovering quest rewards | Header widths anchored into a secure-filled tooltip are secret | `num`/`secret_or` · I-26 |
| R-02 | 2026-10-04 | UI/ui (Spells tab) | `bad argument #2 to 'format'` | Data spell the client does not have, name nil | skip on nil name · I-22 |
| R-03 | 2026-10-04 | Data | Fire Nova trainable at 12 but missing from the page | Era data had it as a rune (train 0) | now upstream data · F007 |
| R-04 | 2026-10-09 | Calc (merge) | Would crash every update | Merge left `prev` reads from our old code in upstream's `dynamic_loadout` | diff merged vs theirs after every merge (CLAUDE.md) |
| R-05 | 2026-10-09 | UI/overlay | `update_cc` used `eval_flags` undefined (upstream bug) | Missing local | kept our define |
| R-06 | 2026-10-09 | Libs | Color pickers of other addons would break | LibUIDropDownMenu rev 135 treats 16001 as Classic Era | I-27 |
| R-07 | 2026-10-09 | UI/ui (merge) | Tab code called upstream's `select_tab` on our tabs | Upstream changed tab handling in non-conflicting hunks | I-11 |
| R-08 | 2026-10-09 | Locales | 32 obsolete keys shown; zhCN broke when removing them | Upstream leftovers; zhCN writes values on the next line | check: obsolete keys · I-31 |
| R-09 | 2026-10-10 | tools | Every file one big conflict in `git merge-file` | Working copy CRLF vs upstream LF | `.gitattributes` eol=lf |
| R-10 | 2026-10-10 | UI/spellbook | Spell section list missed "known" → length of nil | New section key not in every builder | review |
| R-11 | 2026-10-11 | Calc/equipment | Fire wand counted as physical in itIT/ptBR; frFR/koKR never parsed | Decorated `STRING_SCHOOL_*`, positional `%1$s`, `ipairs` stopping at nil | `DAMAGE_SCHOOLn`, order map; Lua VM test |
| R-12 | 2026-10-11 | Calc/equipment | Comparison could undo weapon damage never added | Tooltip unreadable at scan time | `weapon_needs_rescan` |
| R-13 | 2026-09-28 / 10-09 | tools (shell) | Lua/Python with `\` corrupted | Bash heredocs eat backslashes here | write with Write/Edit (CLAUDE.md) |
| R-14 | 2026-10-14 | Calc/equipment | Rescan request of one slot could be cleared by a later slot (slots run in `pairs` order) | `found_anything` set per slot | `scan_again` flag returned at the end; also covers item stats not loaded after login |
| R-15 | 2026-10-14 | UI/tooltip (merge) | Unreadable weapon compared as doing 0 damage under the red line | Upstream 0.13 no longer returns after the hint | return after the hint (kept 0.58 behaviour) |
