# Verification and test plan

## Status

Target: Forever beta `1.60.1.70338`, Interface `16001`, Lua `5.1`.
The owner confirmed the build/runtime and the presence of native set APIs.
Core gates operations to exact version `1.60.1`, build `70338`, and Interface `16001`.
Other builds remain unsupported until reviewed and tested.
Initial client testing found a save-verification error. The owner supplied
native result tables for `Shield-Set` (ID 2), recorded below. After the fix,
on 2026-10-12 the owner reported that UI controls and macros/slash commands can
save and equip a set. This is a successful basic client smoke test, not full
compatibility verification. Unchanged non-weapon gear/ammo, empty-slot restoration,
weapon transitions, failure cases, restored combat guard/taint, persistence,
and character isolation still require separate checks. Repeated owner-reported
same-set combat comparisons confirm a beta limitation: custom WSF UI swaps fail
with generic WSF feedback referring to bag space, while the native conditional
macro works. This establishes different observed results, not the internal
permission root cause. WSF UI equip is now out of combat only. Saves remain
blocked in combat and with the Equipment Manager pane visible. No macro
workarounds, secure-macro support, queues, or frameworks are in scope.

The experimental runtime now includes `Commands.lua`, `Equipment.lua`,
`Core.lua`, `UI.lua`, and `WeaponSetsForever.toc`. Focused tests exist at
`tests/run.lua`. The latest reported validation on 2026-10-12 passed 270/270 mock
tests under Lua 5.1.5. Syntax checks passed for Commands.lua, Equipment.lua,
Core.lua, UI.lua, and tests/run.lua. Earlier runs are historical records below.
Automated results do not establish in-client behavior, panel appearance,
protected-action permissions, or taint.

### Current runtime contract

- `Commands.lua` validates exactly one save name and counts UTF-8 start bytes
  against a 16-letter limit. Custom save-panel and slash saves use the shared validator.
- `Equipment.lua` checks exact version/build/Interface, required APIs/constants,
  and all three slot identities (main 16, off 17, ranged 18). It does not discard
  a slot based on ranged visibility or `IsInventorySlotEnabled`.
- Save-ignore operations cover equipped slots `1..19` except weapons `16/17/18`.
  The code does not individually operate on ammo slot `0`. Ammo is outside scope;
  native ammo behavior and unchanged ammo remain in-client checks.
- Saves verify saved ignore flags, item IDs, and locations. Omitted ignored
  locations are accepted. An omitted weapon location is treated as empty only
  with an explicit false ignore flag and no saved item ID.
  A narrow protected save region attempts shared-flag restoration after a
  programming defect, then rethrows. Restoration errors are also rethrown.
- `Core.lua` starts unavailable and checks capabilities at `PLAYER_LOGIN`.
  Missing capabilities disable operations and produce one login report.
  A missing `C_Timer.After` also disables core operations.
- `Equipment.PrepareEquip` rejects combat before any
  `C_EquipmentSet.UseEquipmentSet` call and returns the exact error
  `WSF cannot equip from its UI in combat. Use native /equipset instead.`
  Core reports it once; UI adds no feedback. Out-of-combat weapon-only validation,
  missing-item, item-lock, casting, and completion checks remain.
- Equip completion uses the native bool/event result plus `isEquipped`.
  An accepted pending swap gets one five-second fallback state check, not idle
  polling. Core owns all equip failure/completion feedback.
- UI guards its deferred login call with timer table/function checks. If the
  timer is absent, it updates directly without a timer exception; core remains
  responsible for disabling operations. Both login-handler orders need tests.
- The TOC uses Interface 16001, loads Commands, Equipment, Core, then UI, and
  declares no SavedVariables. Equipping by command remains native `/equipset`;
  there is no `/wsf set` implementation.

## Pinned source evidence

