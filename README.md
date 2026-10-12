# Buffeteria

**All-you-can-buff.** Raid buff coordination for every class, not just paladins.

Targets **World of Warcraft: Forever** (interface `16001`, client `1.60.1`).

Buffeteria works out who casts what, and a one-click tracker serves it. Players can
choose their own buffs, while paladins can manage class blessings for the whole group,
including players who don't have Buffeteria installed. No PallyPower addon is required.

## How it works

- **You order, the kitchen cooks.** Each player ranks the paladin blessings they want
  (drag to reorder) and lights up the buffs they care about (Fortitude, Spirit, Shadow
  Protection, Mark of the Wild, Arcane Intellect). In `/buff`, these appear as
  talent-style trees: Blessings (each ranked blessing names the paladin serving it),
  Buffs (each buff names its caster), and Tanks (buffs wanted
  while tanking: Righteous Fury for paladins and Thorns from a druid).
- **Smart assignments.** With one paladin you get your #1 blessing, with two your #1 and
  #2, and so on. Greater Blessings cover a whole class, so each class gets what most of
  its players ranked highest. Priests, druids and mages split the raid groups.
- **No Salvation on the tank.** Drag a blessing below the line and you'll get a
  different personal blessing from that paladin instead.
- **No raid leader needed.** Every copy of Buffeteria computes the same answer from the
  same preferences. Players without the add-on get sensible class defaults.

