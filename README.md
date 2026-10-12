# Buffeteria

**All-you-can-buff.** Raid buff coordination for every class, not just paladins.

Targets **World of Warcraft: Forever** (interface `16001`, client `1.60.1`).

Everyone in the group runs Buffeteria and says what they want on their plate. Buffeteria
works out who casts what, and a one-click tracker serves it.

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
