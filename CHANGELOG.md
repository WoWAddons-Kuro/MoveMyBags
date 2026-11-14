# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.6.3] - 2026-11-13

### Changed

- Checked against WoW Forever's launch build, 1.60.1 (70938). The addon needs
  no change for it and its interface number, 16001, is still current. Every
  check of Blizzard's bag code passes there, and so do the new ones below.
- Forever's interface number is now kept current by the weekly TOC updater,
  which gained Blizzard's live Forever product at launch. It used to be kept
  by hand. If a flavour's number cannot be fetched, the workflow now also
  copes with the updater leaving an empty entry in the line, and puts the
  old number back.

### Added

- The weekly check of Blizzard's code now makes sure Forever really runs
  the Retail files it checks for Forever. Before, a Forever patch that
  replaced the bag-layout function or the bank's show handler with its own
  version would have gone unnoticed. Forever's bag code, bank and addon
  compartment are all checked.
- An in-game test plan for Forever in `TESTING.md`, covering the addon
  compartment, Forever's bank, combined bags with a gamepad, and Edit Mode.

## [1.6.2] - 2026-10-15

### Fixed

- Bags that turn greyed out and ignore clicks. Blizzard rebuilds a bag
  window's item buttons each time it opens the window, and a new button can
  end up drawn underneath its own window: greyed out by the window's
  background, with every click landing on the window instead. It happens
  with no addons loaded, but the addon's layering kept the windows high
  enough to make it common. Each bag window's items are now put back just
  above the window whenever the bags open or a window is brought forward,
  in combat too. The weekly check of Blizzard's bag code now watches the
  facts this relies on.

## [1.6.1] - 2026-10-13

### Changed

- Retail interface 120105, for 12.1.5. The weekly check of every assumption
  the addon makes about Blizzard's bag code passes on 12.1.5 and on every
  Classic flavour, so nothing else changes.

### Fixed

- The weekly interface updater no longer drops Titan from the TOC. It has
  stopped reporting a number for Titan, and its clean-up step only put back
  WoW Forever's; it now puts back any flavour's number the updater leaves
  out.

## [1.6.0] - 2026-10-13

### Added

- Translations, through CurseForge's localization page. Each release now
  builds in whatever has been translated there for German, French, Spanish
  (Spain and Mexico), Italian, Brazilian Portuguese, Russian, Korean and
  Simplified and Traditional Chinese; anything untranslated stays in English.
  All of these but Italian start from drafts that native speakers are asked
  to check. A workflow keeps CurseForge's list of strings in step with
  `Locales.lua`, and a new test suite checks that every string the addon
  shows is on that list and that the drafts keep their `%s` markers and
  commands intact.
- Until CurseForge's localization page accepts the project's API token, the
  drafts ship in its place: the release and alpha builds bake them into
  `Locales.lua`, and setting the repository variable `CF_LOCALIZATION` to
  `true` switches the builds over to CurseForge's translations.

### Removed

- "Bag windows" from the list of strings to translate. It was listed when
  the list was written and nothing has ever shown it.

## [1.5.2] - 2026-10-12

### Added

- Titan (Wrath of the Lich King Classic, 3.80), from the same files. Titan
  runs the shared Classic container code with a quest-item override of its
  own, so the addon's Classic path covers it unchanged. The contract check
  runs against Titan's own source branch.

### Fixed

- The weekly interface-version updater rewrites the whole `## Interface`
  line from the flavours it knows, which would have dropped Forever's number
  on its next run. The workflow now puts the hand-kept number back after the
  updater, and the contract check keeps saying whether it is current.

## [1.5.1] - 2026-10-12

### Added

- WoW Forever, from the same files. Forever runs Retail's container code
  with a two-function cosmetic override, so the addon's Retail path covers it
  unchanged, Edit Mode and the addon compartment included. The contract check
  runs against Forever's own source branch and also checks that the TOC's
  Forever number is current, since the TOC updater has no product for it yet.
  1.5.0's notes said Forever had a container implementation of its own; that
  was a misreading of a seventeen-line file.

## [1.5.0] - 2026-10-08

### Fixed

- Dragging a bag window by its title bar never worked, and the documentation
  said it did. The title bar is a button of Blizzard's own whose press opens
  the bag's menu — filters, clean-up, the combined-bags toggle — so the drag
  never reached the window. The window body still drags with no modifier, and
  the title bar and bag icon now drag with **Shift** held: Blizzard's handler
  ignores a press with Shift down, so the menu stays shut. Shift-right-click
  on the title bar or icon now resets the bag as well; it used to be swallowed
  by the same button.
- The layer order is now kept per bag rather than per window. Bag windows are
  pooled — the client hands a bag the first free frame — so opening the bags
  in a different sequence put a different bag in each frame, and the order the
  player had arranged was shuffled with it. Saved positions were always keyed
  by bag and were never affected.

