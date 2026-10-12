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


class AddonTests(unittest.TestCase):
    def test_lua51_syntax(self):
        lua = runtime()
        compile_lua = lua.eval("function(s,n) local f,e=loadstring(s,n); assert(f,e) end")
        for path in ROOT.glob("*.lua"):
            compile_lua(path.read_text(encoding="utf-8"), path.name)

    def solver(self, code):
        lua = runtime()
        load(lua, "Data.lua")
        load(lua, "Solver.lua")
        lua.execute("""
            function member(class, caps, override, order)
                local ranking, excluded = ns.Data.SplitOrder(order or ns.Data.DEFAULT_ORDER[class])
                return {class=class, group=1, caps=caps or {}, ranking=ranking,
                    excluded=excluded, wants=ns.Data.DefaultWants(class), blessingsOverride=override}
            end
            all = {KINGS=true, MIGHT=true, SALV=true, WISDOM=true, LIGHT=true, SANCT=true}
        """)
        lua.execute(code)

    def core_runtime(self, player_class="PALADIN"):
        lua = runtime()
        lua.execute((ROOT / "tests/wow_mock.lua").read_text(encoding="utf-8"))
        lua.globals().PLAYER_CLASS = player_class
        for name in ("Data.lua", "Solver.lua", "Core.lua", "Paladins.lua"):
            load(lua, name)
        lua.execute("ns.MyCaps = function() return {KINGS=true,MIGHT=true,SALV=true,WISDOM=true} end")
        return lua

    def test_saved_custom_rankings_migrate_and_can_opt_out(self):
        lua = self.core_runtime("ROGUE")
        lua.execute("""
            BuffeteriaCharDB = {order={'SALV','MIGHT','KINGS','LIGHT','SANCT','|','WISDOM'}}
            ns.Core:GetScript('OnEvent')(ns.Core, 'ADDON_LOADED', 'Buffeteria')
            assert(ns.db.blessingsOverride)
            assert(ns.BuildRoster().members['A-Realm'].ranking[1] == 'SALV')
            ns.db.blessingsOverride = false
            assert(ns.BuildRoster().members['A-Realm'].ranking[1] == 'KINGS')
            assert(ns.db.order[1] == 'SALV') -- preserve the order for re-enabling
            ns.peers['B-Realm'] = {caps={KINGS=true},ranking={'SALV'},excluded={},wants={},blessingsOverride=true}
            assert(ns.BuildRoster().members['B-Realm'].blessingsOverride)
            ns.peers['B-Realm'].blessingsOverride = false
            assert(ns.BuildRoster().members['B-Realm'].ranking[1] == 'KINGS')
            BuffeteriaCharDB = {}
            ns.Core:GetScript('OnEvent')(ns.Core, 'ADDON_LOADED', 'Buffeteria')
            assert(not ns.db.blessingsOverride)
        """)

    def test_paladin_editor_and_settings_share_controls(self):
        lua = self.core_runtime()
        lua.execute("""
            ns.Core:GetScript('OnEvent')(ns.Core, 'ADDON_LOADED', 'Buffeteria')
            ns.Paladins.Init(); ns.roster = ns.BuildRoster(); ns.result = ns.Solver.Solve(ns.roster)
            ns.Preview = {active=false}; ns.Tracker = {Refresh=function() end}
        """)
        load(lua, "Prefs.lua")
        lua.execute("""
            ns.Prefs.Toggle()
            local tab = findWidget('Paladins')
            assert(tab:IsVisible())
            tab:GetScript('OnClick')(tab)
            local heading = findWidget('Class blessing assignments')
            assert(heading:IsVisible())
            local rows = 0
            for _, w in ipairs(widgets) do
                if w.kind == 'Button' and w.parent == heading.parent and w:GetScript('OnClick')
                    and w.label ~= '<' and w.label ~= '>' and w.label ~= 'Announce to group' then
                    rows = rows + 1
                    w:GetScript('OnClick')(w, 'RightButton') -- Auto -> None
                end
            end
            assert(rows == 9)
            runTimers()
            for _, class in ipairs(ns.Data.CLASS_KEYS) do assert(ns.Paladins.Get('A-Realm',class) == 'NONE') end
            ns.Prefs.RegisterSettings()
            settingsPage:GetScript('OnShow')(settingsPage)
            assert(heading:IsVisible() and not Buffeteria_Prefs:IsShown())
            ns.Prefs.Toggle()
            assert(heading:IsVisible() and Buffeteria_Prefs:IsShown())
            local mine = findWidget('My preferences'); mine:GetScript('OnClick')(mine)
            assert(not heading:IsVisible())
            local override = findWidget('Override the Paladins class plan').parent
            override:SetChecked(true); override:GetScript('OnClick')(override)
            assert(ns.db.blessingsOverride)
        """)

    def test_non_paladins_do_not_see_assignment_tab(self):
        lua = self.core_runtime("ROGUE")
        lua.execute("""
            ns.Core:GetScript('OnEvent')(ns.Core, 'ADDON_LOADED', 'Buffeteria')
            ns.roster = ns.BuildRoster(); ns.Preview = {active=false}
        """)
        load(lua, "Prefs.lua")
        lua.execute("ns.Prefs.Toggle(); assert(not findWidget('Paladins'):IsVisible())")

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
        load(lua, "Data.lua")
        lua.execute("""
            function time() return 1000 end
            function UnitClass() return 'Paladin','PALADIN' end
            ns.FullName = function() return 'A-Realm' end
            ns.db = {paladinBlessings={}}
            ns.Resolve = function() ns.solves = (ns.solves or 0) + 1 end
            ns.roster = {members={['A-Realm']={class='PALADIN', hasAddon=true, caps={KINGS=true,MIGHT=true}},
                ['B-Realm']={class='PALADIN', hasAddon=true, caps={KINGS=true,MIGHT=true}},
                ['C-Realm']={class='PALADIN', caps={}}, ['R-Realm']={class='ROGUE', caps={}}}}
            ns.BuildRoster = function() return ns.roster end
            sent = {}; ns.Comm = {Send=function(msg) table.insert(sent,msg) end}
        """)
        load(lua, "Paladins.lua")
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
        load(lua, "Paladins.lua")
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
            ns.MyPrefs = function() return {wants={},ranking={'KINGS'},excluded={},blessingsOverride=true} end
            ns.MyCaps = function() return {KINGS=true} end
            ns.Short = function(n) return n end; ns.Print = function() end
            ns.peers = {}; ns.GetNormalizedRealmName = function() return 'Realm' end
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
        load(lua, "Comm.lua")
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
            assert(ns.peers['B-Realm'].blessingsOverride and ns.peers['B-Realm'].caps.MIGHT)
            ns.Comm.OnMessage('BUFFETERIA','P|2|A-Realm|2|KINGS|3000|B-Realm','PARTY','B-Realm')
            assert(ns.Paladins.Get('A-Realm','ROGUE') == 'KINGS')
        """)

    def test_tracker_uses_singles_around_personal_overrides(self):
        lua = runtime()
        load(lua, "Data.lua")
        lua.execute("""
            function GetTime() return 100 end
            function UnitIsVisible() return true end
            C_UnitAuras = {GetAuraDataByIndex=function() return nil end}
            ns.FullName = function() return 'Pal' end; ns.Short = function(n) return n end
            ns.ClassName = function(c) return c end
            ns.SpellName = function(id) return tostring(id) end
            ns.SpellIcon = function(id) return id end
            ns.KnowsAny = function(ids) return true, ids[#ids] end
            ns.ItemCount = function() return 10 end
            ns.db = {warnMinutes=5}
            ns.roster = {members={R={class='ROGUE',unit='party1'}, C={class='ROGUE',unit='party2'}},
                units={R='party1', C='party2'}}
            ns.result = {groups={}, pally={ROGUE={Pal='KINGS'}},
                expected={R={KINGS='Pal'}, C={MIGHT='Pal'}}, overrides={C={Pal='MIGHT'}}}
        """)
        load(lua, "Scan.lua")
        lua.execute("""
            local summary = ns.Scan.Update()
            assert(summary.next and not summary.next.big)
            assert(summary.next.spell == '20217')
            ns.result.overrides = {}; ns.result.expected.C = {KINGS='Pal'}
            summary = ns.Scan.Update()
            assert(summary.next.big and summary.next.spell == '25898')
            ns.result.overrides = {C={Pal=false}}; ns.result.expected.C = {}
            assert(not ns.Scan.Update().next.big)
            ns.FullName = function() return 'R' end
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
