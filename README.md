# Weapon Sets Forever

Save and restore named weapon configurations in World of Warcraft: Forever.
Weapon Sets Forever uses WoW's native per-character equipment sets. It is small,
has no runtime dependencies, and does not use SavedVariables.

## Purpose

Swapping between weapon loadouts (for example, a shield set and a two-handed set)
should not require managing complete outfits. WSF saves only the main-hand,
off-hand, and ranged slots as native equipment sets, ignoring every other slot,
so armor, trinkets, and the rest of your gear are never part of a swap.

Native sets are used deliberately: they persist per character without AddOn
storage, and they work with the game's own `/equipset` command and macros.

## Compatibility

WSF targets Forever beta `1.60.1`, build `70338`, Interface `16001`, Lua `5.1`.
The runtime checks for this exact build, the required APIs, and the expected
weapon slot identities, and disables itself with one message otherwise. Launch,
Retail, and other Classic clients are not supported.

## Features

- Save main-hand, off-hand, and ranged configurations, including shields and held
  off-hand items. Keep intentionally empty weapon slots in the snapshot.
- Ignore native non-weapon equipment slots rather than manage complete outfits.
- Use the **Save** and **Equip** icon buttons in the Character equipment panel.
  They sit beneath the left and right slot columns, clear of the stat text that
  other AddOns draw beside the slots.
- Use `/wsf save` for saving and native `/equipset` for command or macro swaps.
- Use `/wsf export` to print equipped item IDs by slot, or a saved set, as JSON.
- Keep sets per character through native WoW persistence.
- Provide dark-brown save/equip panels with gold borders and warm text.

Automatic switching, talent-spec-specific sets, and general outfit management
are outside the project's scope.

## Quick start

1. Equip the weapons you want to save.
2. Open the Character equipment panel and close the native Equipment Manager pane.
3. Click the **Save** icon (the WSF shield logo, beneath the wrist slot), enter a name, and
   click **Save** or press Enter.
4. Repeat with another weapon configuration.
5. Outside combat, click the **Equip** icon (a sword, beneath the lower trinket
   slot) and select a saved set.

Hover over either icon for help text.

At login, WSF prints its title, version, and author, then a short ready hint.
If the client is unsupported, the second line gives the reason instead.

The custom name field accepts a literal name. Spaces need no quotes there.
The equip list shows eight sets per page. You can browse it in combat, but WSF
blocks UI equipping. Combat entry closes the save panel, not the equip list.

### Commands and names

```text
/wsf save Daggers
/wsf save "Tank Weapons"
/equipset Daggers
/equipset Tank Weapons
```

`/wsf save` requires exactly one non-empty name. Spaces separate arguments;
multi-word names require double quotes. Missing names, malformed quotes, and
extra arguments are rejected before changing a set. `/wsf save Tank Weapons`
does not silently create or overwrite `Tank`.

Names can contain at most 16 letters, including spaces, matching the native
Equipment Manager name field. WSF counts UTF-8 characters rather than raw Lua
string bytes. Control characters and `|` are rejected.

Native `/equipset` has its own parser. Do not apply the save quoting rules to it.
There is no `/wsf set` command.

### Export

Export prints your equipped item IDs by slot, or a saved set's full contents,
as one line of JSON in chat. Use it to record your gear, compare sets, or
attach details to a bug report.

```text
/wsf export
/wsf export Shield-Set
/wsf export "Tank Weapons"
```

`/wsf debug_probe` is an alias that accepts the same arguments and prints the
same JSON.

With no name, export reports each set that the client marks as equipped,
one line per set; overlapping weapon-only sets can be equipped together. If no
set is equipped, it prints only `client` and `current`, with `name` and `id`
as `null`.

`/wsf export Name` prints one chat line with a named native set as JSON:

| Field | Content |
| --- | --- |
| `client` | Version, build, and Interface. |
| `name`, `id` | The set name and native ID. |
| `info` | `GetEquipmentSetInfo` returns, named in documented order; any undocumented extra returns appear in `extraReturns`. |
| `ignored`, `locations`, `items` | The raw native tables. |
| `decodedLocations` | Each location decoded: `kind` (`equipped`, `bags`, `bank`, `empty`, `ignored`, `missing`, or `unknown`), `hex`, the `player`/`bags`/`bank` flags, `bag`, `slot`, and any `otherBits`. |
| `current` | The item IDs equipped now. |