### Added

- Classic Era, the Anniversary realms and Mists of Pandaria Classic, from the
  same files. Classic's container code shares one implementation across the
  three, and everything the addon is built on holds there: the global anchor
  pass, the bag-to-bag chain, the rescaling, the pooled frames. Two things
  differ and are read from the client rather than switched on by flavour:
  Classic lays the bags out in the order they were opened, which the
  compaction replay now follows, and its free-height accounting subtracts a
  per-bag constant that is a global there, which the replay now reads. The
  title bar is part of the window on Classic, so a plain drag there works
  without Shift. The contract check runs once per flavour against each
  flavour's own source branch.
- Every push to `main` is packaged as an alpha, uploaded once the
  `ALPHA_UPLOADS` repository variable is set.
- The bag windows are in Edit Mode. Each bag the addon has seen appears as a
  labelled placeholder at its position, the size its window was last seen,
  and drags like any other part of the UI; an open bag window follows it
  live. Its dialog has *Put back* and the usual *Reset Position*. Edit Mode
  arranges the field, not the bank. This goes through LibEditMode, which
  ships inside the addon, because Blizzard offers no way for an addon to add
  a frame to Edit Mode itself. One checkbox turns it off. A second, off by
  default, loads a MoveMyBags layout whenever an Edit Mode layout of the same
  name becomes active.
- The bank and a merchant each keep an arrangement of their own. Blizzard
  lays the column out differently beside the bank, and both the bank and a
  merchant open every bag, so a place like that follows your usual
  arrangement until you move a bag there, then takes a copy and goes its own
  way. Shift-right-click there puts a bag on Blizzard's slot for that place
  only; `/movemybags reset` there forgets the place's arrangement, and
  `/movemybags reset all` forgets every place. One checkbox turns this off.
- Named layouts: `/movemybags save <name>`, `load`, `delete` and `layouts`
  keep whole arrangements — every place together — and switch between them.
- A per-character arrangement, as a checkbox. It starts from a copy of the
  account-wide one and is kept when switched off again.
- The saved variables are now version 2: positions per place, the layouts,
  and a per-character file. A version 1 database is migrated in place and
  nothing in it changes.
- An options page, under Options → AddOns → MoveMyBags or `/movemybags
  config`. Six switches and a button: lock the windows, connect windows while
  dragging, close the hole a moved bag leaves, keep the window you are using
  in front, separate arrangements at the bank and a merchant, this character
  keeps its own arrangement, and reset every position. The defaults are
  exactly what the addon did before the page existed. Built on
  Blizzard's Settings API, writing straight into the saved variables; a client
  without that API gets the addon without the page.
- A keybinding, *Lock or unlock bag windows*, under Keybindings → MoveMyBags.
  Unbound until you bind it.
- An entry in the minimap's addon compartment. Left-click opens the options,
  right-click locks or unlocks, and the tooltip shows the lock state.
- A locale table. Every string a player sees is in `Locales.lua`, keyed by its
  English text with English as the fallback, ready for translations.
- `/movemybags status` prints what the addon is doing: the client build, the
  addon version, whether the layout hook is live, whether compacting is
  measured or standing down and why, the layer and lock state, any errors,
  every saved position and every window on screen with the bag it shows, its
  frame level and its position. It reads state only. Paste it into a bug report.
- An error inside the addon no longer repeats every frame. Each one goes to
  the error handler (so BugSack captures it with a stack) and is announced in
  chat once; after three in a session the addon stands down and leaves the
  windows to Blizzard until a reload. Saved positions are untouched.
- The test stub now models the two client behaviours that hid the fixes above
  for four releases: the title bar's menu-on-press handler, and the frame
  pool, which assigns bags to frames by open order and sizes the window for
  the bag it is about to show. `tools/check-api-contract.sh` asserts both
  against Blizzard's source, plus the Shift bypass in the dropdown's press
  handler that the title-bar drag depends on.

## [1.4.0] - 2026-09-20

### Added

- Bag windows are now layered, one per window, with the one you are working
  with in front. Picking a window up — or clicking it — brings it to the top
  and pushes the others back one layer each.

  Blizzard gives the separate bag windows almost no layering: they are not
  `toplevel`, so clicking one does not bring it forward, and the only raise is
  the one that happens as a window is generated. Two windows that met were
  drawn in whatever order their frame levels happened to be in, so the window
  you were dragging could pass *underneath* the ones it crossed, and a window
  clicked while half covered stayed half covered.

  Layers are 520 levels apart, which is wide enough that one window's title bar
  and close button — Blizzard declares them 510 levels above the window itself
  — cannot draw over the window in front of it. The band is hung from the
  lowest level the windows already sit at and rises from there, so bringing one
  window forward never pushes another behind something it was drawn over, and
  it is capped well below the client's own limit so it cannot creep up the
  strata over a session of opening and closing your bags. The order it starts
  from is the one you were already looking at.

  Clicking the title bar or the bag icon raises the window too — both are
  buttons of Blizzard's own, so the click never reaches the window itself. A
  window with nothing to be layered against, including the combined bag window,
  is left exactly as the client has it.

  Nothing is layered until you have moved a window or clicked one: until then
  the bags are in Blizzard's column, where nothing overlaps.

