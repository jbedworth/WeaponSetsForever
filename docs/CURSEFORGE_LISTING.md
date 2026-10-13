# CurseForge listing

Copy-ready text for the CurseForge project form. Keep it aligned with README.md
and the tested client; do not advertise clients or versions that have not been
tested.

## Project fields

| Field | Value |
| --- | --- |
| Name | Weapon Sets Forever |
| Class | Addons |
| Main category | Choose the closest to weapon or equipment swapping, such as Bags & Inventory; confirm against the form's current list. |
| Additional categories | None, or only directly related ones; unrelated categories can send the project back for changes. |
| License | MIT License |
| Logo | `artwork/weapon-sets-forever-logo-512.png` |
| Source | https://github.com/jbedworth/WeaponSetsForever |
| Issues | https://github.com/jbedworth/WeaponSetsForever/issues |

## Summary

Save and swap named weapon sets (main hand, off hand, ranged) for World of Warcraft: Forever, using native equipment sets.

## Description

```markdown
**Weapon Sets Forever** saves and swaps named weapon loadouts in World of Warcraft: Forever. It stores only your main-hand, off-hand, and ranged slots, so armor, trinkets, and the rest of your gear never change.

Sets are native WoW equipment sets: they persist per character without AddOn storage, and they work with the game's own `/equipset` command and macros.

### Features
- Save and equip from two small icons in the Character panel, beneath the slot columns.
- `/wsf save Name` or `/wsf save "Set Name"` to save your current weapons.
- Native `/equipset` for command and macro swaps.
- Keeps intentionally empty weapon slots, including shields and held off-hand items.
- `/wsf export` prints your equipped item IDs by slot, or a saved set, as JSON.
- No SavedVariables and no runtime dependencies.

### Combat
WSF's own Equip button works **out of combat only**. In combat, use native `/equipset` macros, for example:

    /equipset [noequipped:shield] Shield-Set; DPS-Set

### Compatibility
Beta: tested on the Forever beta client 1.60.1, build 70338. WSF keeps working on later beta builds; if a client update removes an API it needs, it disables itself with one chat message.

Sets saved by pre-release builds of WSF should be re-saved before combat use.

### Notes
- Saving an existing name replaces that set with a weapon-only snapshot.
- Close Blizzard's Equipment Manager pane before saving.

Source, issues, and license (MIT): https://github.com/jbedworth/WeaponSetsForever
```
