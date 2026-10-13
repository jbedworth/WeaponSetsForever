# Weapon Sets Forever

Save and restore named weapon configurations in World of Warcraft: Forever.
Weapon Sets Forever uses WoW's native per-character equipment sets. It is small,
has no runtime dependencies, and does not use SavedVariables.

## Project status

**Implemented beta AddOn, version `0.1.0-beta`.** This repository contains the
runtime, Character-panel controls, automated tests, MIT license, and project logo.
It is no longer a documentation-only project.

- **Target:** Forever beta `1.60.1`, build `70338`, Interface `16001`, Lua `5.1`.
  The runtime requires this exact build and the required APIs and slot identities.
- **Client results:** The owner reported successful UI and command save/equip
  tests. Native `/equipset` works in combat. Direct WSF UI combat swaps failed;
  WSF now blocks that path before the native API call.
- **Local automated results (2026-10-13, parent-reported):** **270/270 Lua mock
  tests** and runtime/test syntax checks passed on LF-normalized files;
  **62/62 Python tests** (22 builder, 30 CurseForge, 10 provenance) and Python
  compilation passed under portable Python 3.13.7. actionlint 1.7.12 passed
  silently after the latest source-commit and tag-check workflow edits.
  The original 2026-10-12 Lua result remains historical evidence in
  [TESTING.md](TESTING.md). No GitHub-hosted CI run or live-service upload has
  been tested.
- **Release preparation:** The logo, MIT license, deterministic ZIP builder, and
  GitHub Actions workflow are present; a valid local package has been generated.
  Publishing is off by default. Screenshots, clean client installation, protected
  release-environment setup, and distribution-service setup remain pending.

These results are not a claim of full client compatibility. The latest styled
panels and restored combat guard still need client checks. Remaining equipment,
ammo, failure, taint, and character-isolation cases are listed in
[TESTING.md](TESTING.md). Launch, Retail, and other Classic clients are not
currently supported.

## Features

- Save main-hand, off-hand, and ranged configurations, including shields and held
  off-hand items. Keep intentionally empty weapon slots in the snapshot.
- Ignore native non-weapon equipment slots rather than manage complete outfits.
- Use **WSF Save** and **WSF Equip** in the Character equipment panel.
- Use `/wsf save` for saving and native `/equipset` for command or macro swaps.
- Keep sets per character through native WoW persistence.
- Provide dark-brown save/equip panels with gold borders and warm text.

Automatic switching, talent-spec-specific sets, and general outfit management
are outside the current scope.

## Quick start

1. Equip the weapons you want to save.
2. Open the Character equipment panel and close the native Equipment Manager pane.
3. Click **WSF Save**, enter a name, and click **Save** or press Enter.
4. Repeat with another weapon configuration.
5. Outside combat, click **WSF Equip** and select a saved set.

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

Names can contain at most 16 letters, including spaces. WSF counts UTF-8 start
bytes rather than raw Lua string bytes. Control characters and `|` are rejected.
Native Unicode behavior still needs client verification.

Native `/equipset` has its own parser. Do not apply the save quoting rules to it.
There is no `/wsf set` command.

### Combat macro

For shield users, create both `Shield-Set` and `DPS-Set`, then use:

```text
/equipset [noequipped:shield] Shield-Set; DPS-Set
```

The macro selects `Shield-Set` when no shield is equipped. Otherwise, it selects
`DPS-Set`. The owner confirmed this macro works in combat on the target beta.

**WSF UI equipping is out of combat only.** Native commands and WSF's ordinary
UI callbacks have different execution paths. We have confirmed different client
results, not the internal permission cause. WSF adds no combat workaround or
deferred equip queue.

## Safety

- **Saving an existing name overwrites that character's native set**, regardless
  of its creator, without another confirmation. A full outfit becomes a
  weapon-only snapshot. Saving does not equip or move items.
- Saving is blocked in combat and while the native Equipment Manager pane is
  visible. WSF does not hide that pane for you.
- WSF preserves and restores Blizzard's shared save-ignore flags. It verifies
  saved configuration and native equip completion before reporting success.
- Weapon slots are main hand `16`, off hand `17`, and ranged `18`. The beta
  requires all three identities, including hidden empty ranged. Ignore operations
  cover native equipped slots `1..19` other than those weapons.
- Ammo slot `0` is not individually operated on. Native ammo behavior and unchanged
  ammo remain separate client checks.
- Sparse native result tables are supported. An omitted weapon location counts
  as empty only with an explicit false ignore flag and no saved item ID.
- Swaps are not assumed atomic. Failure feedback can warn about partial changes;
  WSF does not attempt an unverified rollback.

**Early experimental sets:** Re-save them before combat use. Updating the AddOn
does not rewrite existing native sets. Native `/equipset` bypasses WSF's checks.
An earlier set was reported to remove armor; re-saving resolved the issue, but
its original configuration was not captured and the cause remains unknown.

## Install for beta testing

Create `Interface/AddOns/WeaponSetsForever/` in the beta client's game folder.
Copy the following files into it:

```text
WeaponSetsForever/
    WeaponSetsForever.toc
    Commands.lua
    Equipment.lua
    Core.lua
    UI.lua
    LICENSE
```

