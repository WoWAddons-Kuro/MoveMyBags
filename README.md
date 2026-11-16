# MoveMyBags.Kuro

**Project:** https://github.com/WoWAddons-Kuro/MoveMyBags

A fork of [MoveMyBags](https://www.curseforge.com/wow/addons/movemybags) by
steveweed79, maintained by Kuro for WoW Forever.

Make World of Warcraft's bag windows draggable — the separate ones and the
combined one. Nothing to configure, no layout engine of its own, and a short
options page for the few things you might want to turn off.

One addon for every current flavour, verified against each one's UI source:

| Flavour | Interface | Container code |
|---|---|---|
| Retail | `120105` (12.1.5) | Mainline |
| Classic Era | `11509` (1.15.9) | Classic, shared |
| Anniversary realms | `20506` (2.5.6) | Classic, shared |
| Mists of Pandaria Classic | `50504` (5.5.4) | Classic, shared |
| Titan (Wrath Classic) | `38002` (3.80.2) | Classic, shared |
| WoW Forever | `16001` (1.60.1) | Mainline, with a small override |

The Lua is the same everywhere; where a client lacks something (the combined
window, the addon compartment, Edit Mode) that feature stands down and
`/mmbk status` says so. On Classic the title bar is part of the window,
so a plain drag there moves it; Shift is only needed on the bag icon.

## Usage

| Interaction | Result |
|---|---|
| Left-drag a bag window by its frame (not an item slot) | The window follows the cursor, connecting to the others as it goes; the position persists |
| **Shift**-drag a bag window's title bar or bag icon | The same. Without Shift, a press there opens Blizzard's bag menu, as it always has |
| Click a bag window's title bar, bag icon or frame | It comes to the front; the others go one layer back |
| Shift-right-click a bag window, its title bar or its icon | That window returns to Blizzard's default slot |
| `/mmbk reset` (or `/mmb reset`) | Every window returns to Blizzard's layout. At the bank or a merchant, that place forgets its own arrangement and follows your usual one again |
| `/mmbk reset all` | The same, in every place at once |
| `/mmbk save` / `load` / `delete <name>`, `/mmbk layouts` | Keep whole arrangements by name and switch between them |
| `/mmbk lock` / `unlock` | Stops windows being dragged; resets still work |
| `/mmbk config` | Opens the options page |
| `/mmbk status` | What the addon is doing: hooks, saved positions, every window on screen. Paste it into a bug report |
| Never moved a window | Blizzard's default behaviour, completely unmodified |

Drag a window and it moves. The rest of the column closes up on the drop, and
re-opens the moment you put the window back. There is nothing to turn on.

## Options

Everything is on by default and works the way the rest of this page describes.
The options page (Escape → Options → AddOns → MoveMyBags.Kuro, or
`/mmbk config`) has eight switches and a button:

| Option | Default | Off |
|---|---|---|
| Lock bag windows | off | — |
| Connect windows while dragging | on | A dragged window goes exactly where the cursor puts it, overlaps and all |
| Close the hole a moved bag leaves | on | Blizzard's column is left exactly as it draws it |
| Keep the window you are using in front | on | Windows are drawn in whatever order the client has them |
| Separate arrangements at the bank and at a merchant | on | One arrangement is used everywhere |
| Show the bag windows in Edit Mode | on | Edit Mode leaves the bags alone |
| Follow Edit Mode layouts | off | — (on: an Edit Mode layout loads the MoveMyBags.Kuro layout of the same name) |
| This character keeps its own arrangement | off | — (on: this character's bags are arranged on their own, starting from a copy of the account's) |
| Reset positions | | Puts every window back, in every place and both bag modes |

Two other ways in:

- **Keybinding.** Options → Keybindings → MoveMyBags.Kuro → *Lock or unlock bag
  windows*. Unbound until you bind it.
- **Addon compartment.** MoveMyBags.Kuro is in the minimap's addon menu. Left-click
  opens the options; right-click locks or unlocks.

Settings are account-wide, except *This character keeps its own arrangement*,
which is per character by definition.

Windows connect as you drag them. Bring one alongside another and it clicks
flush against it; try to drag it *over* one and it slides around instead. Bag
windows are opaque, so an overlap hides whatever is underneath — they behave
like solid objects rather than sheets of paper. Letting go changes nothing:
the window is already where you can see it is.

Only the window you are actually holding ever moves.

Each window sits on its own layer, and the one you are working with is in
front: pick a window up, or click its title bar, bag icon or frame, and it comes
to the top, pushing the others back one. Windows only ever meet in the places
settling cannot help with — a window in mid-drag, a bag that grew into its
neighbour, a screen with nowhere clear left — and when they do, the one you just
touched is the one you can see. Clicking changes the layer and nothing else; the
window does not move. Clicking an *item* still just handles the item.

Positions are saved account-wide (or per character, if you ask for that), keyed
by **bag ID** rather than window slot —
move your ore bag and the ore bag remembers, no matter which slot it sits in or
how many bags are open. The combined window gets its own key, so the two modes
never overwrite each other.

## The bank and the merchant

Blizzard lays the bags out differently beside the bank, and both the bank and
a merchant open every bag you have. So each of those places keeps an
arrangement of its own. Until you move a bag there, it follows your usual
arrangement; the first time you do, that place takes a copy and goes its own
way. From then on, moving a bag in the field does not move it at the bank, and
the other way round. Shift-right-click at the bank puts that bag on Blizzard's
bank slot without touching where it sits in the field, and `/mmbk reset`
at the bank makes the bank follow your usual arrangement again. Turn
*Separate arrangements at the bank and at a merchant* off in the options to use
one arrangement everywhere.

## Edit Mode

Open Edit Mode (Escape → Edit Mode) and each bag you have is there as a
labelled placeholder, at the bag's position, drawn the size its window was
last seen. Drag it like any other part of the UI; a bag window that happens
to be open follows it live. Its dialog has *Put back*, which clears the bag's
position, and the usual *Reset Position*. Edit Mode arranges the field: the
bank and merchant arrangements are left alone.

A bag the addon has never seen — never opened this session and never moved —
has no placeholder, because there is nothing to show for it. Open your bags
once and they all appear.

Tick *Follow Edit Mode layouts* and an Edit Mode layout becoming active,
including at login, loads a MoveMyBags.Kuro layout with the same name, if you have
saved one. Off by default: it resets the bags to that snapshot every time,
which is the feature, and a surprise to anyone who did not ask for it.

The bags go through [LibEditMode](https://github.com/p3lim-wow/LibEditMode),
which ships inside the addon. Blizzard offers no way for an addon to add a
frame to Edit Mode itself, and doing it by hand taints the whole Edit Mode UI.

## Layouts and characters

`/mmbk save Raid night` keeps the whole arrangement — field, bank and
merchant together — under a name; `/mmbk load Raid night` brings it back,
`/mmbk layouts` lists what you have, and `/mmbk delete` removes
one. A loaded layout is a copy: change it and save again to keep the change.

Arrangements are account-wide. Tick *This character keeps its own arrangement*
in the options and this character starts from a copy of the account's and is
then arranged on its own. Untick it and the account's arrangement comes back;
the character's is kept for next time.

A bag window grows when you put a bigger bag in that slot. One parked in the
lower half of the screen grows upward, as Blizzard's own do; one parked in the
upper half keeps its top edge and grows downward, so it never gets pushed off
the top and clamped back onto whatever you placed it beside.

## Things to know

- **Item slots still drag items.** Grab the window by its frame edge or the
  gaps between slots. Left-dragging an item picks up the item, as it always did.
- **The title bar is Blizzard's menu button.** Pressing it opens the bag's
  menu — filters, clean-up, the combined-bags toggle — before any drag can
  start, so a plain drag from the title bar does what it always did and opens
  the menu. Hold **Shift** to drag from the title bar or the bag icon instead;
  Blizzard's handler ignores a press with Shift held, so the menu stays shut.
- **If something goes wrong, the addon gets out of the way.** An error inside
  the addon is reported once, and after a few in one session it stops touching
  the windows until you `/reload`. Your saved positions are kept.
  `/mmbk status` shows what happened.
- **Bags shrink as more open.** That is Blizzard's behaviour and is left alone.
  A moved bag stays on the same screen spot at whatever size Blizzard gives it.
- **Bank open.** When the bank window is open, Blizzard shrinks and shifts the
  bag column to clear it. A bag you moved stays where you put it, which can be
  under the bank window — so move it, and the bank remembers that spot for
  next time without changing where the bag sits in the field.
- **Windows connect while you drag, and only while you drag.** Two windows
  parked flush can still come to overlap later if one of them grows — put a
  bigger bag in that slot and the window gets taller. Drag either one and they
  settle again; the addon never rearranges a window you already placed.
- **A small nudge is still a nudge.** Lift a bag and put it straight back down
  and nothing happens — snapping does not engage until the drag has actually
  carried the window somewhere.
- **No room, no move.** If nothing on screen is clear — more bags open than
  fit, or a window wider than the screen — the window stays where you have it
  rather than being shoved somewhere arbitrary.
- **UI scale changes.** Positions are kept in UI units, so changing the UI scale
  shifts moved windows on screen. They are pulled back into view if that
  strands one off the edge; drag them where you want them again.

Windows also get out of the way on their own if a future patch makes bags
natively movable or puts them in Edit Mode. See [DESIGN.md](DESIGN.md) for how
the addon works and why it is built the way it is.

## Installing from source

Copy or symlink this repository into
`World of Warcraft/_retail_/Interface/AddOns/` as a folder named **MoveMyBags.Kuro**.
The folder name and the `.toc` filename must match exactly or the client will
not list the addon.

## Translating

MoveMyBags.Kuro is translated on CurseForge: open the project's **Localization**
page, pick your language and translate the strings there. Every release picks
up whatever has been translated, and a string nobody has translated yet shows
in English, so a partial translation is still useful.

German, French, Spanish, Brazilian Portuguese, Russian, Korean and both
Chinese scripts start from machine-assisted drafts. They are the strings most
worth checking: anything that reads oddly to a native speaker is a fix worth
making. Keep the `%s` and `%d` markers in the same order as the English, and
leave `/mmbk` commands in English, since they are typed as they are.

Behind that, every string a player sees is listed in `Locales.lua`, keyed by
its English text. `.github/workflows/localization.yml` sends the list to
CurseForge whenever it changes, the drafts live in `docs/localization/`, and
`tools/localization.lua check` checks them.

`## Version` carries the `v1.6.3` token, which the
[BigWigs packager](https://github.com/BigWigsMods/packager) substitutes at
release time; a direct copy of the source tree shows the literal token in the
addon list, which is cosmetic only.

## Development

```sh
make test       # headless suite: lua5.1 tests/run.lua
make lint       # luacheck .
make coverage   # the suite under LuaCov, with a floor
make package    # a packager dry run, then a check of what it packed
```

CI runs all four on every pull request. Taint behaviour cannot be tested
outside the client, so [TESTING.md](TESTING.md) carries the in-game plan.
[DESIGN.md](DESIGN.md) covers the design, the module layout, the release
process, and the weekly check against Blizzard's UI source.

## Licence

MIT — see [LICENSE](LICENSE).
