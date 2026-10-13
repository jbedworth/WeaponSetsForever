# Verification and test plan

This document describes how Weapon Sets Forever is verified: the runtime
contract under test, the pinned client-source evidence behind design decisions,
the automated test method, and the in-client checklist.

## Verification approach

WSF is verified in three layers, and each proves different things:

1. **Pinned source review.** Client behavior is read from Blizzard's FrameXML
   and generated API documentation at a pinned commit matching the target build.
   Source establishes declared constants, templates, and code paths, not
   operational behavior.
2. **Automated mock tests.** `tests/run.lua` exercises parsing, validation,
   equipment-operation logic, and panel behavior against minimal WoW API mocks
   under Lua 5.1. Python unit tests cover the release helpers. Mocks cannot
   establish protected-action permissions, taint, visual layout, or actual
   equipment changes.
3. **In-client checks.** The checklist below covers everything mocks cannot.
   Client observations that contradict a mock assumption take precedence; fix
   the mock and add a regression test that encodes the observed behavior.

Keep these layers distinct when reporting results. Do not present a source
finding or a passing mock run as client verification.

Target: Forever beta `1.60.1.70338`, Interface `16001`, Lua `5.1`. Core does
not gate on client version, build, or Interface; it gates only on the required
APIs, constants, and slot identities, so later beta builds keep working unless
those change.

## Runtime contract

- `Commands.lua` validates exactly one save name and counts UTF-8 start bytes
  against a 16-letter limit. Custom save-panel and slash saves use the shared validator.
- `Equipment.lua` checks required APIs/constants and all three slot identities (main 16, off 17, ranged 18). It does not discard
  a slot based on ranged visibility or `IsInventorySlotEnabled`.
- Save-ignore operations cover equipped slots `1..19` except weapons `16/17/18`.
  The code does not individually operate on ammo slot `0`; ammo is outside scope.
- Saves verify saved ignore flags, item IDs, and locations. Omitted ignored
  locations are accepted. An omitted weapon location is treated as empty only
  with an explicit false ignore flag and no saved item ID.
  A narrow protected save region attempts shared-flag restoration after a
  programming defect, then rethrows. Restoration errors are also rethrown.
- `Core.lua` starts unavailable and checks capabilities at `PLAYER_LOGIN`.
  It then prints one banner (`Title Version by Author`, read through
  `C_AddOns.GetAddOnMetadata`, with a fixed title fallback), followed by a
  ready hint or the unavailable reason. Metadata never gates operations.
  Missing capabilities disable operations and produce one login report.
  A missing `C_Timer.After` also disables core operations.
- `/wsf debug_swap` (session-only, off by default) prints swap state at the
  native use call, at completion (`via=` equipment, event, immediate, fallback,
  or rejected), at each `EQUIPMENT_SWAP_FINISHED` event, and one second later.
  Diagnostics run after swap state settles; tests require that a diagnostic
  defect propagates without stranding a pending swap. Use it to compare WSF and native `/equipset`
  timing in the client; it never changes swap outcomes.
- `Equipment.PrepareEquip` rejects combat before any
  `C_EquipmentSet.UseEquipmentSet` call and returns the exact error
  `WSF cannot equip from its UI in combat. Use native /equipset instead.`
  Core reports it once; UI adds no feedback. Out-of-combat weapon-only validation,
  missing-item, item-lock, casting, and completion checks remain.
- Equip completion: a false `EQUIPMENT_SWAP_FINISHED` result fails at once; a
  true result succeeds when `isEquipped` is true or `WSF.WeaponsMatchSet`
  confirms slots 16 to 18 hold the saved items (or are empty where saved
  empty). Client traces show `EQUIPMENT_SWAP_FINISHED` fires with
  `result=true` before items move and with `isEquipped=false`; one second later
  the weapons match and `isEquipped` is true, for weapon and all-empty sets.
  While a swap is pending, `PLAYER_EQUIPMENT_CHANGED` re-checks this verified
  state, so success reports as soon as the gear changes. Core also checks at
  login that every runtime file comes from the same version.
  An accepted pending swap gets one five-second fallback state check, not idle
  polling. Core owns all equip failure/completion feedback.