Slots `1..19` are always listed; `null` means the native table has no entry for
that slot. Export does not validate or change anything, works in combat, and accepts any
existing set name, including sets that WSF would reject for equipping.
Use the same quoting rules as `/wsf save`. To copy the output, enable `/chatlog`
first; the client writes chat to `Logs/WoWChatLog.txt`.

### Swap diagnostics

`/wsf debug_swap` turns swap diagnostics on or off for the current session
(`/wsf debug_swap on` and `/wsf debug_swap off` also work). While on, each
swap prints `debug_swap` lines with the set, its `isEquipped` flag, and the
item IDs in slots 16 to 18: when WSF asks the client to equip (`use`), when WSF
decides the result (`finish`, with `via=equipment`, `event`, `immediate`,
`fallback`, or `rejected`), when the client reports the swap finished (`event`), and one
second later (`event+1s`). Diagnostics print only after WSF has settled the
swap, so they cannot leave a swap pending.
Native `/equipset` swaps print the `event` lines too, for comparison. The
setting resets on `/reload` and is never saved.

`/wsf debug_swap status` prints whether diagnostics are on, whether WSF is
available, how many swap-finished events the client has sent since login (with
the last result and set), and whether a swap is pending. It then prints a sample
diagnostic line, or the error text if that line cannot be built.

### Combat macro

**WSF UI equipping is out of combat only.** On the target client, the secure
native `/equipset` command can swap sets in combat, but an AddOn's ordinary UI
callbacks cannot. WSF therefore blocks UI equips in combat with a pointer to
`/equipset`, and adds no combat workaround or deferred equip queue.

For shield users, create both `Shield-Set` and `DPS-Set`, then use:

```text
/equipset [noequipped:shield] Shield-Set; DPS-Set
```

The macro selects `Shield-Set` when no shield is equipped. Otherwise, it selects
`DPS-Set`.

## Safety

- **Saving an existing name overwrites that character's native set**, regardless
  of its creator, without another confirmation. A full outfit becomes a
  weapon-only snapshot. Saving does not equip or move items.
- Saving is blocked in combat and while the native Equipment Manager pane is
  visible. WSF does not hide that pane for you.
- WSF preserves and restores Blizzard's shared save-ignore flags. It verifies
  saved configuration and native equip completion before reporting success.
- Weapon slots are main hand `16`, off hand `17`, and ranged `18`. All three
  identities are required, including a hidden empty ranged slot. Ignore
  operations cover native equipped slots `1..19` other than those weapons.
- Ammo slot `0` is not individually operated on and is outside scope.
- Native result tables omit ignored locations. An omitted weapon location counts
  as empty only with an explicit false ignore flag and no saved item ID.
- Swaps are not assumed atomic. Failure feedback can warn about partial changes;
  WSF does not attempt an unverified rollback.

**Sets from pre-release builds:** re-save them before combat use. Updating the
AddOn does not rewrite existing native sets, and native `/equipset` bypasses
WSF's checks.

## Installation

Create `Interface/AddOns/WeaponSetsForever/` in the client's game folder and
copy these files into it (or extract a release ZIP, which has this layout):

```text
WeaponSetsForever/
    WeaponSetsForever.toc
    Commands.lua
    Equipment.lua
    Core.lua
    UI.lua
    LICENSE
    Textures/
        SaveIcon.tga
```

The TOC loads Commands, Equipment, Core, then UI. It declares no SavedVariables.
Its in-game AddOn category is **Equipment**, and it uses Blizzard's built-in
`INV_Sword_04` icon. This category is separate from distribution-site categories.

Do not install `.tools/`, tests, artwork, or agent guidance as runtime files.
Include `LICENSE` when distributing copies. Restart the client after installing
the AddOn or changing TOC metadata.

## Development

| File | Responsibility |
| --- | --- |
| `Commands.lua` | Strict save-command parsing and shared name validation. |
| `Equipment.lua` | Capability checks, native snapshots, shared flags, set validation, and equip preconditions. |
| `Core.lua` | Slash registration, login availability, equip state and completion feedback. |
| `UI.lua` | Character-panel buttons and custom save/equip panels. |
| `tests/run.lua` | Isolated Lua 5.1 tests with WoW API mocks. |
| `scripts/` | Standard-library Python release builder, provenance verifier, and CurseForge uploader; no runtime dependencies. |
| `tests/test_*.py` | Release-builder, CurseForge, and provenance unit tests. |
| `.github/workflows/release.yml` | Read-only CI builds and opt-in, protected-environment publishers. |
| `TESTING.md` | Verification method, pinned source evidence, and in-client checklist. |
| `docs/RELEASE_PLAN.md` | Packaging, CI, and publication process. |
| `AGENTS.md` | Maintenance rules and agreed project constraints. |