## [1.3.0] - 2026-09-17

### Changed

- Bag windows now connect while you are dragging them, not once you let go. A
  window clicks flush against a neighbour as it comes alongside, and it will not
  cross one at all — it slides around instead. Dropping it is then just letting
  go of something already in place; nothing moves on release.

  1.2.0 only settled the window after the drop, so a drag still slid straight
  through everything on the way and then jumped somewhere else at the end. That
  is because a drag handed to the client belongs to the client for its whole
  duration, and anything an addon does to the window is undone frame by frame.
  The addon now moves the window itself, following the cursor, which is what
  gives snapping and clearing somewhere to run while you can still see them. It
  costs one frame handler for the length of a drag and nothing the rest of the
  time.
- Picking a bag up out of the column no longer twitches. Blizzard stacks the
  column eight pixels apart, which is inside the snap distance, so a window
  would otherwise jump flush against its neighbours the instant it was lifted.
  Nothing settles it until the drag has actually carried it somewhere.
- Dragging keeps a window on screen by itself rather than relying on
  `SetClampedToScreen`, which only ever constrained a drag the client was
  running.

### Fixed

- Dropping a moved bag back on its own slot resets it again. The window can no
  longer come to rest on that slot — the column has closed up and another bag is
  sitting there, so settling moves it aside — which silently broke the gesture.
  It is now read from where the cursor asked for the window to go rather than
  from where the window ended up.

## [1.2.0] - 2026-09-17

### Added

- A window dropped squarely on top of another now moves to the nearest free
  side of it instead of burying it. Snapping only ever reached within twelve
  pixels of an edge, so a window let go over the middle of another just sat
  there hiding it — bag windows are opaque. The search offers the four flush
  positions around each window in the way, takes the one nearest the drop, and
  never offers one that would put a window out of reach: if nothing on screen
  is clear, the drop stands exactly where you put it. Only the window you just
  let go of ever moves.

### Fixed

- Snapping no longer lines a dropped window's left edge up with a window it is
  face to face with, which put it squarely on top of that window rather than
  beside it. An edge pair is only offered when it means something: contact
  (this edge to that opposite edge) between windows that face each other,
  a shared gridline between windows that are stacked or side by side.
- Snapping now aligns against where the column is *going* to be rather than
  where it was while the mouse button was still down. The drop also closes the
  hole the window came out of, so the column re-stacks in the same pass;
  aligning against the old positions put every drop onto the column a slot out.
  Both rules now run in that pass, and a drop whose pass is abandoned is
  forgotten rather than being settled against some later layout.

## [1.1.2] - 2026-09-15

### Fixed

- A bag window held mid-drag is now left alone by a layout pass that fires
  while you are holding it — clicking a vendor or the bank with a bag in hand
  opens the bags again. The window used to be snapshotted wherever the cursor
  happened to be, which recorded the cursor as Blizzard's own slot (so
  shift-right-click and `/mmb reset` put the bag back to a spot Blizzard never
  chose) and re-anchored the window out from under the pointer.
- A flush that gives up waiting for a bag to acquire a rect no longer leaves
  the next one believing it follows a Blizzard layout pass. The next drag would
  otherwise have its own drop point recorded as Blizzard's slot, quietly
  breaking reset for that bag.
- Compacting no longer stands down for the rest of the session on a single
  layout it cannot model. The reading is validated on every layout pass, so it
  is now un-stood-down on any pass that reproduces Blizzard's output again. The
  explanation is still printed only once per session.
- A UI scale or resolution change now drops the measured column geometry
  instead of re-stacking from it. The spacing and free height are measured in
  UIParent units at a particular scale, so re-flowing from them after a change
  misplaced the column; it re-opens to Blizzard's own slots until the next
  layout pass re-measures.
- The store description and other repository-only material under `docs/` is no
  longer copied into the packaged addon. `.pkgmeta`'s ignore list is opt-out and
  the directory was not on it, so the CurseForge copy would have shipped inside
  the addon folder.

## [1.1.1] - 2026-09-15

### Added

- Dropping a window near another window's edge, or the screen's, now lands it
  exactly flush instead of overlapping by however much the drop was off. Bag
  windows are opaque, so even a small overlap made the one underneath
  unreadable. Each axis snaps independently, only windows you are actually
  beside are considered, and nothing already parked is moved.

## [1.1.0] - 2026-09-14

### Added

