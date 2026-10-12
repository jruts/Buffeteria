# Buffeteria

**All-you-can-buff.** Raid buff coordination for every class, not just paladins.

Targets **World of Warcraft: Forever** (interface `16001`, client `1.60.1`).

Buffeteria works out who casts what, and a one-click tracker serves it. Players can
choose their own buffs, while paladins can manage class blessings for the whole group,
including players who don't have Buffeteria installed. No PallyPower addon is required.

## How it works

- **You order, the kitchen cooks.** Each player ranks the paladin blessings they want
  (drag to reorder) and ticks the buffs they care about (Fortitude, Spirit, Shadow
  Protection, Mark of the Wild, Arcane Intellect).
- **Smart assignments.** With one paladin you get your #1 blessing, with two your #1 and
  #2, and so on. Greater Blessings cover a whole class, so each class gets what most of
  its players ranked highest. Priests, druids and mages split the raid groups.
- **No Salvation on the tank.** Drag a blessing below the line and you'll get a
  different personal blessing from that paladin instead.
- **No raid leader needed.** Every copy of Buffeteria computes the same answer from the
  same preferences. Players without the add-on get sensible class defaults.

## Paladin assignments

Paladins have a **Paladins** tab in `/buff` and Settings > AddOns > Buffeteria.
Use the arrows to select a paladin, then click each class's blessing to cycle through
the choices; right-click cycles backward. You can also assign paladins without the
addon. For those paladins, choose blessings you know they can cast.

- **Auto** uses Buffeteria's normal class assignment solver.
- A **specific blessing** sets that paladin's class assignment.
- **None** removes that paladin's class assignment.

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
navigation, and tracker decisions. Layout and protected casting still need an
in-game check.