- UI guards its deferred login call with timer table/function checks. If the
  timer is absent, it updates directly without a timer exception; core remains
  responsible for disabling operations. Both login-handler orders are tested.
- `/wsf export Name` (alias `/wsf debug_probe`; `WSF.ProbeSet`) prints the raw native tables for
  slots `1..19`, the `GetEquipmentSetInfo` returns named in documented order,
  decoded locations, the client build, and current gear as JSON. It does not
  validate or mutate anything. Absent slot entries print as `null`, and `|` and
  control characters are escaped so the chat line cannot form UI escape sequences.
  Location decoding uses the pinned `ITEM_INVENTORY_LOCATION_PLAYER` (`0x100000`),
  `_BAGS` (`0x200000`), and `_BANK` (`0x400000`) flags, with the bag index shifted
  by `ITEM_INVENTORY_BAG_BIT_OFFSET` (8) and the slot in the low byte. Any other
  set bits are reported as `otherBits` rather than interpreted.
  With no name (`WSF.ProbeEquipped`), it probes every set whose
  `GetEquipmentSetInfo` `isEquipped` return is exactly `true`, or reports only
  the client and current gear when none is.
- The TOC uses Interface 16001, loads Commands, Equipment, Core, then UI, and
  declares no SavedVariables. Equipping by command is native `/equipset`;
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
  manager also uses it. WSF uses the same template for buttons inside its panels.
- The same `PaperDollFrame.xml` stacks the left column from `CharacterHeadSlot`
  down to `CharacterWristSlot`, and the right column from `CharacterHandsSlot`
  down to `CharacterTrinket1Slot`, with 6-pixel gaps.

WSF places a 28x28 icon-only Save button 6 pixels beneath `CharacterWristSlot`
and an Equip button 6 pixels beneath `CharacterTrinket1Slot`. Stat AddOns
commonly draw text beside the slots and the weapon row, and the earlier centered
text buttons covered that text; the space beneath each column is outside it.
Save shows `Textures/SaveIcon.tga`, a 64 x 64 crop of the logo emblem built
by `scripts/build_icon.py`; Equip shows the built-in `INV_Sword_04` icon. Both
use the `ButtonHilight-Square` highlight. Both panels open centered at bottom y=124 in
the left pane and temporarily cover the model. If either anchor slot is
missing, WSF creates no controls. Source anchors do not prove visual clearance
at every UI scale, or that these icon files exist on the client. Check icons,
sockets, flyouts, model input, and gamepad legends in the client.

### Custom WSF panels

WSF does not use StaticPopup dialogs; Blizzard's native dialogs remain untouched.
The following is WSF source and policy, not visual client verification:

- Both custom panels have dark-brown backgrounds, gold borders and headings,
  warm text, and subtle separators. Each heading is exactly `Weapon Sets Forever`.
- The icon-only Save and Equip buttons sit beneath the left and right slot
  columns, keep their tooltips, and desaturate when WSF is unavailable. No
  assets or runtime dependencies are added.
- The save panel exposes `.editBox`, `.saveButton`, and `.cancelButton`.
  Its input is a literal name. Validate before `WSF.Save`; retain input and focus
  after validation or save failure. Save and Enter share one acceptance path.
- Only `WeaponSetsForeverSaveDialog` and `WeaponSetsForeverEquipDialog` are
  prefixed panel globals, registered with `UISpecialFrames` for Escape support.
  Other frames and controls remain local or on their parent.
- Parent hiding closes both panels. Combat entry hides only the save panel.
  The equip list stays open and can open and be browsed in combat. Selecting a
  row is blocked by core once, with clear feedback and no native equip API call.
  Save combat/manager guards apply at open and acceptance.
