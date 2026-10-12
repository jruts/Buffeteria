# Buffeteria

## v0.6.4

Update Buffeteria together with your group: group buff assignments now account for each caster's available group spells.

- Choose from eight tracker heads: Orc, Gnome, Night Elf, Tauren, Human, Troll, Undead, and Xaru.
- Colored hair is on by default: muted green when happy, orange when annoyed, and red when angry. Turn off **Colored hair** in Settings to restore the original artwork; the choice is saved per character.
- Refined the Classic portraits and kept cast lighting behind the face. The cast halo is soft orange when annoyed and stronger red when angry.
- Buffing advances after a successful cast, accounts for everyone covered by group and Greater spells, and updates promptly when another caster applies a buff.
- Group buff assignments balance the number of casts and favor a caster's own group on a tie. **Cover for others**, enabled by default, lets helpers serve overdue group buffs and Thorns.
- Repeated presses during the global cooldown no longer skip targets or flood spell-not-ready errors. A shadow on the head shows the cooldown; the cast cursor and press dimming appear when the button can cast.
- Tinted preference tree artwork with each class's color for readability.

## v0.6.3

- Added optional **Inner Fire** tracking for priests, enabled by default in the Buffs tree once learned. The tracker warns when it is missing or has less than 60 seconds left, and offers the cast once you have enough mana. Battle Shout likewise appears in the Buffs tree only after it is learned.
- **Battle Shout and Inner Fire stay tracked during combat.** The orc calls for your self buff when it runs low, and clicking recasts it. Because the client hides buff information during combat, timing follows the last reading before the pull and your own recasts; early removals, including Inner Fire charges running out, are detected after combat.
- Simplified the tracker: removed the **Need** label beneath the head and kept the **GIEF** call-out for buffs you can cast yourself. The head stays fully visible when there is nothing for you to cast.
- Refactored feature ownership, shared controls, and event handling for simpler maintenance while preserving saved settings and the existing group message format.

## v0.6.2

- The tracker now makes it clear when you have a buff to cast: the orc glows gold and calls out **GIEF <buff>!** above his head. When there is nothing for you to cast, he dims and shows the buffs you still need; tooltips name the assigned casters.
- Small icons for buffs assigned to other players are dimmed, while your assignments and buffs you need stay bright. Added a **Shout-out text** size slider and class-aware preview states.
- Added optional **Battle Shout** tracking for warriors, enabled by default in the Buffs tree. The tracker warns when your shout is missing or has less than 30 seconds left, and offers the cast once you have enough rage. Other classes and warriors without Buffeteria are not tracked for it.

## v0.6.1

- Fixed personal preferences and Paladins-tab edits arriving before players appear in the roster. Assignments now survive a paladin briefly going offline or entering a loading screen, and clear when you leave the group.
- Normalized realm names across roster and group messages, and prevented rejected messages from blocking the synchronization queue.
- Enlarged blessing ranking rows and added drag animations: the lifted row follows the cursor, an outlined slot marks its destination, and neighboring rows slide into place.
- Added a separate Buffeteria-Dev installation for local testing, with its own settings, commands, bindings, and visible DEV tracker label.

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
