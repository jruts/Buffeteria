"""Run with python tests/test_addon.py (requires lupa with its Lua 5.1 runtime)."""
from pathlib import Path
import unittest

from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]


def runtime():
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.execute("ns = {}; function loadAddon(source, name) assert(loadstring(source, name))('Buffeteria', ns) end")
    return lua


def load(lua, name):
    lua.globals().loadAddon((ROOT / name).read_text(encoding="utf-8"), name)


def addon_files():
    return [line.strip() for line in (ROOT / "Buffeteria.toc").read_text().splitlines()
            if line.strip().endswith(".lua") and not line.startswith("#")]


def full_addon(player_class="PALADIN", login=True):
    lua = runtime()
    lua.execute((ROOT / "tests/wow_mock.lua").read_text(encoding="utf-8"))
    lua.globals().PLAYER_CLASS = player_class
    for name in addon_files():
        load(lua, name)
    lua.execute("ns.App:GetScript('OnEvent')(ns.App, 'ADDON_LOADED', 'Buffeteria')")
    if login:
        lua.execute("ns.App:GetScript('OnEvent')(ns.App, 'PLAYER_LOGIN'); runTimers()")
    return lua


class AddonTests(unittest.TestCase):
    def test_manifest_contains_each_runtime_module_once(self):
        files = addon_files()
        expected = {path.relative_to(ROOT).as_posix() for folder in ("App", "Shared", "Features")
                    for path in (ROOT / folder).rglob("*.lua")}
        self.assertEqual(len(files), len(set(files)))
        self.assertEqual(set(files), expected)

    def test_manifest_startup_and_commands_for_every_class(self):
        for player_class in ("WARRIOR", "ROGUE", "HUNTER", "MAGE", "WARLOCK", "PRIEST", "DRUID", "PALADIN", "SHAMAN"):
            with self.subTest(player_class=player_class):
                lua = full_addon(player_class)
                lua.execute("""
                    assert(ns.roster.members['A-Realm'].class == PLAYER_CLASS)
                    assert(ns.result.expected['A-Realm'])
                    assert(ns.Tracker.Summary().any)
                    assert(#tickers == 3)
                    for _, message in ipairs(delivered) do assert(#message <= 255) end
                    SlashCmdList.BUFFETERIA('show'); assert(ns.db.showTracker)
                    SlashCmdList.BUFFETERIA('hide'); assert(not ns.db.showTracker)
                    SlashCmdList.BUFFETERIA('lock'); assert(ns.db.locked)
                    SlashCmdList.BUFFETERIA('minimap'); assert(ns.db.minimap.hide)
                    ns.db.blessingsOverride = true
                    SlashCmdList.BUFFETERIA('reset'); runTimers()
                    assert(not ns.db.blessingsOverride)
                    SlashCmdList.BUFFETERIA(''); assert(Buffeteria_Prefs:IsShown())
                    assert(findWidget('Paladins'):IsVisible() == (PLAYER_CLASS == 'PALADIN'))
                    Buffeteria_OnAddonCompartmentClick(nil, 'RightButton'); assert(openedCategory == 1)
                """)

    def test_options_opened_before_login_keep_assignment_updates(self):
        lua = full_addon(login=False)
        lua.execute("""
            ns.Options.Toggle()
            local refresh = ns.Preferences.View.Refresh
            refreshes = 0
            ns.Preferences.View.Refresh = function() refreshes = refreshes + 1; refresh() end
            ns.App:GetScript('OnEvent')(ns.App, 'PLAYER_LOGIN'); runTimers()
            assert(refreshes > 0 and ns.Tracker.Summary().any)
            refreshes = 0
            ns.Preferences.Changed(); ns.Assignments.Resolve(); ns.Assignments.Resolve()
            assert(#timers == 1) -- resolving repeated changes is debounced
            runTimers()
            assert(refreshes == 1 and ns.Tracker.Summary().any)
        """)

    def test_preview_and_combat_preserve_secure_button_behavior(self):
        lua = full_addon()
        lua.execute("""
            assert(Buffeteria_CastButton:GetAttribute('spell'))
            assert(Buffeteria_CastButton:GetAttribute('type2') == 'macro')
            assert(Buffeteria_CastButton:GetAttribute('macrotext2') == '')
            ns.Preview.Set(true)
            assert(not Buffeteria_CastButton:GetAttribute('spell'))
            assert(not Buffeteria_CastButton:GetAttribute('unit'))
            assert(not Buffeteria_CancelButton:GetAttribute('spell'))
            assert(not Buffeteria_CancelButton:IsShown())
            ns.Preview.Set(false)
            local spell, unit = Buffeteria_CastButton:GetAttribute('spell'), Buffeteria_CastButton:GetAttribute('unit')
            COMBAT = true
            ns.Tracker.Refresh()
            assert(Buffeteria_CastButton:GetAttribute('spell') == spell)
            assert(Buffeteria_CastButton:GetAttribute('unit') == unit)
            COMBAT = false
            ns.App:GetScript('OnEvent')(ns.App, 'PLAYER_REGEN_ENABLED')
            local pending = ns.Tracker.Summary().next
            Buffeteria_CastButton:GetScript('PostClick')(Buffeteria_CastButton, 'LeftButton', false)
            runTimers()
            local nextAction = ns.Tracker.Summary().next
            assert(not nextAction or nextAction.who ~= pending.who or nextAction.key ~= pending.key)
            WOW_TIME = WOW_TIME + 4
            ns.Tracker.Refresh()
            assert(Buffeteria_CastButton:GetAttribute('spell'))
        """)

    def test_edit_mode_movement_options_and_visibility(self):
        lua = full_addon()
        lua.execute("""
            ns.db.showTracker = false
            ns.Tracker.Refresh()
            assert(not Buffeteria_Tracker:IsShown())
            EventRegistry:TriggerEvent('EditMode.Enter')
            local overlay = Buffeteria_Tracker.editOverlay
            assert(Buffeteria_Tracker:IsShown() and overlay:IsShown())
            overlay:GetScript('OnDragStart')(overlay)
            assert(Buffeteria_Tracker.moving)
            Buffeteria_Tracker:SetPoint('CENTER', UIParent, 'CENTER', 37, -81)
            overlay:GetScript('OnDragStop')(overlay)
            assert(not Buffeteria_Tracker.moving)
            assert(ns.db.pos[3] == 37 and ns.db.pos[4] == -81)
            overlay:GetScript('OnClick')(overlay)
            assert(Buffeteria_Prefs:IsShown())
            Buffeteria_Prefs.CloseButton:GetScript('OnClick')()
            assert(not Buffeteria_Prefs:IsShown())
            settingsPage:Show() -- It starts shown in the mock; force its OnShow.
            settingsPage:GetScript('OnShow')(settingsPage)
            assert(findWidget('My preferences').parent.parent == settingsPage)
            ns.Options.Toggle()
            assert(findWidget('My preferences').parent.parent == Buffeteria_Prefs)
            COMBAT = true
            overlay:GetScript('OnDragStart')(overlay)
            assert(not Buffeteria_Tracker.moving)
            COMBAT = false
            EventRegistry:TriggerEvent('EditMode.Exit')
            assert(not overlay:IsShown() and not Buffeteria_Tracker:IsShown())
            COMBAT = true
            EventRegistry:TriggerEvent('EditMode.Enter')
            assert(not overlay:IsShown() and not Buffeteria_Tracker:IsShown())
        """)

    def test_lua51_syntax(self):
        lua = runtime()
        compile_lua = lua.eval("function(s,n) local f,e=loadstring(s,n); assert(f,e) end")
        for path in ROOT.rglob("*.lua"):
            compile_lua(path.read_text(encoding="utf-8"), path.name)

    def solver(self, code):
        lua = runtime()
        load(lua, "Features/Buffs/Catalog.lua")
        load(lua, "Features/Assignments/Solver.lua")
        lua.execute("""
            function member(class, caps, override, order)
                local ranking, excluded = ns.Buffs.SplitOrder(order or ns.Buffs.DEFAULT_ORDER[class])
                return {class=class, group=1, caps=caps or {}, ranking=ranking,
                    excluded=excluded, wants=ns.Buffs.DefaultWants(class), blessingsOverride=override}
            end
            all = {KINGS=true, MIGHT=true, SALV=true, WISDOM=true, LIGHT=true, SANCT=true}
        """)
        lua.execute(code)

    def core_runtime(self, player_class="PALADIN"):
        lua = runtime()
        lua.execute((ROOT / "tests/wow_mock.lua").read_text(encoding="utf-8"))
        lua.globals().PLAYER_CLASS = player_class
        for name in (
            "App/State.lua", "Shared/Events.lua", "Shared/WoW.lua", "Features/Buffs/Catalog.lua",
            "Shared/UI.lua", "Features/Sync/Protocol.lua", "Features/Tracker/Status.lua",
            "App/Database.lua", "Features/Preferences/Model.lua", "Features/Roster/Roster.lua",
            "Features/Assignments/Solver.lua", "Features/Assignments/Assignments.lua",
            "Features/Paladins/Plan.lua", "App/Bootstrap.lua",
        ):
            load(lua, name)
        lua.execute("ns.Comm = {Announce=function() end, Send=function() end}; ns.Roster.Capabilities = function() return {KINGS=true,MIGHT=true,SALV=true,WISDOM=true} end")
        return lua

    def test_saved_custom_rankings_migrate_and_can_opt_out(self):
        lua = self.core_runtime("ROGUE")
        lua.execute("""
            BuffeteriaCharDB = {order={'SALV','MIGHT','KINGS','LIGHT','SANCT','|','WISDOM'}}
            ns.App:GetScript('OnEvent')(ns.App, 'ADDON_LOADED', 'Buffeteria')
            assert(ns.db.blessingsOverride)
            assert(ns.Roster.Build().members['A-Realm'].ranking[1] == 'SALV')
            ns.db.blessingsOverride = false
            assert(ns.Roster.Build().members['A-Realm'].ranking[1] == 'KINGS')
            assert(ns.db.order[1] == 'SALV') -- preserve the order for re-enabling
            ns.Roster.peers['B-Realm'] = {caps={KINGS=true},ranking={'SALV'},excluded={},wants={},blessingsOverride=true}
            assert(ns.Roster.Build().members['B-Realm'].blessingsOverride)
            ns.Roster.peers['B-Realm'].blessingsOverride = false
            assert(ns.Roster.Build().members['B-Realm'].ranking[1] == 'KINGS')
            BuffeteriaCharDB = {}
            ns.App:GetScript('OnEvent')(ns.App, 'ADDON_LOADED', 'Buffeteria')
            assert(not ns.db.blessingsOverride)
        """)

    def test_paladin_editor_and_settings_share_controls(self):
        lua = self.core_runtime()
        lua.execute("""
            ns.App:GetScript('OnEvent')(ns.App, 'ADDON_LOADED', 'Buffeteria')
            ns.Paladins.Init(); ns.roster = ns.Roster.Build(); ns.result = ns.Solver.Solve(ns.roster)
            ns.Preview = {active=false}; ns.Tracker = {Refresh=function() end}
        """)
        for name in ("Features/Preferences/View.lua", "Features/Paladins/View.lua", "Features/Options/Window.lua"):
            load(lua, name)
        lua.execute("""
            ns.Options.Toggle()
            local tab = findWidget('Paladins')
            assert(tab:IsVisible())
            tab:GetScript('OnClick')(tab)
            local heading = findWidget('Class blessing assignments')
            assert(heading:IsVisible())
            local columns = heading.parent.columns
            assert(#columns == 2 and columns[1].paladin == 'A-Realm' and columns[2].paladin == 'B-Realm')
            local rows = 0
            for _, w in pairs(columns[1].rows) do
                rows = rows + 1
                w:GetScript('OnClick')(w, 'RightButton') -- Auto -> None
            end
            assert(rows == 9)
            runTimers()
            for _, class in ipairs(ns.Buffs.CLASS_KEYS) do assert(ns.Paladins.Get('A-Realm',class) == 'NONE') end
            assert(ns.Paladins.Get('B-Realm', 'ROGUE') == 'AUTO')
            ns.Options.RegisterSettings()
            settingsPage:GetScript('OnShow')(settingsPage)
            assert(heading:IsVisible() and not Buffeteria_Prefs:IsShown())
            ns.Options.Toggle()
            assert(heading:IsVisible() and Buffeteria_Prefs:IsShown())
            local mine = findWidget('My preferences'); mine:GetScript('OnClick')(mine)
            assert(not heading:IsVisible())
            local override = findWidget('Override the Paladins class plan').parent
            override:SetChecked(true); override:GetScript('OnClick')(override)
            assert(ns.db.blessingsOverride)
        """)

    def test_paladin_columns_follow_roster_and_scroll_in_both_hosts(self):
        lua = full_addon()
        lua.execute("""
            ns.Options.Toggle()
            local tab = findWidget('Paladins'); tab:GetScript('OnClick')(tab)
            local panel = findWidget('Class blessing assignments').parent
            assert(#panel.columns == 2 and Buffeteria_Prefs:GetWidth() == 534)
            assert(not panel.scrollbar:IsShown())
            -- Add paladins through the real roster -> solver -> refresh event path.
            function UnitFullName(unit)
                if unit == 'player' then return 'A', 'Realm' end
                return 'Party' .. unit:match('%d+'), 'Realm'
            end
            GROUP_SIZE = 2
            ns.Assignments.Resolve(); runTimers()
            assert(#panel.columns == 3 and Buffeteria_Prefs:GetWidth() == 788)
            assert(panel.columns[2].paladin == 'Party1-Realm')
            assert(panel.columns[3].paladin == 'Party2-Realm')
            -- Screen width caps the host without dropping any columns.
            UIParent:SetWidth(900); GROUP_SIZE = 9
            ns.Assignments.Resolve(); runTimers()
            assert(#panel.columns == 10 and Buffeteria_Prefs:GetWidth() == 852)
            assert(panel.scrollbar:IsShown())
            for _, column in ipairs(panel.columns) do assert(column:IsVisible()) end
            panel.viewport:GetScript('OnMouseWheel')(panel.viewport, -1)
            assert(panel.viewport.horizontalScroll > 0)
            panel.scrollbar:SetValue(panel.scrollbar.maximum)
            assert(panel.viewport.horizontalScroll == panel.scrollbar.maximum)
            -- Settings uses the same controls, capped to its own available width.
            settingsPage:SetSize(650, 800)
            settingsPage:GetScript('OnShow')(settingsPage)
            assert(panel:GetParent():GetParent() == settingsPage)
            assert(panel:GetParent():GetWidth() == 618 and panel.scrollbar:IsShown())
            settingsPage:SetWidth(800); settingsPage:GetScript('OnSizeChanged')(settingsPage)
            assert(panel:GetParent():GetWidth() == 768)
            -- Remove everyone else: the host shrinks and stale columns stop accepting edits.
            GROUP_SIZE = 0
            ns.Assignments.Resolve(); runTimers()
            assert(panel.columns[1].paladin == 'A-Realm')
            assert(panel:GetParent():GetWidth() == 340 and not panel.scrollbar:IsShown())
            assert(panel.viewport.horizontalScroll == 0)
            for i = 2, #panel.columns do
                assert(not panel.columns[i]:IsShown() and panel.columns[i].paladin == nil)
            end
            ns.Options.Toggle()
            assert(Buffeteria_Prefs:GetWidth() == 340)
            GROUP_SIZE = 2
            ns.Assignments.Resolve(); runTimers()
            assert(Buffeteria_Prefs:GetWidth() == 788)
            local mine = findWidget('My preferences'); mine:GetScript('OnClick')(mine)
            assert(Buffeteria_Prefs:GetWidth() == 340 and not panel:IsVisible())
        """)

    def test_each_paladin_column_edits_its_own_capabilities_and_handles_empty_roster(self):
        lua = full_addon()
        lua.execute("""
            ns.Options.Toggle()
            local tab = findWidget('Paladins'); tab:GetScript('OnClick')(tab)
            local panel = findWidget('Class blessing assignments').parent
            ns.roster.members['A-Realm'].caps = {WISDOM=true}
            ns.roster.members['B-Realm'].hasAddon = false
            ns.Events.Emit('AssignmentsChanged')
            local a, b = panel.columns[1].rows.ROGUE, panel.columns[2].rows.ROGUE
            a:GetScript('OnClick')(a, 'LeftButton')
            assert(ns.Paladins.Get('A-Realm', 'ROGUE') == 'WISDOM')
            assert(ns.Paladins.Get('B-Realm', 'ROGUE') == 'AUTO')
            b:GetScript('OnClick')(b, 'LeftButton')
            assert(ns.Paladins.Get('B-Realm', 'ROGUE') == 'KINGS')
            a:GetScript('OnEnter')(a)
            assert(GameTooltip:GetText() == 'A - ROGUE')
            a:GetScript('OnLeave')(a); assert(not GameTooltip:IsShown())
            ns.roster.members = {}
            ns.Events.Emit('AssignmentsChanged')
            assert(findWidget('No paladins in the group'):IsVisible())
            for _, column in ipairs(panel.columns) do assert(not column:IsShown()) end
            -- Pooled controls cannot edit a departed paladin.
            b:GetScript('OnClick')(b, 'LeftButton')
            assert(ns.Paladins.Get('B-Realm', 'ROGUE') == 'KINGS')
            assert(Buffeteria_Prefs:GetWidth() == 340)
        """)

    def test_non_paladins_do_not_see_assignment_tab(self):
        lua = self.core_runtime("ROGUE")
        lua.execute("""
            ns.App:GetScript('OnEvent')(ns.App, 'ADDON_LOADED', 'Buffeteria')
            ns.roster = ns.Roster.Build(); ns.Preview = {active=false}
        """)
        for name in ("Features/Preferences/View.lua", "Features/Paladins/View.lua", "Features/Options/Window.lua"):
            load(lua, name)
        lua.execute("ns.Options.Toggle(); assert(not findWidget('Paladins'):IsVisible())")

    def test_manual_plan_and_opt_in_priority(self):
        self.solver("""
            local roster = {members={Pal=member('PALADIN', all),
                Offline=member('ROGUE'), Default=member('ROGUE', {}, false),
                Custom=member('ROGUE', {}, true)}, paladinAssignments={ROGUE={Pal='SALV'}}}
            local r = ns.Solver.Solve(roster)
            assert(r.pally.ROGUE.Pal == 'SALV')
            assert(r.expected.Offline.SALV == 'Pal' and r.expected.Default.SALV == 'Pal')
            assert(r.expected.Custom.KINGS == 'Pal' and r.expected.Custom.SALV == nil)
            assert(r.overrides.Custom.Pal == 'KINGS')
        """)

    def test_manual_plan_can_override_class_default_exclusion(self):
        self.solver("""
            local r = ns.Solver.Solve({members={Pal=member('PALADIN', all), Rogue=member('ROGUE')},
                paladinAssignments={ROGUE={Pal='WISDOM'}}})
            assert(r.expected.Rogue.WISDOM == 'Pal' and not r.overrides.Rogue)
        """)

    def test_auto_slots_do_not_duplicate_manual_blessings(self):
        self.solver("""
            local r = ns.Solver.Solve({members={A=member('PALADIN', all), B=member('PALADIN', all),
                Rogue=member('ROGUE')}, paladinAssignments={ROGUE={A='MIGHT'}}})
            assert(r.pally.ROGUE.A == 'MIGHT' and r.pally.ROGUE.B == 'KINGS')
        """)

    def test_none_and_custom_exclusions(self):
        self.solver("""
            local roster = {members={A=member('PALADIN', all), B=member('PALADIN', all),
                Rogue=member('ROGUE'), Tank=member('WARRIOR', {}, true, {'KINGS','MIGHT','|','SALV'})},
                paladinAssignments={ROGUE={A='NONE', B='NONE'}, WARRIOR={A='SALV', B='NONE'}}}
            local r = ns.Solver.Solve(roster)
            assert(next(r.expected.Rogue) == nil)
            assert(r.expected.Tank.KINGS and r.expected.Tank.MIGHT and not r.expected.Tank.SALV)
            assert(r.overrides.Tank.A and r.overrides.Tank.B)
            roster.members.Tank.ranking = {}; roster.members.Tank.excluded = all
            r = ns.Solver.Solve(roster)
            assert(next(r.expected.Tank) == nil and r.overrides.Tank.A == false)
        """)

    def test_scarce_spells_and_group_buffs(self):
        self.solver("""
            local r = ns.Solver.Solve({members={A=member('PALADIN', {KINGS=true}),
                B=member('PALADIN', {MIGHT=true}), R=member('ROGUE', {}, true),
                Priest=member('PRIEST', {FORT=true})}, paladinAssignments={ROGUE={A='NONE', B='NONE'}}})
            assert(r.expected.R.KINGS == 'A' and r.expected.R.MIGHT == 'B')
            assert(r.expected.R.FORT == 'Priest')
        """)

    def plan_runtime(self):
        lua = runtime()
        load(lua, "Features/Buffs/Catalog.lua")
        lua.execute("ns.WoW = {}; ns.Preferences = {}; ns.Roster = {}; ns.Assignments = {}")
        load(lua, "Shared/Events.lua")
        load(lua, "Features/Sync/Protocol.lua")
        load(lua, "Features/Tracker/Status.lua")
        lua.execute("""
            function time() return 1000 end
            function UnitClass() return 'Paladin','PALADIN' end
            ns.WoW.FullName = function() return 'A-Realm' end
            ns.db = {paladinBlessings={}}
            ns.Assignments.Resolve = function() ns.solves = (ns.solves or 0) + 1 end
            ns.roster = {members={['A-Realm']={class='PALADIN', hasAddon=true, caps={KINGS=true,MIGHT=true}},
                ['B-Realm']={class='PALADIN', hasAddon=true, caps={KINGS=true,MIGHT=true}},
                ['C-Realm']={class='PALADIN', caps={}}, ['R-Realm']={class='ROGUE', caps={}}}}
            ns.Roster.Build = function() return ns.roster end
            sent = {}; ns.Comm = {Send=function(msg) table.insert(sent,msg) end}
        """)
        load(lua, "Features/Paladins/Plan.lua")
        return lua

    def test_shared_edits_capabilities_and_persistence(self):
        lua = self.plan_runtime()
        lua.execute("""
            ns.Paladins.Set('A-Realm', 'ROGUE', 'KINGS')
            assert(ns.db.paladinBlessings.ROGUE == 'KINGS')
            ns.Paladins.Set('B-Realm', 'ROGUE', 'KINGS')
            assert(ns.Paladins.Get('A-Realm', 'ROGUE') == 'NONE')
            ns.Paladins.Set('B-Realm', 'ROGUE', 'SANCT')
            assert(ns.Paladins.Get('B-Realm', 'ROGUE') == 'KINGS')
            ns.Paladins.Set('C-Realm', 'ROGUE', 'SANCT')
            assert(ns.Paladins.Assignments(ns.roster).ROGUE['C-Realm'] == 'SANCT')
            assert(ns.roster.members['C-Realm'].caps.SANCT)
            ns.Paladins.Set('A-Realm', 'ROGUE', 'AUTO')
            assert(ns.db.paladinBlessings.ROGUE == 'AUTO')
            for _, msg in ipairs(sent) do assert(#msg <= 255) end
            ns.db.paladinBlessings.WARRIOR = 'MIGHT'; ns.Paladins.Init()
            assert(ns.Paladins.Get('A-Realm','WARRIOR') == 'MIGHT')
        """)

    def test_reload_advances_clock_and_preserves_auto(self):
        lua = self.plan_runtime()
        lua.execute("""
            ns.Paladins.Set('A-Realm', 'ROGUE', 'KINGS')
            ns.Paladins.Set('A-Realm', 'ROGUE', 'AUTO')
            oldRevision = ns.Paladins.revision
        """)
        load(lua, "Features/Paladins/Plan.lua")
        lua.execute("""
            ns.Paladins.Init()
            assert(ns.Paladins.revision > oldRevision)
            assert(ns.Paladins.cells['A-Realm'].ROGUE.key == 'AUTO')
            ns.Paladins.Set('A-Realm', 'ROGUE', 'MIGHT')
            assert(ns.Paladins.cells['A-Realm'].ROGUE.revision > oldRevision)
        """)

    def test_simultaneous_duplicate_slots_have_one_winner(self):
        lua = self.plan_runtime()
        lua.execute("""
            local a = ns.Paladins
            a.Receive('A-Realm', 'A-Realm', '2', 'KINGS', '2000', 'A-Realm')
            a.Receive('B-Realm', 'B-Realm', '2', 'KINGS', '2000', 'B-Realm')
            local assignments = a.Assignments(ns.roster)
            assert(assignments.ROGUE['A-Realm'] == 'NONE' and assignments.ROGUE['B-Realm'] == 'KINGS')
            a.cells = {}
            a.Receive('B-Realm', 'B-Realm', '2', 'KINGS', '2000', 'B-Realm')
            a.Receive('A-Realm', 'A-Realm', '2', 'KINGS', '2000', 'A-Realm')
            assignments = a.Assignments(ns.roster)
            assert(assignments.ROGUE['A-Realm'] == 'NONE' and assignments.ROGUE['B-Realm'] == 'KINGS')
        """)

    def test_register_convergence_and_invalid_messages(self):
        lua = self.plan_runtime()
        lua.execute("""
            local a = ns.Paladins
            a.Receive('B-Realm', 'A-Realm', '2', 'MIGHT', '2000', 'B-Realm')
            a.Receive('B-Realm', 'A-Realm', '2', 'KINGS', '2000', 'A-Realm')
            assert(a.Get('A-Realm','ROGUE') == 'MIGHT')
            a.cells = {}
            a.Receive('B-Realm', 'A-Realm', '2', 'KINGS', '2000', 'A-Realm')
            a.Receive('B-Realm', 'A-Realm', '2', 'MIGHT', '2000', 'B-Realm')
            assert(a.Get('A-Realm','ROGUE') == 'MIGHT')
            a.Receive('R-Realm', 'A-Realm', '2', 'KINGS', '3000', 'R-Realm')
            a.Receive('B-Realm', 'A-Realm', '99', 'KINGS', '3000', 'B-Realm')
            a.Receive('B-Realm', 'A-Realm', '2', 'FORT', '3000', 'B-Realm')
            a.Receive('B-Realm', 'A-Realm', '2', 'KINGS', '-1', 'B-Realm')
            assert(a.Get('A-Realm','ROGUE') == 'MIGHT')
            ns.roster.members['B-Realm'] = nil; a.Prune(ns.roster)
            assert(a.Get('A-Realm','ROGUE') == 'MIGHT') -- editor leaving keeps the plan
            a.Set('A-Realm','ROGUE','KINGS')
            assert(a.Get('A-Realm','ROGUE') == 'KINGS') -- observed clock advances
            ns.roster.members['A-Realm'] = nil; a.Prune(ns.roster)
            assert(a.Get('A-Realm','ROGUE') == 'AUTO')
        """)

    def test_message_retry_keeps_every_cell_and_latest_state(self):
        lua = self.plan_runtime()
        lua.execute("""
            ns.Preferences.Get = function() return {wants={},ranking={'KINGS'},excluded={},blessingsOverride=true} end
            ns.Roster.Capabilities = function() return {KINGS=true} end
            ns.WoW.Short = function(n) return n end; ns.WoW.Print = function() end
            ns.Roster.peers = {}
            function IsInGroup(category) return category == nil end
            function IsInRaid() return false end
            function GetTime() return 100 end
            function strsplit(sep, str)
                local out = {}; for part in (str..sep):gmatch('(.-)'..sep) do out[#out+1]=part end
                return unpack(out)
            end
            throttled = true; delivered = {}
            C_ChatInfo = {SendAddonMessage=function(_, msg)
                if throttled then return false end
                table.insert(delivered, msg); return 0
            end}
        """)
        load(lua, "Features/Sync/Comm.lua")
        lua.execute("""
            ns.Comm.Send('P|2|A-Realm|1|KINGS|1|A-Realm')
            ns.Comm.Send('P|2|A-Realm|2|MIGHT|2|A-Realm')
            ns.Comm.Send('P|2|A-Realm|1|NONE|3|A-Realm')
            ns.Comm.Send('S|2|||||0'); ns.Comm.Send('S|2|||||1')
            ns.Comm.Flush(); assert(#delivered == 0)
            throttled = false; ns.Comm.Flush(); assert(#delivered == 3)
            assert(delivered[1] == 'P|2|A-Realm|1|NONE|3|A-Realm')
            assert(delivered[2] == 'P|2|A-Realm|2|MIGHT|2|A-Realm')
            assert(delivered[3] == 'S|2|||||1')
            ns.Comm.OnMessage('BUFFETERIA','S|2|FORT|MIGHT||MIGHT|1','PARTY','B-Realm')
            assert(ns.Roster.peers['B-Realm'].blessingsOverride and ns.Roster.peers['B-Realm'].caps.MIGHT)
            ns.Comm.OnMessage('BUFFETERIA','P|2|A-Realm|2|KINGS|3000|B-Realm','PARTY','B-Realm')
            assert(ns.Paladins.Get('A-Realm','ROGUE') == 'KINGS')
        """)

    def test_tracker_uses_singles_around_personal_overrides(self):
        lua = runtime()
        load(lua, "Features/Buffs/Catalog.lua")
        lua.execute("ns.WoW = {}; ns.Preferences = {}; ns.Roster = {}; ns.Assignments = {}")
        load(lua, "Shared/Events.lua")
        load(lua, "Features/Sync/Protocol.lua")
        load(lua, "Features/Tracker/Status.lua")
        lua.execute("""
            function GetTime() return 100 end
            function UnitIsVisible() return true end
            C_UnitAuras = {GetAuraDataByIndex=function() return nil end}
            ns.WoW.FullName = function() return 'Pal' end; ns.WoW.Short = function(n) return n end
            ns.WoW.ClassName = function(c) return c end
            ns.WoW.SpellName = function(id) return tostring(id) end
            ns.WoW.SpellIcon = function(id) return id end
            ns.WoW.KnowsAny = function(ids) return true, ids[#ids] end
            ns.WoW.ItemCount = function() return 10 end
            ns.db = {warnMinutes=5}
            ns.roster = {members={R={class='ROGUE',unit='party1'}, C={class='ROGUE',unit='party2'}},
                units={R='party1', C='party2'}}
            ns.result = {groups={}, pally={ROGUE={Pal='KINGS'}},
                expected={R={KINGS='Pal'}, C={MIGHT='Pal'}}, overrides={C={Pal='MIGHT'}}}
        """)
        load(lua, "Features/Tracker/Scan.lua")
        load(lua, "Features/Tracker/Actions.lua")
        lua.execute("""
            local summary = ns.Scan.Update()
            assert(summary.next and not summary.next.big)
            assert(summary.next.spell == '20217')
            ns.result.overrides = {}; ns.result.expected.C = {KINGS='Pal'}
            summary = ns.Scan.Update()
            assert(summary.next.big and summary.next.spell == '25898')
            ns.result.overrides = {C={Pal=false}}; ns.result.expected.C = {}
            assert(not ns.Scan.Update().next.big)
            ns.WoW.FullName = function() return 'R' end
            ns.roster.members.R.excluded = {WISDOM=true}
            ns.result.expected.R = {WISDOM='Pal'}
            C_UnitAuras.GetAuraDataByIndex = function(_, i)
                if i == 1 then return {name='25290', expirationTime=0} end
            end
            summary = ns.Scan.Update()
            assert(not summary.cancel and not ns.Scan.UnwantedOnMe())
            for _, problem in ipairs(summary.problems) do assert(problem.status ~= 'unwanted') end
            ns.result.expected.R = {}
            assert(ns.Scan.UnwantedOnMe() == '25290')
        """)


if __name__ == "__main__":
    unittest.main()
