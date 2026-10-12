# Buffeteria

## v0.6.0

Update Buffeteria together with your group: this release changes the assignment message format.

- Added a **Paladins** tab for shared class blessing assignments, including paladins without Buffeteria. Choose Auto, a specific blessing, or None; your own assignments persist between sessions. Auto plans every class, including classes not currently in the group.
- Added shared paladin aura assignments. Auto gives each paladin a different aura and accounts for talented auras. The tracker reminds you to activate your assigned aura, and announcements include it.
- Added **Auto-fill** to lock in the current automatic blessing and aura picks, plus **Clear** to return all slots to Auto.
- Personal blessing overrides take priority over the class plan. Custom rankings are preserved, and single blessings prevent Greater Blessings from overwriting personal choices.
- Updated class defaults: warriors and rogues prefer Might, casters prefer Wisdom, and hunters prefer Kings. Existing untouched default rankings migrate; custom rankings stay as saved.
- Added **Tanks** preferences with Auto, Tank, and Not tank role choices. The tracker serves Righteous Fury for paladin tanks and distributes Thorns targets among druids, including assigned tanks without Buffeteria.
- Restyled `/buff` with a Talents-style window and talent buttons. Paladin trees share the board according to roster size and scroll horizontally beyond three paladins; preference panels name assigned casters.
- Replaced the tracker head with a transparent orc whose expression and color reflect buff status. Out-of-range players no longer change his mood; tooltips still identify them.
- Rebuilt **Settings** with Tracker, Size, Show icons, and Layout cards plus a border-color legend. Added separate head and small-icon sizes, missing/expiring icon filters, 2/3/4 icons per row, and Left/Top/Right/Bottom/Auto positioning. Auto adapts to screen edges and available space.
- Tracker and minimap actions occur on click release; releasing a drag only finishes moving the button. Improved assignment synchronization and retries, and reorganized the add-on into feature modules.

## v0.5.0

First public release.

- Every player ranks the blessings they want (drag to reorder) and ticks the other buffs they care about.
- Buffeteria works out which paladin casts which Greater Blessing on which class, and which priest, druid and mage covers which group.
- Tanks and anyone else can exclude a blessing (e.g. Salvation): they automatically get a different blessing from that paladin.
- One-click tracker: big button casts your next buff; small icons show what's missing (red) or running low (orange).
- Minimap button, options page under Esc > Options > AddOns, Edit Mode support, key binding, and a preview mode with a fake raid.