New installs start from a class default ranking: warriors and rogues want Might
first; mages, warlocks, priests, druids, paladins, and shamans want Wisdom first;
hunters want Kings first (Might doesn't raise ranged attack power). Kings and
Salvation follow for everyone. Casters don't want Might, and warriors and rogues
don't want Wisdom. Players without the add-on are planned from the same defaults,
and so are classes Auto and **Auto-fill** cover on the Paladins tab. If your saved
ranking still matches the old Kings-first default, it moves to the new one; a
ranking you reordered is kept.

In **My preferences > Tanks**, **Role: Auto** follows your assigned Tank role or
raid main-tank assignment. Click Role to cycle through **Tank**, **Not tank**, and
**Auto** when you need an override, including solo play or groups without assigned
roles. Righteous Fury (paladins only) and Thorns are enabled by default; click their
icons to opt out individually. These choices are saved and only requested while
tanking. The panel names the caster or shows when none is available.

The tracker reminds paladin tanks to cast Righteous Fury on themselves and assigns
Thorns to druids for tank recipients, including assigned tanks without Buffeteria.
Multiple druids share Thorns targets. Missing and expiring tank buffs use the same
tracker and cast button as other buffs. Updated casters need Buffeteria's tank-buff
support to serve these requests; druids without the addon are named in the plan but
must cast manually. `/buff who` and **Announce to group** still list the group's plan.

## Paladin assignments

Paladins have a **Paladins** tab in `/buff` and Settings > AddOns > Buffeteria.
The window is styled like the game's Talents panel. Each paladin gets a talent tree,
with the nine classes' blessings shown as talent buttons and the paladin's aura as
a button in the tree's header. Gold buttons are
assignments you set, green ones follow Auto, and grey ones have nothing. The trees
share the board: one paladin fills it, two split it, three take a third each. With
more than three paladins, scroll horizontally with the mouse wheel or the scrollbar.
Click a class's blessing to cycle through the choices; right-click cycles backward. You can also
assign paladins without the addon. For those paladins, choose blessings you know they
can cast.

- **Auto** uses Buffeteria's normal class assignment solver. Every class is planned,
  including classes not in the group yet (from their class defaults), so all
  buttons are filled in, like PallyPower.
- A **specific blessing** sets that paladin's class assignment.
- **None** removes that paladin's class assignment.

Auras work the same way: Auto gives each paladin a different aura, in the order
Devotion, Concentration, Sanctity, Retribution, Fire, Frost and Shadow Resistance.
Paladins that know the fewest auras choose first, so a Concentration or Sanctity
talent goes to the paladin who has it. Without Buffeteria, a paladin is assumed to
know only the untalented auras. The tracker reminds you when your assigned aura
isn't running, and the big button turns it on.

**Auto-fill** turns every Auto blessing and aura into Buffeteria's current pick and
shares it, so the plan stays put when people join or leave. Your manual choices,
including None, stay as they are. **Clear** sets every slot back to Auto.

Edits are shared with the group's Buffeteria users. A paladin's own assignments are
saved between sessions; assignments for other paladins stay with the current group,
including while a paladin is briefly offline or on a loading screen, and are cleared
when you leave the group. Edits and preferences that arrive before the sender appears
in your roster are applied once they do.
Use **Announce to group** to communicate the plan to players without the addon.
Buffeteria cannot provide a cast button on a client that doesn't have it installed.

An explicit personal blessing preference takes priority over this class plan.
Dragging the blessing ranking enables **Override the Paladins class plan**; you can
also tick it to use your existing ranking. Untick it to follow the class plan again.
Players without Buffeteria, and users who haven't enabled a personal override, follow
the Paladins tab. When no manual assignment is set, class defaults apply.

Personal differences use single blessings. The tracker also uses single blessings
for that class when a Greater Blessing would overwrite someone's personal choice.
Everyone running Buffeteria should update together, since the assignment message
format changed for this feature.

## The tracker

Every class has a **Settings** tab in `/buff` and the game's Buffeteria AddOns page.
Its controls are grouped into four cards: **Tracker**, **Size**, **Show icons**, and
**Layout**, with a border-color legend underneath.
It holds **Show tracker**, **Lock tracker**, **Minimap button**, and **Preview**, plus
the clickable head's size (32–128 pixels; changes apply after combat), a separate
**Small icon size** slider (16–64 pixels, default: 21; applies immediately), and
the expiring-buff threshold (1–15 minutes). Changing the small icon size updates
the rows' spacing and alignment without resizing the face.

Choose which small buff icons appear: **Always show all**, **Missing only**,
**Missing or expiring** (the default), or **Expiring only**. A buff counts as
expiring when at least one recipient has less than the configured time left.
The counts follow the selected filter. These filters affect the small icons;
the head's expression and next cast still consider all tracked buffs.
Blessings, buffs, and auras all use the same full-color icons, with red borders
when missing, orange when expiring, and green when buffed. Missing takes priority
if some recipients are missing a buff while others have it running low.
In the **Layout** card, choose **2**, **3**, or **4** icons per row (default: 2).
Choose **Icon position: Left, Top, Right, Bottom, or Auto** (default: Bottom) from
the compass of buttons around **Auto**.
The four fixed positions keep the chosen side and icons per row, including near
screen edges. Move the tracker inward if icons extend off-screen.
**Auto** normally places rows below the face, moves them above near the bottom
of the screen, shifts rows inward at the left and right edges, and adds columns
when vertical space is tight. It uses your chosen icon size and row width as its
starting point, and updates while dragging or changing UI scale and resolution.
Top and Bottom center each row on the face, including a partially filled last
row. Left fills each row from right to left, starting beside the face; Right
fills from left to right. Rows update as icons appear or disappear.
The head stays fixed as icons appear or disappear; the grid follows it while
dragging, including in Edit Mode. Bottom leaves room for the next recipient's
name; Top leaves room for the preview tag and Edit Mode label.
Existing tracker visibility and display choices are preserved.

- **Orc head:** release a click to cast your next buff on the right target. The
  transparent mascot is green and smiling when everyone has their tracked buffs,
  orange and grumpy when some are missing or running low, and red and furious
  when all tracked buffs are missing across the group. With nothing to track,
  he is grey and grumpy.
  Players whose buffs can't be read (usually because they are out of range) don't
  change his mood; hovering lists them as out of range, and they count again once
  they are back in range. If nobody's buffs can be read, he is grey.
  His invisible click area is rectangular. The next recipient appears below him;
  hover to see the next spell and targets.
- **Small icons by the head:** which buffs need attention and how many players are
  affected. Hover for details.
- Right-click the big button for options. Move it with Edit Mode, or unlock it in
  options and drag. Dragging only moves it; releasing a drag never casts or opens options.
- The minimap icon also acts on click release; dragging it only changes its position.
- Bind a key: Key Bindings > AddOns > Buffeteria > "Cast next buff".
- Try `/buff preview` to cycle through furious, partly missing, running low, and
  happy states every five seconds without casting. Run it again to return to the
  real group.

## Commands

`/buff` options · `/buff who` assignments · `/buff announce` post them to the group ·
`/buff preview` fake raid · `/buff show` / `hide` · `/buff lock` · `/buff minimap` ·
`/buff reset`

## Notes

- The cast button can't change targets during combat (a WoW rule), so buff up
  between pulls.
- Some clients hide buff information in combat or instances; the tracker then keeps
  the last reading.

## Releases

Download the **Buffeteria ZIP asset** from [GitHub Releases](https://github.com/jruts/Buffeteria/releases)
and extract its `Buffeteria` folder into `Interface/AddOns`.
Publishing a GitHub release also uploads it to CurseForge after the one-time setup
in [RELEASING.md](RELEASING.md).

## Development checks

Local development installs as **Buffeteria-Dev**, alongside the published
**Buffeteria** copy from CurseForge. Enable one version at a time in the game's
AddOns menu to compare them. Live uses `/buff`; Dev uses `/buffdev` (or
`/buffeteriadev`), with the same subcommands, such as `/buffdev preview` and
`/buffdev settings`. Dev's Settings page and key bindings are labeled
**Buffeteria-Dev**. Each version keeps its own character settings; Dev starts
with defaults and does not change Live's preferences.

Dev's tracker has an orange **DEV** label above the head (**DEV / PREVIEW** while
previewing). A fresh Dev tracker starts 140 pixels to the right of Live's default
position; any position you already saved is preserved. Hovering the head also
identifies the copy. Having both folders installed does not mean both are enabled:
with one copy enabled, seeing one head is expected. Use the AddOns menu to switch.

After every workspace change, run:

```text
python tests/test_addon.py
python tools/deploy_dev.py
```

The deployment command installs to
`C:\Program Files (x86)\World of Warcraft\_classic_beta_\Interface\AddOns\Buffeteria-Dev`,
backs up overwritten files under `.release/local-backups/`, and checks installed
SHA-256 hashes. It leaves the published `Buffeteria` folder and saved variables
untouched. The source TOC remains `Buffeteria.toc` for release packaging; deployment
generates `Buffeteria-Dev.toc` and separate Dev bindings. Lua and artwork are copied
unchanged. This does not publish a release or update CurseForge.

Use `/reload` to load subsequent changes with Dev enabled. If the new Dev folder
does not appear in the AddOns menu after the first install, restart the client.
Dev uses the normal Buffeteria group messages so you can test it with release
users; keep only one version enabled to avoid sending conflicting preferences.

Run `python tests/test_addon.py` with `lupa` installed. The tests use Lua 5.1 and a
mock WoW environment to check assignments, synchronization, saved data, editor
navigation, tracker decisions, and startup in the manifest's actual load order
for all nine classes, plus Dev identity, separate settings, and deployment with
backups and release-file preservation. Layout and protected casting still need
an in-game check.

## Code organization

Each feature owns its logic and, when needed, its view:

| Directory | Responsibility |
| --- | --- |
| `Features/Buffs` | Spell catalog and class defaults |
| `Features/Preferences` | Personal buff choices, reset behavior, and preference controls |
| `Features/Roster` | Group members, peer preferences, and spell capabilities |
| `Features/Assignments` | Pure assignment solver, recomputation, summaries, and announcements |
| `Features/Paladins` | Shared class plans and their editor |
| `Features/Sync` | Message protocol, transport, and retry queue |
| `Features/Tracker` | Aura observations, next-cast selection, status, secure buttons, and preview |
| `Features/Minimap` | Minimap button and positioning |
| `Features/Options` | Window and Settings page hosting the feature views |

`App` initializes the runtime snapshots and saved variables, routes WoW events,
and exposes commands. `Shared` contains the WoW compatibility helpers, reused UI
controls, and internal notifications. The existing saved-variable keys and
version 2 message format are preserved.

Keep new behavior in its owning feature. Use its namespace (`ns.Preferences`,
`ns.Paladins`, etc.) for public operations; keep implementation helpers local.
Use `ns.Events.On` and `ns.Events.Emit` for refresh notifications instead of
replacing another feature's callbacks. Extract shared code only when multiple
features actually need it. Update `Buffeteria.toc` when adding a runtime file;
the manifest lists dependencies before their consumers and loads bootstrap last.
