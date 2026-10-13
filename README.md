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
  three named panels: **Blessings**, **Buffs** (including Battle Shout for warriors
  and Inner Fire for priests), and **Tank role** (Righteous Fury for paladins and
  Thorns from a druid). Each buff row names its caster; missing casters are grey.
- **Smart assignments.** Paladins serve your highest available blessings, subject
  to their spells and the class plan. Greater Blessings cover a whole class, so
  each class gets what most of its players ranked highest. Priests, druids and mages split the raid groups by
  work: a group is one cast for someone with the group spell (Prayer, Gift, Arcane
  Brilliance) but one cast per player without it, so the work evens out. On a tie, a
  caster keeps their own group, where they are in range. Everyone should update
  together: copies that split groups differently disagree on who buffs which group.
- **Personal exclusions.** With **Use my own order** ticked, drag Salvation
  below **Don't want** to avoid it while tanking. With it off, you get your
  class's blessings from the shared plan, including manual assignments;
  exclusions belong to your own order.
- **No raid leader needed.** Every copy of Buffeteria computes the same answer from the
  same preferences. Players without the add-on get sensible class defaults.

Blessing rankings use larger rows. While dragging, the lifted row follows your
cursor, an outlined slot marks where it will land, and the other rows slide aside.

New installs start from a class default ranking: warriors and rogues want Might
first; mages, warlocks, priests, druids, paladins, and shamans want Wisdom first;
hunters want Kings first (Might doesn't raise ranged attack power). Kings and
Salvation follow for everyone. Casters don't want Might, and warriors and rogues
don't want Wisdom. Players without the add-on are planned from the same defaults,
and so are classes Auto and **Lock in Auto picks** cover on the Paladins tab. If your saved
ranking still matches the old Kings-first default, it moves to the new one; a
ranking you reordered is kept.

Warriors see **Battle Shout** in the Buffs panel. It is on by default; click it to
skip it. The tracker reminds you when your own shout is missing or has less than
30 seconds left (it lasts only two minutes, so the expiring-buff setting would
always flag it), and the big button casts it once you have enough rage. Other
classes never see it, and warriors without Buffeteria aren't tracked for it.

Priests likewise see **Inner Fire** in the Buffs panel, on by default and skippable.
The tracker reminds you when it is missing (including after its charges run out)
or has less than 60 seconds of its ten minutes left, and the big button casts it
once you have the mana. Other classes never see it, and priests without
Buffeteria aren't tracked for it.

Battle Shout and Inner Fire are also tracked **during combat**. When combat starts,
the head is set to cast your shout or Inner Fire, so if it runs low or falls off
mid-fight the head demands it and a click recasts it. Other buffs wait until combat
ends (the game doesn't let add-ons change the button's target during combat).
The client hides buffs during combat, so the tracker dates them from the last
reading before the pull and from your own recasts. A buff you lose early
(clicked off, or Inner Fire's charges used up) can't be seen until combat ends.

In **My preferences > Tank role**, choose **Auto**, **Tank**, or **Not tank**
explicitly. Auto shows its resolved role and follows your assigned Tank role or
raid main-tank assignment. Use Tank or Not tank for solo play or groups without
assigned roles. Righteous Fury (paladins only) and Thorns are enabled by default; click their
icons to opt out individually. These choices are saved and only requested while
tanking. The panel names the caster or shows when none is available.

The tracker reminds paladin tanks to cast Righteous Fury on themselves and assigns
Thorns to druids for tank recipients, including assigned tanks without Buffeteria.
Multiple druids share Thorns targets. Missing and expiring tank buffs use the same
tracker and cast button as other buffs. Updated casters need Buffeteria's tank-buff
support to serve these requests; druids without the addon are named in the plan but
must cast manually. `/buff who` and **Announce to group** still list the group's plan.

## Extra: resurrect

The **Extra** tab in `/buff` (or `/buff extra`) holds conveniences beyond buffs.
**Resurrect with the head** is on by default for every class: priests
(Resurrection), paladins (Redemption), shamans (Ancestral Spirit) and druids
(Rebirth) see the head demand **GIEF** their resurrection when a group member is
dead, and a click casts it, before any buff. Other classes have nothing to cast.
Players who can resurrect are picked first, then the rest by name. Players who
already released count too. Only players in range count; feigning hunters and
players someone else is already resurrecting are skipped, and after your resurrection lands the player
gets a minute to accept. It waits while you're out of mana or reagents, and while
Rebirth is on cooldown. Combat keeps the head on your combat buff, so resurrecting
waits until combat ends.

## Paladin assignments

Paladins have a **Paladins** tab in `/buff` and Settings > AddOns > Buffeteria.
The window uses Blizzard's portrait frame, inset panels, native controls and spell
icons. The **Class blessings** grid has classes as rows and paladins as columns;
five paladins fit side by side, with horizontal scrolling for larger rosters.
Class rows show group counts and the number of players using personal rankings;
absent classes are dimmed but remain editable. Each paladin's header includes an
aura picker and an explicit class coverage count.

Click a blessing or aura to open its picker. For Buffeteria users the picker lists
only known spells. For paladins without the add-on, it labels the spellbook as
unverified and permits manual choices; choose only spells they can cast.
Right-click a slot to reset it to **Auto**, or Shift-click to set **None**.
Auto has a boxed **A** badge, manual choices have a gold border, None has a
pass icon, and conflicts have a red border and read **Conflict**; state is not
communicated by color alone. A legend under the grid repeats these cues.

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
isn't running, and the big button turns it on. Another paladin's copy of the same
aura on you counts as covered, because the game shows only one copy.

A paladin column marked **Unverified** means your client has not heard from that
paladin's Buffeteria. Their spellbook is assumed untalented (no Kings, Concentration
or Sanctity), so each client may give those to its own paladin and the plans
disagree. `/buff sync` shows the channel in use, sent and failed messages, and
which players your client has heard from.

**Lock in Auto picks** turns every resolved Auto blessing and aura into
Buffeteria's current pick and shares it, so the plan stays put when people join or
leave. Your manual choices, including None, stay as they are.
**Reset all to Auto** resets the whole plan. **Undo** reverses the last bulk
action where its cells have not since been edited; it preserves newer group
edits and newer claims on the same blessing. Undo history ends when you leave
the group or reload.

Edits are shared with the group's Buffeteria users. A paladin's own assignments are
saved between sessions; assignments for other paladins stay with the current group,
including while a paladin is briefly offline or on a loading screen, and are cleared
when you leave the group. Edits and preferences that arrive before the sender appears
in your roster are applied once they do.
Paladins sharing an older plan cell receive the group's newer version, and login
synchronization requests saved edits from older clients so plans can reconcile.
Use **Announce to group** to communicate the plan to players without the addon.
Buffeteria cannot provide a cast button on a client that doesn't have it installed.

An explicit personal blessing preference takes priority over this class plan.
The Blessings panel has one checkbox, **Use my own order**. Off, you get the
Greater Blessings planned for your class; your list is saved but greyed out and
not used. On, you get the blessings at the top of your list. The line under the
checkbox names the blessings you get; hover it for the casters. Dragging the list
ticks the checkbox; untick it to keep your order without applying it. A note under
the list explains the current state in plain words.
Checkmarks identify blessings actually cast on you; hover a row to see who casts
it, or why nobody does. A gold **You get the top N** line appears only when
assignments form a contiguous prefix of your personal ranking; it is computed
from the plan, not from paladin count alone.
Players without Buffeteria, and users who haven't enabled a personal override, follow
the Paladins tab. When no manual assignment is set, class defaults apply.

Personal differences use single blessings. The tracker also uses single blessings
for that class when a Greater Blessing would overwrite someone's personal choice.
Everyone running Buffeteria should update together, since the assignment message
format changed for this feature.

## The tracker

Every class has a **Settings** tab in `/buff` and the game's Buffeteria AddOns page.
Its controls are grouped by **Display**, **Behavior**, **Appearance**, **Buff
icons**, and **Layout**, with an isolated **Tracker preview** beside them.
Display contains Show tracker, Lock tracker and Minimap button. Behavior contains
**Help with overdue buffs** (see below). Appearance contains the head selector,
Colored hair and three size sliders: head (32–128 pixels, default 96), small icons (16–64
pixels, default 32), and shout-out text (10–24 pixels, default 16).

The preview uses sample raid data, the same head artwork, icon filters, border
colors and layout calculation as the real tracker. Switch its Happy, Grumpy and
Angry examples to inspect expressions; large combinations are scaled to fit the
inset. It remains visible when Show tracker is off, updates while editing, and
never casts or changes the real tracker's target, position or preview mode.
Head sizing on the real tracker waits until after combat; the Settings header
shows this note only in combat. The sample can resize immediately.

Choose **Head: Orc, Gnome, Night Elf, Tauren, Human, Troll, Undead, or Xaru** using
the native-arrow portrait menu. Each head has happy, grumpy and angry artwork
and a matching cast halo. All are floating heads without necks or shoulders.
**Colored hair** is on by default: subtly green when happy, orange when grumpy,
and red when angry. Untick it to restore original hair colors. Skin, facial
hair and accessories retain their natural colors. Xaru is the human mage homage
with swept-back hair, moustache and goatee. Every class can select every head.
Head and hair choices are saved per character and apply immediately, including
in combat, without changing the next spell or target.

Prefer no mascot? Pick **None (clean)** at the bottom of the head menu. The
tracker then shows just the small icons. Only when you have something to cast
does a plain square button appear, showing the icon of that cast with a border
colored like the small icons (orange when your buffs are expiring, red
when any of your buffs are missing); click it or use the key binding. It keeps its place
while hidden, so the small icons don't move. To move the tracker while the
button is hidden, drag any small icon (when unlocked), or use Edit Mode, which
marks the button's spot with a faint Buffeteria icon. There is no halo, GIEF call-out,
face or badge; filters, layout, cooldown shade, tooltips and resurrecting work
the same, and the Settings preview follows. Colored hair is greyed out, and
your last head is kept for when you switch back.

Choose which small buff icons appear: **All**, **Missing**,
**Missing or expiring** (the default), or **Expiring**. A buff counts as
expiring when at least one of your assigned recipients has less than the configured time left.
The counts follow the selected filter. These filters affect the small icons;
the head's expression and next cast still consider all your assigned buffs.
Other casters' work does not appear in the small icons or affect your head's mood,
even when you share the same buff type. Overdue help appears when the head offers
you that cast.
Blessings, buffs, and auras all use the same full-color icons, with red borders
when missing, orange when expiring, and green when buffed. Missing takes priority
if some recipients are missing a buff while others have it running low.
The border legend stays inside Buff icons. **Expiring below** selects the
1–15 minute warning threshold. In the **Layout** panel, choose **2**, **3**, or **4** icons per row (default: 2).
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
dragging, including in Edit Mode. Top leaves room for the GIEF call-out, the
preview tag and Edit Mode label.
Existing tracker visibility and display choices are preserved.

- **Character head:** release a click to cast your next buff on the right target.
  The transparent mascot smiles when your assigned recipients have their buffs, turns
  grumpy when your buffs are running low, and furious when any buff you are assigned
  to give is missing. Missing buffs take priority over expiring ones, so casting
  one buff keeps the head red until all your missing buffs are served. Other
  casters' missing buffs do not change your head. With nothing to track, the head
  is grey and grumpy.
  Players whose buffs can't be read (usually because they are out of range) don't
  change the mood; hovering lists them as out of range, and they count again once
  they are back in range. If nobody's buffs can be read, the head is grey.
  Its invisible click area is rectangular.
- **Is it my turn?** When you have something to cast, a glow breathes around the head
  (soft orange for expiring buffs, strong red for missing buffs, flaring up
  whenever the next spell changes) and it demands the buff above the face,
  for example **GIEF Fortitude!** The halo stays behind the head; the face is never
  brightened by an additive shimmer. Hover to see the spell and target. When
  there's nothing for you to cast, there is no glow and clicking does nothing; hover
  to see which buffs you're missing and who is supposed to cast them. The glow and
  GIEF only appear when you can make the cast yourself, including on yourself;
  just needing a buff never triggers them. In combat, only Battle Shout and Inner
  Fire are demanded.
- **Your part vs. theirs.** A badge in the head's top-right corner shows your own
  share. A gold number counts the players (and your
  aura) you still have to serve. A small, faint green check means everyone assigned
  to you is served. With no buffs
  to give, there is no badge. Players out of range aren't counted against your check.
  When the remove-unwanted-buff button occupies the corner, the badge sits beside it.
  Hover the head or the small icons to see who you're waiting for.
- **Mash away.** A cast counts once it actually goes off, so pressing the button or
  key binding during the global cooldown never skips a target. Presses during the
  cooldown are simply held, so they don't flood you with "Spell is not ready yet"
  (in combat the press still goes through, with that error muted). While the
  cooldown runs, a shadow drains off the face from the top down, like an action
  button's cooldown sweep, even after your last buff. Pressing the head only dims
  it, and hovering it only shows the spell-cast cursor, when the press will
  actually cast something. A Prayer, Gift, Arcane
  Brilliance or Greater Blessing counts for everyone it covers, so you aren't sent to
  recast it on them one by one. The tracker also updates as soon as anyone gains or
  loses a buff, so when another caster gets there first the button moves on.
- **Help with overdue buffs** (on by default, in Settings): with nothing of your own to
  cast, you are offered your class's group buffs and Thorns on players whose
  assigned caster hasn't served them after 30 seconds, or right away when that
  caster is dead or out of sight. Several helpers take turns 10 seconds apart, so
  only one steps in. Hover to see who you're covering for. Blessings are never
  covered: a paladin's new blessing on a player replaces their previous one.
- **Small icons by the head:** your assigned buffs and how many of your recipients
  need attention. Other casters' buffs are hidden. Hover for details.
- Right-click the big button for options. Move it with Edit Mode, or unlock it in
  options and drag. Dragging only moves it; releasing a drag never casts or opens options.
- The minimap icon also acts on click release; dragging it only changes its position.
- Bind a key: Key Bindings > AddOns > Buffeteria > "Cast next buff".
- Try `/buff preview` to cycle through all missing, partly missing, running low, and
  happy states every five seconds without casting. Paladins, priests, druids and
  mages see the GIEF call-out and both missing phases stay furious; other classes
  stay happy while waiting for buffs from others. Run it again to return to the
  real group.

The window remembers your last tab. On first opening, paladins in a raid start on
Paladins; other players start on My preferences. The same panels are used in
Settings > AddOns. A shared footer contains **Announce to group**; hover it to
see the exact plan and whether it goes to Raid, Party or your local chat.
The tab bar sits below the native title bar. `/buff preferences` opens personal
preferences directly; `/buff paladins` opens the paladin-only assignment editor.
`/buff settings` selects Settings, including when another tab was remembered.
`/buff extra` opens Extra.
Dev uses `/buffdev preferences`, `/buffdev paladins`, `/buffdev settings`, and `/buffdev extra`.

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

The mascot source sheets and their exact built-in ImageGen prompts are kept under
`Artwork/Tracker/`. [The tracker art guide](Artwork/Tracker/STYLE_GUIDE.md) defines
Classic race features, lighting, expressions, and reference sources.
Run `python tools/build_tracker_art.py` with Pillow to rebuild
all eight heads' original and colored hair runtime portraits and silhouette glows
in `Media/`. Use `--colored-only` to rebuild just the colored hair variants.
These are uncompressed 256×256 RGBA TGA textures for the game; source artwork
and build tools are not deployed.

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
| `Features/Preferences` | Personal buff choices, their defaults and migrations, reset behavior, the drag-and-drop ranking, and preference controls |
| `Features/Roster` | Group members, peer preferences (the `S` message), spell capabilities, and member names |
| `Features/Assignments` | Pure assignment solver, recomputation, summaries, and announcements |
| `Features/Paladins` | Shared class plans and their editor |
| `Features/Sync` | Wire format (`Protocol`), transport, and retry queue |
| `Features/Tracker` | Aura observations, next-cast selection, status, icon layout, tooltips, secure buttons, Edit Mode, and preview |
| `Features/Minimap` | Minimap button and positioning |
| `Features/Extra` | Extra conveniences: resurrecting with the head, and the Extra tab |
| `Features/Options` | Window and Settings page hosting the feature views |

`App` initializes saved variables, routes WoW events, wires feature notifications
to re-solving, and exposes commands. `App/Database.lua` validates display settings
against one table of ranges and choices, which the settings controls also read;
`ns.Database.Set` normalizes a value and emits `SettingsChanged` so the tracker,
minimap button, and open controls follow. `Shared` contains plain table helpers,
the WoW compatibility helpers, reused UI controls, and internal notifications; it
never depends on a feature. The existing saved-variable keys and version 2
message format are preserved.

Each feature owns its saved data and writes it through its own API. Preferences
owns personal choices and their migrations (`ns.Preferences.Set`, `Toggle`,
`Reset`, which emit `PreferencesChanged`); Paladins owns its plan cells
(`PaladinPlanChanged`); Roster owns peer state (`PeersChanged`). Bootstrap
re-solves after any of these.

Each roster read flows one way: `Assignments.Resolve` builds the roster, lets
`Paladins.Attach` add the shared class plan and the spells it implies, runs the
pure solver, and emits `AssignmentsChanged`. Assignments owns the snapshots:
read `ns.Assignments.roster` and `ns.Assignments.result` (or the accessors
`Served`, `ClassBlessing`, and `Aura`) and never write them. `Tracker.Compute`
combines the observed group (`Scan`) with the next cast (`Actions`), and the
tracker emits `SummaryChanged` after each refresh. Tracker modules live under
`ns.Tracker` (`ns.Tracker.Scan`, `ns.Tracker.Actions`, and so on).

`Sync/Comm` is only the transport. A feature shares its state when
`BroadcastRequested` fires and handles its own message kind from
`Received:<kind>` (sender, fields...): Roster sends and receives `S`, Paladins
`P`. The Options window creates each tab's panel and the feature's view fills it.

Keep new behavior in its owning feature. Use its namespace (`ns.Preferences`,
`ns.Paladins`, etc.) for public operations; keep implementation helpers local.
Use `ns.Events.On` and `ns.Events.Emit` for notifications instead of calling
or replacing another feature's functions. Extract shared code only when multiple
features actually need it. Update `Buffeteria.toc` when adding a runtime file;
the manifest lists dependencies before their consumers and loads bootstrap last.