All links use Gethe/wow-ui-source commit
`943764493e6b16d63ded3ab304150d1f05e58b57`.
[`version.txt`](https://github.com/Gethe/wow-ui-source/blob/943764493e6b16d63ded3ab304150d1f05e58b57/version.txt)
reports `1.60.1.70338`.

### Frames, templates, and placement

- [`CharacterFrame.xml`](https://github.com/Gethe/wow-ui-source/blob/943764493e6b16d63ded3ab304150d1f05e58b57/Interface/AddOns/Blizzard_UIPanels_Game/Camelot/CharacterFrame.xml)
  defines `CharacterFrame.LeftPaneHost` with width 398 and a separate right pane.
- [`CharacterFrameConstants.lua`](https://github.com/Gethe/wow-ui-source/blob/943764493e6b16d63ded3ab304150d1f05e58b57/Interface/AddOns/Blizzard_UIPanels_Game/Camelot/CharacterFrameConstants.lua)
  sets the Character frame height to 484 and collapsed width to 398.
- [`PaperDollFrame.xml`](https://github.com/Gethe/wow-ui-source/blob/943764493e6b16d63ded3ab304150d1f05e58b57/Interface/AddOns/Blizzard_UIPanels_Game/Camelot/PaperDollFrame.xml)
  defines `PaperDollFrame.ItemsFrame` at frame level 100, above the model at 50.
  Side slots start at left x=24 and right x=-20, y=-60. Model controls sit near
  the top. `PaperDollFrame.EquipmentManagerPane` is in the right pane.
- [`PaperDollFrame.lua`](https://github.com/Gethe/wow-ui-source/blob/943764493e6b16d63ded3ab304150d1f05e58b57/Interface/AddOns/Blizzard_UIPanels_Game/Camelot/PaperDollFrame.lua)
  anchors the main-hand button at bottom y=30. Off-hand and ranged follow it.
  `PaperDollFrame_ShowSidebar` hides `PaperDollItemsFrame` for the pet sidebar.
- [`ThreeSliceButtonTemplate.xml`](https://github.com/Gethe/wow-ui-source/blob/943764493e6b16d63ded3ab304150d1f05e58b57/Interface/AddOns/Blizzard_SharedXML/Shared/Button/ThreeSliceButtonTemplate.xml)
  defines `SharedButtonSmallTemplate`, with default size 138 by 28. The native
  manager also uses it. WSF uses the same template at 120 by 28.

WSF places two buttons side by side, centered at bottom y=90 in the left pane.
Their total width is 246. This uses the central model area rather than external
panel space, the side slots, the bottom weapon row, or the native manager.
The equip list opens above the buttons and temporarily covers the model.
Source anchors support this placement choice, but they do not prove visual
clearance at every UI scale. Check sockets, flyouts, model input, and gamepad
legends in the client.

### Custom WSF panels

WSF no longer uses StaticPopup dialogs. Earlier StaticPopup callback findings
are not the current WSF contract. Blizzard's native dialogs remain untouched.
The following describes WSF source and policy, not visual client verification:

- Both custom panels have dark-brown backgrounds, gold borders and headings,
  warm text, and subtle separators. Each heading is exactly `Weapon Sets Forever`.
- The native `WSF Save` and `WSF Equip` buttons keep their placement, size 120x28,
  and bottom offset 90. No assets or runtime dependencies are added.
- The save panel exposes `.editBox`, `.saveButton`, and `.cancelButton`.
  Its input is a literal name. Validate before `WSF.Save`; retain input and focus
  after validation or save failure. Save and Enter share one acceptance path.
- Only `WeaponSetsForeverSaveDialog` and `WeaponSetsForeverEquipDialog` are
  prefixed panel globals, registered with `UISpecialFrames` for Escape support.
  Other frames and controls remain local or on their parent.
- Parent hiding closes both panels. Combat entry hides only the save panel.
  The equip list stays open and can open and be browsed in combat. Selecting a
  row is blocked by core once, with clear feedback and no native equip API call.
  Save combat/manager guards still apply at open and acceptance, unchanged.
- The equip tooltip says UI equip is out of combat only; use native `/equipset`
  or player macros in combat.

New in-client checks are required for colors, exact headings, layout, focus,
Escape, combat UI, protected actions, and taint. Mocks cannot prove these results.

### Save-ignore state and native equipping

`PaperDollEquipmentManagerPane_OnEvent` updates a shown manager on
`EQUIPMENT_SETS_CHANGED`. `PaperDollEquipmentManagerPane_Update` loads the
selected set's ignored slots. `PaperDollFrame_IgnoreSlotsForSet` calls native
ignore/unignore functions. Manager hide clears shared flags.

[`EquipmentManagerDocumentation.lua`](https://github.com/Gethe/wow-ui-source/blob/943764493e6b16d63ded3ab304150d1f05e58b57/Interface/AddOns/Blizzard_APIDocumentationGenerated/EquipmentManagerDocumentation.lua)
marks `EQUIPMENT_SETS_CHANGED` synchronous. Thus a save can trigger native UI
flag changes before it returns. UI guards both prompt open and acceptance when
`EquipmentManagerPane:IsVisible()`. Core must enforce this before mutation and
restore shared flags on every outcome. UI does not hide the native pane.

[`SlashCommands.lua`](https://github.com/Gethe/wow-ui-source/blob/943764493e6b16d63ded3ab304150d1f05e58b57/Interface/AddOns/Blizzard_ChatFrameBase/Shared/SlashCommands.lua)
registers `EQUIP_SET` as a secure slash command. It applies
`SecureCmdOptionParse`, looks up the returned full name, then calls
`C_EquipmentSet.UseEquipmentSet(id)`. This does not give a custom UI handler the
same permissions. WSF's custom panels use ordinary UI callbacks, not this secure
native slash path. The owner's repeated same-set comparison confirms native
macro success and WSF UI failure in combat on this beta. Source shows different
paths, but does not establish the internal permission root cause of that failure.
Block WSF equip in combat before the native call; retain out-of-combat safety
checks. Add no macro workaround, secure-macro support, queue, or framework.
Core owns all equip result and completion messages.

### Equipment constants and native name field

[`Blizzard_FrameXMLBase/Constants.lua`](https://github.com/Gethe/wow-ui-source/blob/943764493e6b16d63ded3ab304150d1f05e58b57/Interface/AddOns/Blizzard_FrameXMLBase/Constants.lua#L134-L185)
declares these values in the exact pinned source:

| Constant | Value |
| --- | --- |
| `INVSLOT_MAINHAND` | `16` |
| `INVSLOT_OFFHAND` | `17` |
| `INVSLOT_RANGED` | `18` |
| `INVSLOT_FIRST_EQUIPPED` | `1` (`INVSLOT_HEAD`) |
| `INVSLOT_LAST_EQUIPPED` | `19` (`INVSLOT_TABARD`) |
| `MAX_EQUIPMENT_SETS_PER_PLAYER` | `10` |
| `EQUIPMENT_SET_EMPTY_SLOT` | `0` |
| `EQUIPMENT_SET_IGNORED_SLOT` | `1` |
| `EQUIPMENT_SET_ITEM_MISSING` | `-1` |

These declarations establish source constants, not verified operational
behavior. They do not prove that every native result table uses the same
sentinels. Core compares saved ignore flags and item IDs with locations.
It accepts explicit empty `0`, or an omitted weapon location only with an explicit false ignore flag
and no item ID, as described in the sparse beta results below. Nil alone does not
establish an empty slot. Verify native equip behavior separately.

The native name field has a **16-letter UI limit**.
[`PaperDollFrame.xml`](https://github.com/Gethe/wow-ui-source/blob/943764493e6b16d63ded3ab304150d1f05e58b57/Interface/AddOns/Blizzard_UIPanels_Game/Camelot/PaperDollFrame.xml#L943-L949)
makes `GearManagerPopupFrame` inherit `IconSelectorPopupFrameTemplate`.
[`SharedUIPanelTemplates.xml`](https://github.com/Gethe/wow-ui-source/blob/943764493e6b16d63ded3ab304150d1f05e58b57/Interface/AddOns/Blizzard_SharedXML/Mainline/SharedUIPanelTemplates.xml#L1845-L1846)
defines its `IconSelectorEditBox` with `letters="16"`.
`GearManagerPopupFrameMixin:OkayButton_OnClick` reads that field and passes the
name to native set creation or modification. No name-length override was found
in the reviewed Camelot popup code or shared template Lua.

This verifies the native UI field limit, not an independently documented
`C_EquipmentSet.CreateEquipmentSet` API/server limit. Do not assume that Lua's
byte-counting `#name` equals the edit box's letter count for UTF-8 names.
Test 16- and 17-letter names and non-ASCII names through the native manager,
WSF save panel, and slash command. Check rejection versus truncation and overwrite
safety. WSF's shared `ValidateName` now enforces the 16-letter limit by counting
UTF-8 start bytes in Lua 5.1. The save panel passes the full input to that validator;
it does not silently truncate it. This does not prove native Unicode behavior.

### Ranged support and unresolved core questions

[`PaperDollInfoDocumentation.lua`](https://github.com/Gethe/wow-ui-source/blob/943764493e6b16d63ded3ab304150d1f05e58b57/Interface/AddOns/Blizzard_APIDocumentationGenerated/PaperDollInfoDocumentation.lua)
exposes `IsRangedSlotShown()` returning `isShown`. Camelot uses it to hide the
ranged button and change weapon-row positioning. This is display behavior,
not proof that the slot is unsupported when hidden.

Core requires `GetInventorySlotInfo` to identify all three weapon slots with
the expected IDs before enabling operations. Neither `IsRangedSlotShown()` nor
`IsInventorySlotEnabled(slotName)` discards an empty ranged slot.
Confirm slot lookup and saved-empty behavior in the beta. Source declarations
alone do not establish successful saves or equips for those slots.

Core verification still needs:

1. Confirm `GetInventorySlotInfo` identifies main hand 16, off hand 17, and
   ranged 18 on the target client.
2. Verify all identified weapon slots remain in snapshots, including empty
   hidden ranged, across relevant characters/classes.
3. Verify actual saved item-ID, location, and ignored-slot results against the
   declared constants and the observed sparse result format. Do not interpret
   nil alone as empty. Require an explicit false ignore flag and no item ID.
   Verify native empty-slot equipping separately from reading saved tables.
4. Verify the exact save results and synchronous callbacks before asserting
   saved configuration correctness.
5. Verify `UseEquipmentSet` return/event timing, failure, partial completion,
   hardware-event restrictions, and combat restrictions in the client.

## Local validation

- Inspected the runtime, TOC, documentation, and selected sections of the mock
  suite. The pinned-source findings above remain source evidence only.
- Whitespace checks passed for the four assigned files. The stale-status search
  found no remaining documentation-only or absent-runtime labels in the docs.

### Historical reported validation: 2026-10-12

The owner reported the following results using Lua 5.1.5 from the official
[LuaRocks legacy Windows package](https://luarocks.github.io/luarocks/releases/luarocks-3.13.0-win32.zip).
Archive SHA-256:

```text
97606881b49d944f9febf1f7ae62fa2c2274ccf583ed9dda8fe6170c3e6128e1
```

Only bundled `win32/lua5.1/bin` and `COPYING` were extracted under ignored
`.tools/`. No installer ran and no PATH change was made. This is development
tooling, not an AddOn runtime dependency.

Commands from the Git Bash repository root:

```sh
.tools/luarocks-3.13.0-win32/win32/lua5.1/bin/lua5.1.exe tests/run.lua
.tools/luarocks-3.13.0-win32/win32/lua5.1/bin/luac5.1.exe -p Commands.lua Equipment.lua Core.lua UI.lua tests/run.lua
```

- Mock suite: **203/203 passed**.
- Syntax check: **passed** for all four runtime Lua files and `tests/run.lua`.
- Independent review: same suite **203/203 passed**; no high-priority bugs found.

The initial automated run and independent review preceded the client finding
below. Their mocks assumed explicit location sentinels for ignored/empty slots.
The passing results did not prove that assumption.

### Sparse beta results and regression fix: 2026-10-12

The owner reported a verification error after saving `Shield-Set`, set ID 2.
Read-only client probes returned:

- `GetIgnoredSlots`: true for slots 1..15 and 19; false for 16, 17, and 18.
- `GetItemLocations`: only `[16] = 1048592`, `[17] = 1048593`.
- `GetItemIDs`: only `[16] = 2011`, `[17] = 6320`.

This verifies the non-weapon ignore flags and sparse returned tables. It does
not independently verify that native equipping restores an empty ranged slot.

The fix accepts omitted ignored locations. It normalizes an omitted weapon
location only when the ignore flag is explicitly false and the item ID is absent.
It does not mutate native result tables. Unknown slot data, absent occupied
locations, and explicit missing-item sentinels remain failures.

Added eight regression tests, including the supplied Shield-Set data. Executed
the commands above under Lua 5.1.5: **211/211 tests passed**, and syntax checks
passed for all runtime Lua files plus the tests. Retest the updated Equipment.lua
in client. The remaining checklist items are still open.

### Latest reported validation: 2026-10-12

The owner supplied the completed agent-executed results under Lua 5.1.5:

- Mock suite: **270/270 passed**.
- Syntax check: **passed** with
  `luac5.1 -p Commands.lua Equipment.lua Core.lua UI.lua tests/run.lua`.

The latest coverage includes:

- Combat rejection in `Equipment.PrepareEquip` before any native equip API call.
- Exactly one core message with native `/equipset` guidance; no duplicate UI feedback.
- Combat list opening, browsing, and paging, plus retention when combat starts.
- A false equip return and clear error guidance that keep the list open.
- Tooltip guidance for out-of-combat UI equip and native commands/macros in combat.
- No deferred equip queue; combat exit does not execute a rejected request.
- Unchanged combat and Equipment Manager save guards.

The earlier **263/263** agent-executed run on 2026-10-12 preceded restoration of
the combat guard. It is historical, as are the 203/203 and 211/211 runs above.
These reported results were not rerun for this documentation update.
Mocks do not verify panel colors, layout, native combat permissions, or taint.

### Owner-reported follow-up tests: 2026-10-12

After the suggested checks for unchanged armor, empty off-hand/two-handed
restoration, reload/relog persistence, and combat behavior, the owner reported
"Tests passed." Treat this as an initial user-reported pass, not a full client
compatibility result. Detailed per-case results were not supplied.

The owner also reported that an earlier set removed armor mid-combat. Re-saving
that set resolved the issue. No original set tables were captured. The sparse
fix changed verification, not the native save operation; it does not establish
the cause of the earlier armor removal. Native `/equipset` does not use WSF's
validation. Re-save early experimental sets before using them in combat.

The owner conclusively repeated the same-set combat comparison on the target
beta. Custom WSF UI could not swap and reported a generic WSF swap failure that
referred to bag space. The following native macro worked:

```text
/equipset [noequipped:shield] Shield-Set; DPS-Set
```

Record this as a confirmed owner-observed beta limitation, not an independently
instrumented result or proof of an internal permission root cause. Native combat
support remains owner-confirmed. Recommend this macro for the owner's named sets.
The earlier authorization for direct WSF combat API testing is superseded by an
out-of-combat core guard. New guard, tooltip, panel visuals, and taint checks
remain open. Do not treat the earlier smoke test as verification of these changes.

The checklist below remains the full test plan. The reported pass does not
close unreported cases such as ammo, ranged empties, item failures, taint, and
character isolation.

## Local release automation validation: 2026-10-13

Executed locally after working-tree text normalization to LF:

- Lua 5.1.5 suite: **270/270 passed**. Keep the original 2026-10-12 results above
  as history, not a replacement for this run.
- Lua syntax checks passed for Commands.lua, Equipment.lua, Core.lua, UI.lua,
  and tests/run.lua. Syntax checks also passed for all four Lua files extracted
  from the generated release ZIP.
- Python 3.13.7 suite: **62/62 passed**, comprising 22 ZIP-builder, 30 CurseForge
  publisher, and 10 provenance tests. These are offline tests with mocked APIs.
- Python compilation passed for scripts/build_release.py,
  scripts/publish_curseforge.py, and scripts/verify_release.py.
- actionlint 1.7.12 passed for .github/workflows/release.yml after the final
  source-commit and remote-tag verification edits.
- The builder created the exact six-file WeaponSetsForever-0.1.0-beta.zip.
  Archive validation and integrity checks passed. SHA-256:

```text
ccebf3646175de74b2ff27c7f497c33ac80f63fba2c584a009604e33ce4f74cf
```

Python is the portable Windows 3.13.7 interpreter from the reviewed official
[python.org embedded archive](https://www.python.org/ftp/python/3.13.7/python-3.13.7-embed-amd64.zip),
extracted under ignored .tools/python-3.13.7/. No installer ran and PATH did not
change. actionlint came from its official
[v1.7.12 release](https://github.com/rhysd/actionlint/releases/tag/v1.7.12).
These tools are development-only and are excluded from the installable package.

Commands use .tools/python-3.13.7/python.exe locally. On the Ubuntu CI runner,
use native python3 and apt's lua5.1, not the local Windows executables.

The local build manifest has no source_commit because local main has no commits.
CI records its actual GITHUB_SHA. Source-commit metadata is external provenance,
not a commit inferred from the ZIP. The provenance verifier checks that the
remote annotated or lightweight tag still points to that tested commit.

The working tree and tracked text report i/lf w/lf through git ls-files --eol.
Binary logo bytes are unchanged. Normalization did not stage or renormalize the
index, and the existing core.autocrlf=input setting was left unchanged.
No runtime logic changed as part of the line-ending fix.

No GitHub-hosted workflow run, live CurseForge upload, or client installation
from this ZIP was tested. Local tests and lint do not prove remote publication,
configured approval gates, manager update detection, or full client compatibility.
See [docs/RELEASE_PLAN.md](docs/RELEASE_PLAN.md) for installed workflow setup,
publication controls, and retry restrictions.

## In-client checklist

Use disposable unique names first. For each case, record the build, character,
class, initial gear, set configuration, action, result, messages, and errors.
Record each non-weapon slot before and after every save/equip test.

### Installation and UI

- [ ] Install the existing TOC and runtime files. Confirm Interface 16001 and
      load order Commands, Equipment, Core, UI. Copy the five files under
      `Interface/AddOns/WeaponSetsForever/`.
- [ ] Verify core accepts version 1.60.1 / build 70338 / Interface 16001 and
      rejects mismatched values or missing slot identities before unsafe operations.
- [ ] Login and `/reload` with the Character panel closed and open. Confirm
      initial availability does not depend on core/UI login-handler order.
- [ ] Test unavailable capability. Buttons must disable without event errors.
      Test absent C_Timer and absent/non-function C_Timer.After with both login
      handler orders. Expect one core capability report and no UI exception.
- [ ] Check collapsed/expanded right pane, stats/title/set/pet sidebars,
      Character mode changes, window position, UI scale, and display size.
- [ ] Verify both custom panels have dark-brown backgrounds, gold borders and
      headings, warm text, and subtle separators. Check the exact heading
      `Weapon Sets Forever` on each panel. Record new actual client results.
- [ ] Confirm native WSF Save/Equip buttons retain their placement, size 120x28,
      and bottom offset 90. Check panel/button clearance, socket displays,
      item flyouts, model controls, and gamepad legend at different UI scales.
      Confirm pet view and parent hiding close both WSF panels.
- [ ] Confirm WSF opens no StaticPopup dialogs and leaves Blizzard's native
      dialogs untouched. Check Escape closes either custom panel through
      `UISpecialFrames` and only the two prefixed panel globals are exposed.
- [ ] Check zero, one, eight, nine, and ten sets. Check long names, paging,
      deletion/rename while the list is open, tooltips, and Close.
- [ ] Check `.editBox`, `.saveButton`, and `.cancelButton`. Check Save, Enter,
      Cancel, and Escape. Save once per action through the shared acceptance path.
      Validate literal names before Save. Preserve input and focus on validation
      and save failures. Names with spaces need no quotes in the save panel.
- [ ] Enter combat with the save panel open. Only the save panel must hide.
      Saves must remain blocked. Repeat with the equip list open; it must remain
      open and browsable. Open the list during combat and select a row. Expect
      exactly one core message:
      `WSF cannot equip from its UI in combat. Use native /equipset instead.`
      Confirm no native equip API call. Check the tooltip's out-of-combat UI and
      native/macros combat guidance. Check combat exit, taint logs, Lua errors,
      and out-of-combat equip. Native success does not prove custom UI permissions.

### Parsing and save safety

- [ ] Test `/wsf save Daggers` and `/wsf save "Tank Weapons"`.
- [ ] Reject missing/empty/whitespace-only names, extra arguments, unmatched
      quotes, malformed adjacent quotes/text, and unquoted multi-word names.
      Check supported argument delimiters. No set may change after rejection.
- [ ] Test native names at 16 and 17 letters, plus UTF-8 names. Compare native
      manager, WSF save panel, and slash behavior. Check for truncation, rejected names,
      accidental same-prefix overwrites, and byte/letter-count differences.
- [ ] Save from the custom panel and slash command in combat. Neither may mutate a set.
- [ ] Save with the native manager visible, both with and without a selection.
      Expect the instruction to close the Equipment Manager pane.
- [ ] Open the WSF prompt, then show the manager before acceptance. Acceptance
      must fail without mutation and retain input and focus. UI must not hide the pane.
- [ ] Overwrite a same-name set made by WSF and one made by Blizzard's manager,
      including a full outfit. No extra confirmation. Verify weapon-only saved
      configuration and unchanged currently equipped gear.
- [ ] Verify shared ignore flags restore after every successful and failed save.
      Test native set changes and reopening the manager after saving.
      Mock-inject programming defects to verify restoration attempts and rethrows,
      including visible restoration errors.

### Equipment, failures, and persistence

- [ ] Save/equip one-handed pairs, shields, held off-hand items, and two-handed
      weapons. Test transitions in both directions.
- [ ] Preserve empty main hand, off hand, and supported ranged, including hidden
      empty ranged. Compare native IDs, locations, and ignored-slot values.
      Verify empty-slot restoration with the observed sparse tables. An omitted
      location needs an explicit false ignore flag and no item ID. Check explicit
      empty `0`, ignored `1`, and missing `-1` results when the client returns them.
- [ ] Verify ignored non-weapon slots in `1..19` stay unchanged.
- [ ] Verify native ammo slot `0` behavior and unchanged ammo separately. WSF
      does not individually set slot-0 ignore flags; mocks do not prove its behavior.
- [ ] Test duplicate identical items and movement between bags/slots.
- [ ] Test missing, unavailable, or locked items, casting, full bags, native set
      limits, unknown sets, failed swaps, and partial swaps. Retain weapon-only
      safety checks out of combat; combat selection must stop before the native
      equip API call. No unverified rollback or equip queue.
- [ ] Check exactly one core equip feedback path. No UI success or duplicate
      failure messages. Success must reflect confirmed completion.
      Check synchronous events, accepted pending swaps, late/unrelated events,
      and the single five-second fallback. Confirm no repeated/idle polling.
- [ ] Test native `/equipset` with single/multi-word names and player macros.
      Record actual out-of-combat and combat restrictions. Do not infer that a
      custom AddOn handler has native secure-command permission.
- [ ] Verify native sets after `/reload` and relog. Verify the same name on two
      characters remains isolated. Confirm no AddOn SavedVariables are needed.

## Automated coverage and remaining checks

`tests/run.lua` contains mock tests for parsing/name validation, capabilities,
save/overwrite and empty slots, flag restoration and defects, equipment swaps,
and custom-panel behavior. It also compiles runtime Lua files under Lua 5.1.
The latest reported suite passed 270/270 under Lua 5.1.5 on 2026-10-12.
The separate syntax check passed for all four runtime Lua files and tests/run.lua.
Historical results appear in Local validation above.

Keep UI regression checks for save-panel guards, literal-name validation, input
and focus retention, shared Save/Enter acceptance, no StaticPopup use, Escape,
core-owned equip feedback, paging, parent visibility, combat hiding only save,
and both login-handler orders, including missing timer APIs. Retain the passing
regressions for combat rejection before any native equip call, exactly one core
error, combat list browsing/paging, retention after a false equip return,
error/tooltip guidance, no equip queue, and unchanged save guards.
Keep checks for duplicates, locks, missing items, full bags, set limits, and
failed/partial swaps. Mock checks cannot establish taint or native game behavior.
