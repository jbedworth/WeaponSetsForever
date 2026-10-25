# Changelog

Player-facing changes for each Weapon Sets Forever release, newest first. The
release builder copies the section for the TOC version into the GitHub release
notes and the CurseForge changelog, and fails if that section is missing.

## 1.2.0

### Fixes

- WSF no longer turns itself off on clients that have only the older slot lookup (Classic Era and Anniversary). It reads the weapon slots the same way there.
- WSF no longer turns itself off when the game reports equipment sets as unavailable but has every equipment-set function (seen on Classic Era, where WeaponRack's sets work). It starts with one chat note instead, and each save and equip still says if it worked.
- On those clients, the Save and Equip icons and their panels now show on the Character panel. Before, they did not show and WSF gave no message. These clients are not yet supported or tested; Forever does not change.

## 1.1.0

### Features

- `/wsf`, `/wsf help`, and any unknown word now show one line that lists every command, the same as Dyre's other AddOns. Before, they showed only how to save a set. A malformed `/wsf save` still says exactly what is wrong.
- New backup command `/weaponsets`. It works the same as `/wsf`, so you can still use WSF when another AddOn takes `/wsf`.
- If another AddOn also uses `/wsf` or `/weaponsets`, WSF says so once at login and names the other command to use.

## 1.0.0

The first full release for WoW: Forever, no longer marked beta: it was play tested on the Forever beta client 1.60.1, build 70450. CurseForge now offers it as a release, so the app updates it and installs what it needs for every player.

- The CurseForge app installs Dyre's Toolkit with WSF. Weapon Skills Forever is listed as optional.

## 0.1.2-beta

- With Dyre's Toolkit installed, Weapon Sets Forever shows under Dyre's Toolkit in the in-game AddOn list. Without it, nothing changes: the toolkit is not needed.

## 0.1.1-beta

- The Save and Equip icons now align to the outer edge of their slot columns, so stat text beside the ranged slot (for example "1.0 Dps") is no longer covered.
- The Equip tooltip now opens up and to the left, over the character, instead of over the stats pane.

## 0.1.0-beta

- First public beta for WoW: Forever.
- Save and equip named weapon-only sets (main hand, off hand, ranged) from icons in the Character panel or with `/wsf save Name`.
- Sets are native equipment sets, so native `/equipset` and macros work, including in combat.
- `/wsf export` prints equipped item IDs by slot, or a saved set, as JSON.