- `/movemybags lock` (and `unlock`) stops bag windows being dragged. Saved
  positions still apply and both resets still work; only the drag is off.

### Fixed

- After the column had closed up around a moved bag, an accidental nudge on
  one of the re-stacked bags was stored as a real move, and that bag then
  stayed stuck in the compacted spot when the column re-opened. A bag that was
  never moved and lands where it started is now left alone, wherever that was.
- Bag windows are no longer clamped to the screen until the player actually
  drags one. `ContainerFrameTemplate` has no `clampedToScreen`, and clamping
  changes how Blizzard's own chain lays out near the edge, so applying it on
  attach touched a layout the addon promises to leave alone.
- If `UpdateContainerFrameAnchors` is not yet defined when the addon file runs,
  the hook is retried at `PLAYER_LOGIN` instead of leaving compacting off for
  the whole session.
- The weekly API-contract workflow adds its report to the open issue rather
  than opening a new one every week the check fails.

### Changed

- The README is now the player-facing page; the engineering notes moved to
  `DESIGN.md`.

## [1.0.3] - 2026-09-13

### Fixed

- A bag that is shown but never acquires a rect — another addon clearing its
  points, a reparent gone wrong — no longer leaves an `OnUpdate` running every
  frame for the rest of the session. The retry now gives up after a second and
  waits for the next bag open, drag or reset.

## [1.0.2] - 2026-09-13

First published release. 1.0.0 and 1.0.1 were both tagged but never published:
the release workflow passed the upload tokens under environment variable names
that the pinned version of the packager does not read, so it built the addon
and uploaded nothing while reporting success. The addon code is identical
across all three; only the release pipeline changed.

Verified against Blizzard's 12.1.0 (build 69587) UI source, and covered by a
headless test suite, but **not yet exercised in a live client** — in particular
the two checks that only the game can answer: that item clicks in combat are
never blocked, and that nothing from this addon appears in `Logs/taint.log`.
See `TESTING.md` if you want to run those before trusting it in a raid.

### Added

- Draggable bag windows, separate and combined, with positions persisted
  account-wide and keyed by bag ID (the combined window gets its own key, so the
  two modes never overwrite each other).
- Shift-right-click a window to return it to Blizzard's default slot, and
  `/movemybags` (`/mmb`) with a `reset` argument that clears all positions.
  Resets replay the position recorded from Blizzard's own last layout pass, so
  no Blizzard layout code ever runs on the addon's tainted path.
- Positions stored in UIParent units and converted on both read and write, so
  they survive `UpdateContainerFrameAnchors` rescaling the bags, plus clamping
  on restore for resolution and UI-scale changes.
- Enumeration via `ContainerFrameContainer.ContainerFrames`, with a
  `_G["ContainerFrame"..i]` fallback and per-window `OnShow` hooks, so the addon
  survives reparenting and `UpdateContainerFrameAnchors` ceasing to be a global.
- Stand-down detection: a bag window that gains an Edit Mode registration, a
  native `OnDragStart`, or the `ScriptBindings` forbidden aspect is left to
  Blizzard. It is still re-anchored so it cannot trail a bag you did move, but
  it never receives a saved position, including a stale one.
- A drag that lands within two pixels of Blizzard's own slot is treated as an
  accidental nudge and clears the saved position instead of storing it.
- Positions record the window's unscaled height, so a bag parked in the upper
  half of the screen keeps its top edge when the bag is upgraded (or when the
  same bag ID is a larger bag on another character) instead of growing off the
  top and being clamped back down. Bags parked low keep their bottom edge and
  grow upward, as Blizzard's own do.
- The column closes up when a bag is dragged out of it, and re-opens when the
  bag is put back — both on the drop, with no reopen or reload and nothing to
  turn on. The column origins and spacing are measured from Blizzard's own
  output rather than reimplementing its layout (two of the constants involved
  are locals and unreachable from an addon), and the measurement is kept so a
  drop can re-flow immediately. It validates itself against Blizzard's output on
  every layout pass and stands down rather than misplacing bags if the two
  disagree, or while a stood-down window is open.
- Luacheck linting, a scheduled TOC interface-version bump, a tag-driven release
  workflow built on the BigWigs packager, and a headless test suite covering the
  layout algorithm against a stand-in for the client.
- `tools/check-api-contract.sh` plus a weekly workflow, asserting against
  Blizzard's live UI source that the facts the addon is built on still hold and
  opening an issue when one stops. Each check names the design decision it
  invalidates.

### Notes

Verified against Blizzard's 12.1.0 (build 69587) UI source. Two assumptions from
the original project brief did not survive that check and were corrected:
`ContainerFrameCombinedBags` is *not* natively draggable (it is `movable="true"`
but has no drag handler), and `SetPoint` offsets are interpreted in the anchored
frame's own units, which the brief's reference `Place` did not account for.
