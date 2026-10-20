# Agent Guidelines

## Project purpose and scope

Weapon Sets Forever is a small, lightweight World of Warcraft: Forever AddOn.
Its scope is saving and equipping named weapon-only snapshots through
Character-panel buttons, `/wsf save {set-name}`, and native `/equipset`.
`/wsf export {set-name}` (alias `/wsf debug_probe`) is an author-approved,
read-only command that prints a native set's raw tables and current gear as
one JSON chat line. Output repeats the command word the user typed. It
uses the save argument rules but not save-name validation, never mutates state,
and may run in combat. With no name it probes each set the client marks
equipped, or prints only current gear when none is.
`/wsf debug_swap [on|off]` is an author-approved, session-only diagnostic. When
on, it prints swap state (set, isEquipped, weapon item IDs) at WSF's native use
call, at completion (with the path that decided it), at each
EQUIPMENT_SWAP_FINISHED event (including native `/equipset`), and one second
after each event. It is off by default, never persists, and never changes swap
outcomes. Run diagnostics only after swap state is settled, so a diagnostic
defect surfaces as an error but can never strand a pending swap. Prefer adding
`/wsf debug_*` commands over long `/run` scripts, which exceed the chat limit.
Do not implement `/wsf set` or speculative secure macro combat support.
Primary and secondary mean main hand and off hand; include the ranged slot when
supported by the target client. Off-hand shields and held items are in scope.
Leave armor, trinkets, and all other equipment unchanged. Sets and any AddOn
metadata must be per character. Talent-spec-specific sets are optional future
scope, not a requirement.

Command arguments are space-delimited; double quotes are required for multi-word
save names. `/wsf save` requires exactly one non-empty name argument.
Custom save-panel input is a literal name, not a command argument string;
spaces need no quotes.
Native `/equipset` has its own parser. Do not apply save-parser rules to it.
Reject missing/empty names, unmatched or malformed quotes, and extra arguments before mutation;
never silently truncate an unquoted multi-word name to its first word.

Keep this narrow feature set. Do not add automatic switching, general
outfit management, frameworks, or speculative features without agreement.

## Project structure

- Runtime files are Commands.lua, Equipment.lua, Core.lua, UI.lua, and
  WeaponSetsForever.toc. Commands owns parsing/name validation; Equipment owns
  native operations and preconditions; Core owns events/equip feedback; UI owns
  Character-panel controls and custom dialogs. Preserve existing runtime
  behavior and user work; do not replace the implementation with scaffolding.
- tests/run.lua holds the Lua 5.1 mock suite. tests/test_*.py cover the release
  helpers in scripts/. .github/workflows/release.yml runs CI and opt-in publishing.
- README.md is the user-facing overview, TESTING.md the verification method,
  source evidence, and in-client checklist, and docs/RELEASE_PLAN.md the release
  process. artwork/ holds publishing images.
- Documentation describes purpose, design, rules, and methodology. Do not add
  dated status reports, test-result logs, or progress notes to the docs; report
  results in conversation, commits, CI runs, or release records instead.
- The project uses the MIT License. The original brown/gold shield-and-swords
  logo in artwork/ is publishing material. The one author-approved runtime
  derivative is Textures/SaveIcon.tga, built from it by scripts/build_icon.py.
- The public author name is `Dyre`, the author's in-game name: use it in the TOC
  `## Author` field (shown in the login banner) and public listings. The MIT
  copyright notice keeps the legal name, John Bedworth; the release builder
  requires that exact notice in LICENSE.
- The TOC uses the built-in INV_Sword_04 icon and `## Category: Bags & Inventory`,
  the author-selected text matching the CurseForge category. The pinned
  AddonList.lua groups AddOns by exact category string; keep the two identical.
- Dyre's Toolkit (`DyresToolkit`, its own repository, owned by the
  coordinating session; do not edit it here) gives Dyre's AddOns one layout
  mode, minimap menu, and settings home. WSF has no movable frame, settings
  page, or saved variables, so it joins only the AddOn list:
  `## Group: DyresToolkit` nests it under the toolkit there. `## Category`
  then matters only when the toolkit is missing. WSF code does not use the
  toolkit: no `## OptionalDeps` (add it only when the code joins the
  toolkit; author has not decided) and no login line about it. CurseForge
  relations (author-set, 2026-10-20): Dyre's Toolkit required, Weapon Skills
  Forever optional; `RELATIONS` in scripts/publish_curseforge.py sends them,
  never as an empty list (CurseForge answers HTTP 400).