- The equip tooltip says UI equip is out of combat only; use native `/equipset`
  or player macros in combat.

### Save-ignore state and native equipping

`PaperDollEquipmentManagerPane_OnEvent` updates a shown manager on
`EQUIPMENT_SETS_CHANGED`. `PaperDollEquipmentManagerPane_Update` loads the
selected set's ignored slots. `PaperDollFrame_IgnoreSlotsForSet` calls native
ignore/unignore functions. Manager hide clears shared flags.

[`EquipmentManagerDocumentation.lua`](https://github.com/Gethe/wow-ui-source/blob/943764493e6b16d63ded3ab304150d1f05e58b57/Interface/AddOns/Blizzard_APIDocumentationGenerated/EquipmentManagerDocumentation.lua)
marks `EQUIPMENT_SETS_CHANGED` synchronous. Thus a save can trigger native UI
flag changes before it returns. UI guards both prompt open and acceptance when
`EquipmentManagerPane:IsVisible()`. Core enforces this before mutation and
restores shared flags on every outcome. UI does not hide the native pane.

[`SlashCommands.lua`](https://github.com/Gethe/wow-ui-source/blob/943764493e6b16d63ded3ab304150d1f05e58b57/Interface/AddOns/Blizzard_ChatFrameBase/Shared/SlashCommands.lua)
registers `EQUIP_SET` as a secure slash command. It applies
`SecureCmdOptionParse`, looks up the returned full name, then calls
`C_EquipmentSet.UseEquipmentSet(id)`. This does not give a custom UI handler the
same permissions. WSF's custom panels use ordinary UI callbacks, not this secure
native slash path. In client, the native macro swaps in combat while the WSF UI
path does not; source shows the different paths but does not establish the
internal permission root cause. WSF therefore blocks UI equips in combat before
the native call and retains out-of-combat safety checks. No macro workaround,
secure-macro support, queue, or framework is in scope.

### Equipment constants and native name field

[`Blizzard_FrameXMLBase/Constants.lua`](https://github.com/Gethe/wow-ui-source/blob/943764493e6b16d63ded3ab304150d1f05e58b57/Interface/AddOns/Blizzard_FrameXMLBase/Constants.lua#L134-L185)
declares these values in the pinned source:

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

These declarations establish source constants, not operational behavior, and do
not prove that every native result table uses the same sentinels. Core compares
saved ignore flags and item IDs with locations. It accepts explicit empty `0`,
or an omitted weapon location only with an explicit false ignore flag and no
item ID (see the sparse result format below). Nil alone does not establish an
empty slot.

The native name field has a **16-letter UI limit**.
[`PaperDollFrame.xml`](https://github.com/Gethe/wow-ui-source/blob/943764493e6b16d63ded3ab304150d1f05e58b57/Interface/AddOns/Blizzard_UIPanels_Game/Camelot/PaperDollFrame.xml#L943-L949)
makes `GearManagerPopupFrame` inherit `IconSelectorPopupFrameTemplate`.
[`SharedUIPanelTemplates.xml`](https://github.com/Gethe/wow-ui-source/blob/943764493e6b16d63ded3ab304150d1f05e58b57/Interface/AddOns/Blizzard_SharedXML/Mainline/SharedUIPanelTemplates.xml#L1845-L1846)
defines its `IconSelectorEditBox` with `letters="16"`.
`GearManagerPopupFrameMixin:OkayButton_OnClick` reads that field and passes the
name to native set creation or modification. No name-length override exists in
the reviewed Camelot popup code or shared template Lua.

This is the native UI field limit, not an independently documented
`C_EquipmentSet.CreateEquipmentSet` API/server limit. Lua's byte-counting
`#name` does not equal the edit box's letter count for UTF-8 names, so WSF's
shared `ValidateName` counts UTF-8 start bytes. The save panel passes the full
input to that validator; it never silently truncates it. Native Unicode
behavior is an in-client check.

### Sparse native result tables

Native set queries return sparse tables that omit ignored locations. For
example, a shield set saved with only slots 16, 17, and 18 un-ignored returns:

- `GetIgnoredSlots`: true for slots 1..15 and 19; false for 16, 17, and 18.
- `GetItemLocations`: only `[16] = 1048592`, `[17] = 1048593`.
- `GetItemIDs`: only `[16] = 2011`, `[17] = 6320`.

Verification therefore accepts omitted ignored locations and normalizes an
omitted weapon location to empty only when the ignore flag is explicitly false
and the item ID is absent. It does not mutate native result tables. Unknown slot
data, absent occupied locations, and explicit missing-item sentinels remain
failures. The mock suite includes this shape as a regression fixture. Reading a
saved table does not prove that native equipping restores an empty slot.

### Packed item locations and set info

[`Blizzard_FrameXMLBase/Constants.lua`](https://github.com/Gethe/wow-ui-source/blob/943764493e6b16d63ded3ab304150d1f05e58b57/Interface/AddOns/Blizzard_FrameXMLBase/Constants.lua#L129-L132)
declares `ITEM_INVENTORY_LOCATION_PLAYER = 0x00100000`,
`ITEM_INVENTORY_LOCATION_BAGS = 0x00200000`,
`ITEM_INVENTORY_LOCATION_BANK = 0x00400000`, and
`ITEM_INVENTORY_BAG_BIT_OFFSET = 8`. Client probes match this packing: an
equipped main hand is `0x100010`, and a saved item in bag 3, slot 3 is `0x300303`.

[`EquipmentManagerDocumentation.lua`](https://github.com/Gethe/wow-ui-source/blob/943764493e6b16d63ded3ab304150d1f05e58b57/Interface/AddOns/Blizzard_APIDocumentationGenerated/EquipmentManagerDocumentation.lua)
documents `GetEquipmentSetInfo` returns as `name`, `iconFileID`, `setID`,
`isEquipped`, `numItems`, `numEquipped`, `numInInventory`, `numLost`, and
`numIgnored`. On the target client, `numIgnored` can be `0` for a set with
ignored slots, so its meaning is unverified; WSF does not use it.

### Ranged support

[`PaperDollInfoDocumentation.lua`](https://github.com/Gethe/wow-ui-source/blob/943764493e6b16d63ded3ab304150d1f05e58b57/Interface/AddOns/Blizzard_APIDocumentationGenerated/PaperDollInfoDocumentation.lua)
exposes `IsRangedSlotShown()` returning `isShown`. Camelot uses it to hide the
ranged button and change weapon-row positioning. This is display behavior,
not proof that the slot is unsupported when hidden.

Core requires `GetInventorySlotInfo` to identify all three weapon slots with
the expected IDs before enabling operations. Neither `IsRangedSlotShown()` nor
`IsInventorySlotEnabled(slotName)` discards an empty ranged slot.

### Open client questions

Source alone cannot answer these; they belong to in-client testing:

1. Whether `GetInventorySlotInfo` identifies main hand 16, off hand 17, and
   ranged 18 on every relevant character and class.
2. Whether all weapon slots, including empty hidden ranged, round-trip through
   save and equip.
3. Whether explicit empty `0`, ignored `1`, and missing `-1` sentinels appear in
   any native results, and how native equipping handles saved empty slots.
4. Exact save results and synchronous callbacks for each save path.
5. `UseEquipmentSet` return/event timing, failure, partial completion,
   hardware-event restrictions, and combat restrictions.
6. Native ammo behavior, and Unicode name handling in the native manager.

## Automated tests

### Tooling

Lua 5.1 comes from the official
[LuaRocks legacy Windows package](https://luarocks.github.io/luarocks/releases/luarocks-3.13.0-win32.zip),
archive SHA-256:

```text
97606881b49d944f9febf1f7ae62fa2c2274ccf583ed9dda8fe6170c3e6128e1
```

Extract only the bundled `win32/lua5.1/bin` and `COPYING` under ignored
`.tools/`. No installer or PATH change is needed.

Python is the portable Windows 3.13.7 interpreter from the official
[python.org embeddable archive](https://www.python.org/ftp/python/3.13.7/python-3.13.7-embed-amd64.zip),
extracted under ignored `.tools/python-3.13.7/`. Workflow linting uses
[actionlint](https://github.com/rhysd/actionlint/releases/tag/v1.7.12).
All of these are development-only and excluded from the installable package.
On the Ubuntu CI runner, use native `python3` and apt's `lua5.1`, not the local
Windows executables.

### Commands

From the Git Bash repository root:

```sh
.tools/luarocks-3.13.0-win32/win32/lua5.1/bin/lua5.1.exe tests/run.lua
.tools/luarocks-3.13.0-win32/win32/lua5.1/bin/luac5.1.exe -p Commands.lua Equipment.lua Core.lua UI.lua tests/run.lua
.tools/python-3.13.7/python.exe -m unittest discover -s tests -p 'test_*.py'
```

### Coverage

`tests/run.lua` contains mock tests for parsing/name validation, capabilities,
save/overwrite and empty slots, flag restoration and defects, equipment swaps,
and custom-panel behavior. It also compiles runtime Lua files under Lua 5.1.
The Python suite covers the ZIP builder, CurseForge publisher, and provenance
verifier offline with mocked APIs.

Maintain regression coverage for:

- Save-panel guards, literal-name validation, input and focus retention, shared
  Save/Enter acceptance, no StaticPopup use, and Escape.
- Core-owned equip feedback, paging, parent visibility, combat hiding only the
  save panel, and both login-handler orders, including missing timer APIs.
- Combat rejection before any native equip call, exactly one core error, combat
  list browsing/paging, retention after a false equip return, error/tooltip
  guidance, no equip queue, and unchanged save guards.
- Duplicates, locks, missing items, full bags, set limits, sparse native result
  tables, and failed/partial swaps.

Mocks encode assumptions about the client. When a client observation differs
from a mock, treat the mock as wrong, update it, and add a regression test.

## In-client checklist

Use disposable unique names first. For each case, record the build, character,
class, initial gear, set configuration, action, result, messages, and errors.
Record each non-weapon slot before and after every save/equip test.
`/wsf export Name` captures the native set tables and current gear in one
step; run it before and after an action and compare the `current` objects.
Enable `/chatlog` to copy the output from `Logs/WoWChatLog.txt`.

### Installation and UI

- [ ] Install the TOC and runtime files under
      `Interface/AddOns/WeaponSetsForever/`. Confirm Interface 16001 and load
      order Commands, Equipment, Core, UI.
- [ ] Verify core runs on the current beta build and rejects missing APIs,
      constants, or slot identities before unsafe operations.
- [ ] Login and `/reload` with the Character panel closed and open. Confirm
      initial availability does not depend on core/UI login-handler order.
- [ ] Test unavailable capability. Buttons must disable without event errors.
      Test absent C_Timer and absent/non-function C_Timer.After with both login
      handler orders. Expect one core capability report and no UI exception.
- [ ] Check collapsed/expanded right pane, stats/title/set/pet sidebars,
      Character mode changes, window position, UI scale, and display size.
- [ ] Verify both custom panels have dark-brown backgrounds, gold borders and
      headings, warm text, and subtle separators. Check the exact heading
      `Weapon Sets Forever` on each panel.
- [ ] Confirm the Save and Equip icons render (not blank or green), sit beneath
      the wrist and lower trinket slots, show tooltips, and do not cover stat
      AddOn text. Check panel/button clearance, socket displays,
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
      Verify empty-slot restoration with sparse tables. An omitted location
      needs an explicit false ignore flag and no item ID. Check explicit empty
      `0`, ignored `1`, and missing `-1` results when the client returns them.
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
