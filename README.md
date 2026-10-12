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
  Buffs (each buff names its caster, plus tracker options), and Kitchen (the whole
  group's plan: every paladin's blessings and every caster's raid groups).
- **Smart assignments.** With one paladin you get your #1 blessing, with two your #1 and
  #2, and so on. Greater Blessings cover a whole class, so each class gets what most of
  its players ranked highest. Priests, druids and mages split the raid groups.
- **No Salvation on the tank.** Drag a blessing below the line and you'll get a
  different personal blessing from that paladin instead.
- **No raid leader needed.** Every copy of Buffeteria computes the same answer from the
  same preferences. Players without the add-on get sensible class defaults.

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
saved between sessions; assignments for other paladins stay with the current group.
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

- **Big button:** click it to cast your next buff on the right target. Its ring is
  green when everyone is fed, orange when buffs are running low, red when something is
  missing.
- **Small icons underneath:** which buffs need attention and how many players are
  affected. Hover for details.
- Right-click the big button for options. Move it with Edit Mode.
- Bind a key: Key Bindings > AddOns > Buffeteria > "Cast next buff".

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

Run `python tests/test_addon.py` with `lupa` installed. The tests use Lua 5.1 and a
mock WoW environment to check assignments, synchronization, saved data, editor
navigation, tracker decisions, and startup in the manifest's actual load order
for all nine classes. Layout and protected casting still need an in-game check.

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