- Git origin is git@github.com:jbedworth/WeaponSetsForever.git. Always inspect
  current Git state before acting, and preserve user work.
- Text is LF under .gitattributes (* text=auto eol=lf; PNG/JPG/GIF/WebP/ZIP
  binary). Do not renormalize the index or change global Git settings without
  authorization.

## Client and API verification

- Use Blizzard's in-game AddOn API, not the Battle.net web API.
- The development target is Forever beta 1.60.1, build 70450, Interface 16001,
  Lua 5.1, with native equipment-set creation, ignore-slot, and equip functions.
  Reverify before supporting launch or any other client.
- Preserve the verified API boundary. Verify client build, Lua runtime,
  Interface/TOC version, slot identities, and affected UI/API behavior before
  adding support for another client or changing client-dependent code.
- Pin source review to Gethe/wow-ui-source commit
  `943764493e6b16d63ded3ab304150d1f05e58b57`, version `1.60.1.70338` (the
  70338 source; the client is tested on build 70450).
  Record source findings and unresolved behavior in TESTING.md.
- Do not gate the runtime on client version, build, or Interface: the author
  dropped that check because Forever beta builds ship several times a week.
  Gate only on required APIs/constants and verified slot identities: main 16,
  off 17, ranged 18.
  Require all three slots. Do not drop hidden empty ranged based on
  IsRangedSlotShown or IsInventorySlotEnabled. Native result tables omit
  ignored locations. Treat an omitted weapon location as empty only with an
  explicit false ignore flag and no item ID; do not infer empty from nil alone.
- Names have at most 16 letters, matching the native UI field limit. Count UTF-8
  start bytes in Lua 5.1, not raw string bytes; verify native Unicode behavior.
- Treat target-client API documentation and FrameXML as authoritative. Retail
  and Classic examples are references, not proof of Forever compatibility.
- Save-ignore operations cover native equipped slots 1..19 other than 16/17/18.
  Ammo slot 0 is not individually operated on and is outside scope. Verify native
  ammo behavior in client; do not promise it from mocks.
- Prefer native WoW equipment sets with non-weapon slots ignored. If the client
  lacks the required support, report that limitation and agree on an alternative;
  do not silently substitute an AddOn-only set store.
- Keep version-dependent API calls behind a small, explicit boundary only where
  verified differences require it. Avoid a speculative multi-client framework.
- Respect protected actions, hardware-event requirements, and combat lockdown.
  Never bypass restrictions or promise combat swapping without verification.
  On the target client, WSF's ordinary UI callbacks cannot swap weapons in
  combat, while the secure native `/equipset` slash path (for example
  `/equipset [noequipped:shield] Shield-Set; DPS-Set`) can. Equip through WSF
  only out of combat; recommend native `/equipset` or player macros in combat.
  Do not claim the internal permission root cause is established. Do not add
  macro workarounds, secure-macro support, deferred queues, or frameworks.

## Clean coding

- Use Lua syntax and libraries supported by the verified game runtime.
- Prefer readable names, small focused functions, guard clauses, and explicit
  state transitions. Separate command parsing, equipment operations, and UI
  responsibilities without unnecessary layers.
- Use four spaces for indentation. Prefer local variables and functions; use
  the AddOn namespace for shared state. Expose globals only when WoW requires
  them, and prefix AddOn-owned globals with `WeaponSetsForever` or `WSF`.
- Centralize meaningful constants; avoid unexplained slot IDs and magic values.
- Comment sparingly: explain non-obvious intent, API constraints, or tradeoffs,
  not what an obvious statement does.
- Prefer native APIs and no runtime dependencies. Justify any new dependency.
- Use event-driven work. Avoid continuous polling, idle `OnUpdate` handlers,
  unnecessary bag scans, and premature micro-optimization.

## Safety and error reporting

- Validate commands, names, required APIs, and operation preconditions before
  mutating equipment or saved sets. Fail fast when invariants are broken.
- Treat invalid input, unknown sets, unavailable items, item locks, full bags,
  set limits, and combat restrictions as expected failures: stop and provide
  concise, actionable feedback prefixed with `WSF`.
