# Buffeteria

## Unreleased

- Updated the options window to Forever's translucent Edit Mode panel style and the tracker selection to native blue/gold nine-slice artwork.
- Added a Paladins-only tab for built-in, shared class blessing assignments, including assignments for players without Buffeteria.
- Class assignments support Auto, a specific blessing, or None, and each paladin's own assignments persist between sessions.
- Explicit personal blessing preferences take priority over the class plan; existing custom rankings are preserved as overrides.
- Use single blessings when a Greater Blessing would overwrite a personal assignment.
- Updated assignment synchronization and retry handling. Buffeteria users should update together.

## v0.5.0

First public release.

- Every player ranks the blessings they want (drag to reorder) and ticks the other buffs they care about.
- Buffeteria works out which paladin casts which Greater Blessing on which class, and which priest, druid and mage covers which group.
- Tanks and anyone else can exclude a blessing (e.g. Salvation): they automatically get a different blessing from that paladin.
- One-click tracker: big button casts your next buff; small icons show what's missing (red) or running low (orange).
- Minimap button, options page under Esc > Options > AddOns, Edit Mode support, key binding, and a preview mode with a fake raid.