### Design principles

- Keep the feature set narrow; prefer native APIs over AddOn-side storage.
- Validate input and preconditions before mutating sets or equipment.
- Report success only after native results or verified state confirm it.
- Treat expected failures (bad input, locked items, full bags, combat) as
  concise `WSF`-prefixed messages; let programming defects surface normally.
- Event-driven work only: no idle polling or `OnUpdate` handlers.

### Running checks

From the Git Bash repository root:

```sh
.tools/luarocks-3.13.0-win32/win32/lua5.1/bin/lua5.1.exe tests/run.lua
.tools/luarocks-3.13.0-win32/win32/lua5.1/bin/luac5.1.exe -p Commands.lua Equipment.lua Core.lua UI.lua tests/run.lua
```

Development tooling is under ignored `.tools/`; it is not an AddOn dependency.
A system Lua 5.1 interpreter can also run `tests/run.lua`. Mocks do not prove
protected-action permissions, taint safety, visual layout, or actual equipment
changes; see [TESTING.md](TESTING.md) for the in-client method.

Release tooling uses Python 3 and its standard library:

```sh
python3 scripts/build_release.py --output dist
python3 -m unittest discover -s tests -p 'test_*.py'
```

The local build needs no credentials. It writes the seven-file installable ZIP,
SHA-256 sidecar, manifest, and release notes to ignored `dist/`. Optional
`--source-commit` records a real full commit SHA outside the ZIP; it does not
prove that the working tree matches that commit.

On Windows, a portable Python 3.13.7 from the official `python.org` embeddable
archive can live under ignored `.tools/python-3.13.7/`; use its `python.exe` in
place of `python3`. CI uses native Python 3 on `ubuntu-24.04` and installs Lua 5.1
through apt. `.gitattributes` keeps text LF and image/ZIP/TGA files binary.

The Save button's `Textures/SaveIcon.tga` is generated from the 512-pixel logo:

```sh
python3 scripts/build_icon.py
```

It crops the shield-and-swords emblem, box-filters it to 64 x 64, and writes an
uncompressed 32-bit TGA. A test fails if the committed TGA differs from a fresh
build, so rerun the script whenever the logo changes.

Client source review is pinned to Gethe/wow-ui-source commit
[`943764493e6b16d63ded3ab304150d1f05e58b57`](https://github.com/Gethe/wow-ui-source/tree/943764493e6b16d63ded3ab304150d1f05e58b57),
whose `version.txt` identifies `1.60.1.70338`.

## Artwork and publishing

The original logo uses a gold shield and crossed swords on dark brown.
The [artwork directory](artwork/README.md) contains an
[editable SVG](artwork/weapon-sets-forever-logo.svg), a
[1024-pixel PNG](artwork/weapon-sets-forever-logo.png), and a
[512-pixel PNG](artwork/weapon-sets-forever-logo-512.png).
These are publishing assets. The only runtime texture derived from them is the
Save button icon in `Textures/`.

Source: [jbedworth/WeaponSetsForever](https://github.com/jbedworth/WeaponSetsForever).
CI tests and builds on `main` pushes, pull requests, and manual runs. Releases
are tagged GitHub Releases carrying the installable `-forever.zip`, also
uploaded to CurseForge. WowUp 2.24.0 or later can install from the repository
URL; the release's `release.json` asset tells it the ZIP is for Forever. Publishing is
disabled unless repository variables explicitly enable it, and both publisher
jobs run in a `release` environment that must have required reviewers.

See the [release process](docs/RELEASE_PLAN.md) for variables, secrets, tag
protections, provenance checks, and recovery rules.

References: [CurseForge submission guide](https://support.curseforge.com/en/support/solutions/articles/9000197241-project-submission-guide),
[WoWUp Hub guide](https://wowup.io/guide/wowup/hub), and
[BigWigs packager](https://github.com/BigWigsMods/packager).

## License

Code and original project artwork use the [MIT License](LICENSE).
Copyright (c) 2026 John Bedworth. Include the copyright and permission notice
with distributed copies, including installable release ZIPs.