- Distinguish expected failures from programming defects. Preserve useful
  diagnostics through WoW's error reporting; never swallow errors with blanket
  `pcall` handlers or replace the global error handler. A narrow protected save
  region may attempt shared-flag restoration before rethrowing programming defects.
  Never hide restoration errors.
- On an unsupported client, disable unsafe operations and report the missing
  capability once rather than generating repeated event errors.
- Do not report success until API results/events or verified state establish
  completion. Report partial equipment changes honestly; do not assume atomic
  swaps or attempt unverified rollback.
- Block saves in combat and when `PaperDollFrame.EquipmentManagerPane:IsVisible()`.
  UI checks at prompt open and acceptance; core must also check before mutation.
  Report: close the Equipment Manager pane before saving. Do not hide it for the user.
  Native synchronous set-change handlers can change shared save-ignore flags.
- Preserve Blizzard Equipment Manager's shared ignore-slot state if temporarily
  modifying it. Restore it on success and failure.
- Core checks `WSF.available` at PLAYER_LOGIN. UI must not rely on event
  handler order for its initial availability update. Guard C_Timer.After before
  use; a missing timer API disables core operations without a UI exception.
- `WSF.Save(name)` returns bool/error synchronously after verifying the saved
  configuration and does not print. UI owns its save feedback through WSF.Report.
- `WSF.GetWeaponSets()` returns a dense array of {id, name}, or nil/error.
- `WSF.Equip(id)` returns bool/error. `Equipment.PrepareEquip` must reject combat
  before calling `C_EquipmentSet.UseEquipmentSet`, with the exact error
  `WSF cannot equip from its UI in combat. Use native /equipset instead.`
  Out of combat, delegate to the native API. Retain weapon-only validation,
  missing-item, item-lock, casting, and completion checks. Respect native restrictions.
  Core owns all equip failure and completion feedback; UI adds none.
  Completion: a false EQUIPMENT_SWAP_FINISHED result fails at once. A true
  result succeeds once verified state confirms it: isEquipped is true, or every
  weapon slot holds the set's saved item (or is empty where the set saved
  empty). Client `debug_swap` traces show the true event fires before any item
  moves, with isEquipped false; within a second the weapons match and
  isEquipped is true, including for an all-empty set. This produced the earlier
  false failure messages. While a swap is pending, each PLAYER_EQUIPMENT_CHANGED
  re-checks verified state and confirms the swap; the single five-second
  fallback check decides otherwise. Neither is idle polling. At login, core
  also confirms every runtime file is from the same version and reports a
  mixed install once.
- WoW APIs can return no values rather than nil (GetInventoryItemID on an empty
  slot). Store results in a local before passing them to tostring or similar.
  Test mocks must return no values in those cases. The target client may not
  show Lua error popups, so diagnostics report errors in chat.
- Author-approved policy: saving an existing name overwrites that character's
  native set regardless of creator, without extra confirmation. Replace its
  saved configuration with a weapon-only snapshot after validation; saving must
  not mutate currently equipped gear.
- Preserve intentionally empty supported weapon slots; do not confuse an empty
  slot, ignored slot, unavailable item data, and an unsupported slot.
- Use native per-character sets with no SavedVariables for this scope.
  Do not add persisted metadata or an AddOn-only set store without agreement.
  Never commit player data, credentials, or upload tokens.

## UI policy

- Use custom dark-brown save and equip panels with gold borders and headings,
  warm text, and subtle separators. Use the exact heading `Weapon Sets Forever`.
  Do not use the singular `Weapon Set Forever`.
- Keep the author-approved icon-only Save and Equip buttons: 28x28, gold-bordered,
  anchored 6 pixels beneath `CharacterWristSlot` (Save) and `CharacterTrinket1Slot`
  (Equip), the last slots in each column, aligned to each column's outer edge
  (Save left, Equip right) so stat text beside the ranged slot stays visible.
  Tooltips open toward the paper doll: Save `ANCHOR_RIGHT`, Equip `ANCHOR_LEFT`,
  so neither covers the stats pane. They replaced centered text buttons that
  overlapped stat text drawn by other AddOns. Save shows the logo-derived Textures/SaveIcon.tga; Equip uses the
  built-in INV_Sword_04 icon. Add no other runtime assets or dependencies without
  agreement. Regenerate the Save icon with scripts/build_icon.py whenever the
  logo changes; tests require the committed TGA to match the build.