The TOC loads Commands, Equipment, Core, then UI. It declares no SavedVariables.
Its in-game AddOn category is **Equipment**, and it uses Blizzard's built-in
`INV_Sword_04` icon. This category is separate from distribution-site categories.

Do not install `.tools/`, tests, artwork, or agent guidance as runtime files.
Include `LICENSE` when distributing copies. Restart the client after installing
the AddOn or changing TOC metadata.

## Development and validation

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
| `TESTING.md` | Source evidence, dated results, and client checks. |
| `AGENTS.md` | Maintenance rules and agreed project constraints. |

From the Git Bash repository root:

```sh
.tools/luarocks-3.13.0-win32/win32/lua5.1/bin/lua5.1.exe tests/run.lua
.tools/luarocks-3.13.0-win32/win32/lua5.1/bin/luac5.1.exe -p Commands.lua Equipment.lua Core.lua UI.lua tests/run.lua
```

Development tooling is under ignored `.tools/`; it is not an AddOn dependency.
A system Lua 5.1 interpreter can also run `tests/run.lua`. Mocks do not prove
protected-action permissions, taint safety, visual layout, or actual equipment
changes. See [TESTING.md](TESTING.md) for provenance and remaining checks.

Release tooling uses Python 3 and its standard library. From the repository root:

```sh
python3 scripts/build_release.py --output dist
python3 -m unittest discover -s tests -p 'test_*.py'
```

The local build needs no CurseForge credentials or GitHub CLI authentication.
It writes the six-file installable ZIP, SHA-256 sidecar, manifest, and release
notes to ignored `dist/`. Optional `--source-commit` records a real full commit
SHA outside the ZIP; it does not prove that the working tree matches that commit.
The validated local `0.1.0-beta` package has no `source_commit`: local `main`
still has no commits. Do not invent a tag or commit for a local build. Its exact
six-file ZIP and SHA-256 are recorded in the [release plan](docs/RELEASE_PLAN.md).

On this Windows checkout, portable Python 3.13.7 from the reviewed official
`python.org` embeddable archive is under ignored `.tools/python-3.13.7/`; no
installer or PATH change is needed. Use `.tools/python-3.13.7/python.exe` instead
of `python3` in the commands above. CI uses native Python 3 on `ubuntu-24.04`
and installs Lua 5.1 through apt, not the local Windows executables.
`.gitattributes` keeps text LF and PNG/JPG/GIF/WebP/ZIP files binary. Working-tree
text has been normalized without changing staged work or global
`core.autocrlf=input`. `git ls-files --eol` confirms `i/lf w/lf` for tracked
text; staged user work remains preserved. Tooling archive sources are linked in
the [release plan](docs/RELEASE_PLAN.md).

The beta source review is pinned to Gethe/wow-ui-source commit
[`943764493e6b16d63ded3ab304150d1f05e58b57`](https://github.com/Gethe/wow-ui-source/tree/943764493e6b16d63ded3ab304150d1f05e58b57),
whose `version.txt` identifies `1.60.1.70338`.

## Artwork and publishing

The approved original logo uses a gold shield and crossed swords on dark brown.
The [artwork directory](artwork/README.md) contains an
[editable SVG](artwork/weapon-sets-forever-logo.svg), a
[1024-pixel PNG](artwork/weapon-sets-forever-logo.png), and a
[512-pixel PNG](artwork/weapon-sets-forever-logo-512.png).
These are publishing assets, not runtime textures.

Source remote: [jbedworth/WeaponSetsForever](https://github.com/jbedworth/WeaponSetsForever).
The local Git repository is initialized. The installed workflow tests and builds
on `main` pushes, pull requests, and manual runs. Matching `v*` tag pushes also
check that the tested commit is an ancestor of `main`. Publishing remains disabled
unless repository variables explicitly enable it; both publisher jobs use the
`release` environment, whose required reviewers must be configured **before**
enabling publication. Declaring that environment in YAML does not create an
approval gate.

See the [release plan and setup guide](docs/RELEASE_PLAN.md) for exact variables,
secrets, tag protections, provenance checks, validation status, and the retained
historical proposal. No commit, tag, upload, or release is authorized by this
documentation update.

Before submission:

- Capture current Character-panel, Save-panel, and Equip-list screenshots.
- Complete the final client checks and test a clean ZIP installation.
- Build an installable ZIP with `WeaponSetsForever/` at its root, containing
  only the five runtime files and `LICENSE`. GitHub source archives are not a
  substitute for this package.
- Create tagged GitHub Releases with that installable asset when authorized.
- Configure the CurseForge project description, logo, license, supported client
  versions, and changelog. Verify Forever support before uploading.
- Verify installation and updates through WoWUp's GitHub release support.
- Configure the release environment and opt-in variables as documented in the
  setup guide; keep the CurseForge token in that environment's secrets.

References: [CurseForge submission guide](https://support.curseforge.com/en/support/solutions/articles/9000197241-project-submission-guide),
[WoWUp Hub guide](https://wowup.io/guide/wowup/hub), and
[BigWigs packager](https://github.com/BigWigsMods/packager).

## License

Code and original project artwork use the [MIT License](LICENSE).
Copyright (c) 2026 John Bedworth. Include the copyright and permission notice
with distributed copies, including installable release ZIPs.