- Do not use StaticPopup dialogs for WSF. Leave Blizzard's native dialogs untouched.
- The save panel exposes `.editBox`, `.saveButton`, and `.cancelButton`.
  Validate the literal name before `WSF.Save`. Validation and save failures
  preserve input and focus. Save and Enter use the same acceptance path.
- Expose only the two prefixed panel globals needed by `UISpecialFrames` for
  Escape support. Keep other UI frames and controls local or on their parent.
- Parent hiding closes both panels. Combat entry hides only the save panel;
  the equip list remains open and can also open and be browsed in combat.
  Selecting a row in combat is blocked by core with one clear message and no
  native equip API call. Keep combat and manager-pane save guards unchanged.
- The equip tooltip must say UI equipping is out of combat only and recommend
  native `/equipset` or player macros for combat.
- UI changes require in-client checks for panel colors, heading, layout, combat
  UI, native action restrictions, and taint. Mocks do not prove these results.
- Keep the user guidance to re-save sets created by pre-release builds before
  combat use. Updating the AddOn does not rewrite sets, and native `/equipset`
  bypasses WSF validation.

## Testing and documentation

- `tests/run.lua` requires Lua 5.1. From the Git Bash repository root, run
  `.tools/luarocks-3.13.0-win32/win32/lua5.1/bin/lua5.1.exe tests/run.lua`.
  Use the bundled luac5.1.exe for syntax checks. Keep development tooling out of
  runtime packages. TESTING.md documents tooling provenance and test method.
- Release helpers/unit tests use Python 3 standard library only, not runtime
  dependencies. Run `python3 -m unittest discover -s tests -p 'test_*.py'`.
  Local Windows tooling is portable Python 3.13.7 under ignored
  .tools/python-3.13.7/, from the official python.org embeddable archive, without
  an installer/PATH change. Workflow linting uses actionlint. CI uses
  ubuntu-24.04 native python3 and apt lua5.1; never try to run local Windows
  binaries there.
- Local mocks, compilation, lint, and ZIP validation do not establish remote
  publication, approval-gate enforcement, or full client compatibility.
- Add focused tests alongside executable behavior, using minimal WoW API mocks
  for pure parsing and equipment-operation logic where appropriate.
- Cover quoted multi-word names, argument delimiters, malformed quoting, extra
  arguments, invalid input, overwrite behavior regardless of creator, missing APIs,
  empty slots, two-handed/off-hand transitions, duplicate items, unavailable or
  locked items, full bags, set limits, shared-state restoration, and failed or
  partial swaps. Keep regressions for combat equip rejection before the native
  API call, one core message, combat list browsing/visibility, and tooltip guidance.
- In-client checks are required for UI placement, native set persistence,
  protected actions, combat restrictions, taint, and actual equipment changes.
- Verify UI and slash saves use the same WSF.Save behavior. Verify UI equip and
  native /equipset leave non-weapon gear unchanged without assuming identical
  combat permissions or validation paths. Check persistence after `/reload` and
  relogging, and verify identically named sets remain isolated between characters.
- Runtime installation uses WeaponSetsForever.toc plus Commands.lua,
  Equipment.lua, Core.lua, and UI.lua in Interface/AddOns/WeaponSetsForever/.
  TOC Interface is 16001; load Commands, Equipment, Core, then UI.
- Keep README usage and compatibility claims aligned with implementation.
  Distinguish automated tests from in-client checks.
- Run available focused checks and report actual results. Never invent tooling,
  test commands, passing results, or compatibility claims.

## Releases and collaboration

- Read docs/RELEASE_PLAN.md before packaging or changing release automation. It
  describes the process and setup; it is not authorization to publish. Validate
  the exact ZIP allowlist and service version metadata before any upload.
- Make focused changes; preserve user work and avoid unrelated refactors.
- Do not create branches, commits, tags, uploads, or public releases unless asked.
  A request to update documentation does not authorize any of these.
- Use authorized tagged GitHub Releases containing installable ZIP assets with a
  top-level `WeaponSetsForever/` folder and correctly named TOC. GitHub source archives
  are not a substitute for an installable release package.
- Name the ZIP `WeaponSetsForever-<version>-forever.zip` and attach the
  builder's BigWigs-format `release.json` (flavor `forever`). WowUp 2.24.0
  identifies Forever assets by that metadata or by the `-forever.zip` suffix;
  keep both unless WowUp's verified rules change.
- Package only WeaponSetsForever.toc, Commands.lua, Equipment.lua, Core.lua,
  UI.lua, LICENSE, and Textures/SaveIcon.tga under the top-level
  WeaponSetsForever/ folder. The builder requires the TGA to be uncompressed,
  32-bit, and square with power-of-two sides. Exclude
  .tools/, tests/, docs/, artwork/, agent guidance, and other development-only files.
  Do not load LICENSE through the TOC.
- Use artwork/ for original logo sources and distribution images. Do not replace
  the built-in runtime icon with publishing artwork without a separate request.
- Advertise only tested client versions and verify Forever support in each
  distribution service. Keep release notes clear about beta-only support,
  out-of-combat WSF UI equips, native combat macros, and re-saving early sets.
- CI tests/builds main pushes, PRs, and manual runs with contents: read.
  v* tag builds require the builder's version to match the TOC and the commit to
  be an ancestor of origin/main. Checkout/upload/download Actions are full-SHA
  pinned and verified against the GitHub API; review any future pin changes.
- Publishing requires repository variables ENABLE_GITHUB_RELEASES='true' and,
  for CurseForge, ENABLE_CURSEFORGE_UPLOADS='true'. Both jobs use the
  author-created environment `release` (jbedworth as required reviewer). The
  workflow's environment name must match it exactly: GitHub silently creates an
  unprotected environment for any unknown name. The author must verify the gate
  works before enabling either flag; an environment declaration alone is not gating.
  CurseForge also requires the GitHub publisher to succeed.
- GitHub publishing uses contents: write, built-in GITHUB_TOKEN, and hosted gh;
  local gh authentication is not needed for CI. CurseForge requires positive
  CURSEFORGE_PROJECT_ID and CURSEFORGE_GAME_VERSION_ID repository variables plus
  release-environment secret CF_API_TOKEN. The uploader verifies server version
  1.60.1/type 88568, refuses redirects, never retries POST, and retains receipts.
  The workflow permits CurseForge only on the first run attempt. Do not blindly
  rerun, replace existing releases, or create conflicting uploads.
- Every release needs a `## <version>` section in CHANGELOG.md with
  player-facing changes. The builder puts it at the top of release-notes.md
  (the GitHub release notes and CurseForge changelog) and fails without it.
  CHANGELOG.md is a release record and never enters the package.
- scripts/build_release.py creates deterministic ZIP bytes for the same inputs/
  toolchain plus checksum, manifest, and notes outside the ZIP. Optional
  --source-commit records a real full SHA (GITHUB_SHA in CI), not proof derived
  from ZIP contents. scripts/verify_release.py checks the artifact, manifest,
  checksum, source commit, and remote tag, peeling annotated or lightweight tags.
  CI rechecks before GitHub draft creation, before making it public, and before
  CurseForge upload. Require immutable release tags: restrict creation to
  maintainers and restrict updates/deletions. These checks are not atomic with
  publication and cannot eliminate a tag-movement race.
- Store publisher tokens only in GitHub Actions secrets; keep build jobs secret-
  free and use least-privilege permissions. Follow exact setup/recovery steps in
  docs/RELEASE_PLAN.md; retain artifacts and inspect remote results before retries.
- Preserve the MIT copyright notice and include LICENSE in distributed copies
  and installable release packages.
- Commit messages, when requested: imperative, capitalized subject, ideally at
  most 50 characters, no ending punctuation; add a short 72-column-wrapped body
  only when useful. A commit-message-only request gets only the message.

## References

- [WoW AddOn API](https://warcraft.wiki.gg/wiki/World_of_Warcraft_API)
- [Equipment-set API](https://warcraft.wiki.gg/wiki/World_of_Warcraft_API#EquipmentSet)
- [Blizzard UI source mirror](https://github.com/Gethe/wow-ui-source)
- [BigWigs AddOn packager](https://github.com/BigWigsMods/packager)
- [WoWUp Hub developer guidance](https://wowup.io/guide/wowup/hub)
