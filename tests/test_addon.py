"""Run with python tests/test_addon.py (requires lupa with its Lua 5.1 runtime)."""
from pathlib import Path
import struct
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
    def test_smart_buff_grid_fits_edges_scale_and_drag_without_moving_head(self):
        lua = full_addon()
        lua.execute("""
            local frame, head = Buffeteria_Tracker, Buffeteria_CastButton
            local s = ns.Preview.Summary()
            ns.Scan.Update = function() return s end
            ns.db.buffDisplay = 'ALL'
            local headScale = 1
            head.GetEffectiveScale = function() return headScale end
            local function check(left, bottom, expectedDirection, minColumns)
                head.left, head.bottom, head.top = left, bottom, bottom + head:GetHeight()
                local oldPoint, oldHeight, oldWidth = frame.point, frame:GetHeight(), frame:GetWidth()
                ns.Tracker.Refresh()
                local count, xs = 0, {}
                local screenW, screenH = UIParent:GetWidth() / headScale, UIParent:GetHeight() / headScale
                for _, w in ipairs(widgets) do
                    if w.parent == frame and w.key and w.tex and w:IsShown() then
                        count = count + 1
                        assert(w.point[3] == expectedDirection)
                        local x = head.left + head:GetWidth() / 2 + w.point[4]
                        local y = (w.point[3] == 'TOP' and head.top or head.bottom) + w.point[5]
                        local low = w.point[1] == 'BOTTOMLEFT' and y or y - w:GetHeight()
                        assert(x >= 4 and x + w:GetWidth() <= screenW - 4)
                        assert(low >= 4 and low + w:GetHeight() <= screenH - 4)
                        xs[x] = true
                    end
                end
                local columns = 0; for _ in pairs(xs) do columns = columns + 1 end
                assert(count == 10 and columns >= (minColumns or 2))
                assert(frame.point == oldPoint and frame:GetHeight() == oldHeight and frame:GetWidth() == oldWidth)
            end
            check(800, 500, 'BOTTOM') -- normal placement
            check(800, 12, 'TOP') -- bottom edge, all rows above
            check(800, 1000, 'BOTTOM') -- top edge, all rows below
            ns.db.iconSize = 32; ns.Tracker.Refresh()
            check(2, 12, 'TOP') -- narrower head at bottom-left
            check(1886, 12, 'TOP') -- bottom-right
            check(2, 900, 'BOTTOM') -- top-left
            check(1886, 900, 'BOTTOM') -- top-right
            ns.db.iconSize = 64; ns.Tracker.Refresh()
            UIParent:SetSize(320, 200)
            check(120, 100, 'BOTTOM', 4) -- neither side fits two columns
            UIParent:SetSize(1920, 1080)
            headScale = 0.5
            check(3740, 12, 'TOP') -- coordinates after UI scaling
            headScale = 1
            -- The grid can change during combat; secure casting stays untouched.
            local spell, unit = head:GetAttribute('spell'), head:GetAttribute('unit')
            COMBAT = true
            check(800, 12, 'TOP')
            assert(head:GetAttribute('spell') == spell and head:GetAttribute('unit') == unit)
            COMBAT = false
            -- Ordinary dragging and Edit Mode both update before release.
            head:GetScript('OnDragStart')(head)
            head.left, head.bottom, head.top = 800, 500, 564
            frame:GetScript('OnUpdate')(frame)
            head.left, head.bottom, head.top = 800, 12, 76
            frame:GetScript('OnUpdate')(frame)
            for _, w in ipairs(widgets) do
                if w.parent == frame and w.key and w.tex and w:IsShown() then assert(w.point[3] == 'TOP') end
            end
            head:GetScript('OnDragStop')(head); runTimers()
            assert(not frame:GetScript('OnUpdate'))
            EventRegistry:TriggerEvent('EditMode.Enter')
            local overlay = frame.editOverlay
            overlay:GetScript('OnDragStart')(overlay)
            assert(frame:GetScript('OnUpdate'))
            frame:GetScript('OnUpdate')(frame)
            overlay:GetScript('OnDragStop')(overlay)
            assert(not frame:GetScript('OnUpdate'))
            EventRegistry:TriggerEvent('EditMode.Exit')
            -- Resolution/scale notifications also recalculate placement.
            head.left, head.bottom, head.top = 800, 500, 564
            frame:GetScript('OnEvent')(frame, 'UI_SCALE_CHANGED')
            for _, w in ipairs(widgets) do
                if w.parent == frame and w.key and w.tex and w:IsShown() then assert(w.point[3] == 'BOTTOM') end
            end
        """)

    def test_tracker_settings_migrate_and_validate_saved_display_options(self):
        lua = self.core_runtime()
        lua.execute("""
            for _, old in ipairs({true, false}) do
                BuffeteriaCharDB = {onlyProblems=old, iconSize=200}
                ns.Database.Init()
                assert(ns.db.buffDisplay == (old and 'PROBLEMS' or 'ALL'))
                assert(ns.db.iconSize == 128)
            end
            BuffeteriaCharDB = {onlyProblems=false, buffDisplay='MISSING', iconSize=16}
            ns.Database.Init()
            assert(ns.db.buffDisplay == 'MISSING' and ns.db.iconSize == 32)
            BuffeteriaCharDB = {buffDisplay='invalid', iconSize='invalid'}
            ns.Database.Init()
            assert(ns.db.buffDisplay == 'PROBLEMS' and ns.db.iconSize == 64)
        """)

    def test_settings_tab_for_every_class_and_shared_game_settings_controls(self):
        for player_class in ("PALADIN", "ROGUE"):
            with self.subTest(player_class=player_class):
                lua = full_addon(player_class)
                lua.execute("""
                    ns.Options.Toggle()
                    local tab = findWidget('Settings')
                    assert(tab:IsVisible() and not findWidget('Show tracker'):IsVisible())
                    tab:GetScript('OnClick')(tab)
                    assert(findWidget('Tracker settings'):IsVisible())
                    assert(not findWidget('Your buffet'):IsVisible())
                    assert(not findWidget('Blessings and auras'):IsVisible())
                    local show = findWidget('Show tracker').parent
                    show:SetChecked(false); show:GetScript('OnClick')(show)
                    assert(not ns.db.showTracker and not Buffeteria_Tracker:IsShown())
                    show:SetChecked(true); show:GetScript('OnClick')(show)
                    assert(ns.db.showTracker and Buffeteria_Tracker:IsShown())
                    local mode = findWidget('Missing only').parent
                    mode:GetScript('OnClick')(mode)
                    assert(ns.db.buffDisplay == 'MISSING' and mode:GetChecked())
                    assert(not findWidget('Missing or expiring').parent:GetChecked())
                    Buffeteria_IconSize:SetValue(96)
                    assert(ns.db.iconSize == 96 and Buffeteria_CastButton:GetWidth() == 96)
                    settingsPage:GetScript('OnShow')(settingsPage)
                    assert(findWidget('Tracker settings'):IsVisible())
                    assert(tab.parent.parent == settingsPage)
                    ns.Options.Toggle()
                    assert(tab.parent.parent == Buffeteria_Prefs)
                    local personal = findWidget('My preferences')
                    personal:GetScript('OnClick')(personal)
                    assert(findWidget('Your buffet'):IsVisible())
                    assert(not findWidget('Show tracker'):IsVisible())
                """)

    def test_display_filters_counts_and_fixed_head_do_not_change_cast_selection(self):
        lua = full_addon()
        lua.execute("""
            local frame, head = Buffeteria_Tracker, Buffeteria_CastButton
            local action = ns.Tracker.Summary().next
            local s = {any=true, overall='bad', problems={}, next=action, perKey={
                FORT={bad=1, warn=2, total=4}, INT={bad=0, warn=1, total=4},
                MOTW={bad=0, warn=0, total=4}, RFURY={bad=1, warn=0, total=1},
            }}
            ns.Scan.Update = function() return s end
            -- Cover center, bottom and top saved anchors: changing rows must
            -- never alter the frame's size or its anchor, keeping the face fixed.
            for _, anchor in ipairs({'CENTER', 'BOTTOM', 'TOPLEFT'}) do
                frame:SetPoint(anchor, UIParent, anchor, 37, -81)
                local height, width = frame:GetHeight(), frame:GetWidth()
                local expected = {
                    ALL={FORT=3, INT=1, MOTW='', RFURY=1},
                    MISSING={FORT=1, RFURY=1},
                    PROBLEMS={FORT=3, INT=1, RFURY=1},
                    EXPIRING={FORT=2, INT=1},
                }
                for _, mode in ipairs({'ALL', 'MISSING', 'PROBLEMS', 'EXPIRING'}) do
                    ns.db.buffDisplay = mode; ns.Tracker.Refresh()
                    local found = {}
                    for _, w in ipairs(widgets) do
                        if w.parent == frame and w.key and w.tex and w:IsShown() then
                            found[w.key] = w.count:GetText()
                            assert(w.point[2] == head and w.point[3] == 'BOTTOM' and w.point[5] < 0)
                        end
                    end
                    for key, count in pairs(expected[mode]) do assert(found[key] == count); found[key] = nil end
                    assert(not next(found))
                    assert(frame:GetHeight() == height and frame:GetWidth() == width)
                    assert(frame.point[1] == anchor and frame.point[4] == 37 and frame.point[5] == -81)
                    assert(head:GetAttribute('spell') == action.spell and head:GetAttribute('unit') == action.unit)
                end
            end
            s.perKey = {}; ns.Tracker.Refresh()
            assert(frame:GetHeight() == 80)
            ns.db.iconSize = 100
            COMBAT = true; ns.Tracker.Refresh()
            assert(head:GetWidth() == 64 and frame:GetWidth() == 68)
            COMBAT = false
            ns.App:GetScript('OnEvent')(ns.App, 'PLAYER_REGEN_ENABLED')
            assert(head:GetWidth() == 100 and frame:GetWidth() == 104)
        """)

    def test_orc_textures_have_matching_dimensions_and_real_transparency(self):
        for mood in ("Happy", "Grumpy", "Angry"):
            with self.subTest(mood=mood):
                data = (ROOT / "Media" / f"Orc{mood}.tga").read_bytes()
                image_type = data[2]
                width, height, depth, descriptor = struct.unpack_from("<HHBB", data, 12)
                self.assertEqual((image_type, width, height, depth), (2, 256, 256, 32))
                self.assertEqual(descriptor & 15, 8)
                start = 18 + data[0]
                alpha = data[start + 3:start + width * height * 4:4]
                self.assertEqual(len(alpha), width * height)
                self.assertIn(0, alpha)
                self.assertIn(255, alpha)
                for corner in (0, width - 1, (height - 1) * width, height * width - 1):
                    self.assertEqual(alpha[corner], 0)

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

    def test_orc_moods_distinguish_partial_empty_and_unreadable_buffs(self):
        lua = runtime()
        load(lua, "Features/Tracker/Status.lua")
        lua.execute("""
            local mood = ns.Status.Mood
            assert(mood({any = false, overall = 'idle', perKey = {}}) == 'idle')
            local s = {any = true, overall = 'bad', perKey = {
                FORT = {bad = 2, warn = 0, total = 2},
                INT = {bad = 1, warn = 0, total = 2},
            }}
            assert(mood(s) == 'grumpy') -- a missing buff is not an empty group
            s.perKey.INT.bad = 2
            assert(mood(s) == 'angry')
            s.perKey.INT = {bad = 1, warn = 0, total = 2, unknown = 1}
            assert(mood(s) == 'grumpy') -- unreadable is not missing
            s.overall = 'ok'
            s.perKey = {FORT = {bad = 0, warn = 0, total = 2, unknown = 2}}
            assert(mood(s) == 'grumpy') -- unreadable is not fully buffed
            s.perKey.FORT.unknown = 0
            assert(mood(s) == 'happy')
            s.overall = 'warn'; s.perKey.FORT.warn = 1
            assert(mood(s) == 'grumpy')
        """)

    def test_preview_cycles_orc_artwork_without_casting_and_updates_in_combat(self):
        lua = full_addon()
        lua.execute("""
            ns.Preview.Set(true)
            local expected = {'Angry', 'Grumpy', 'Grumpy', 'Happy'}
            for phase, suffix in ipairs(expected) do
                WOW_TIME = 100 + (phase - 1) * 5
                ns.Tracker.Refresh()
                assert(Buffeteria_CastButton.icon.texture ==
                    'Interface\\\\AddOns\\\\Buffeteria\\\\Media\\\\Orc' .. suffix)
                assert(not Buffeteria_CastButton.icon.desaturated)
                assert(not Buffeteria_CastButton:GetAttribute('spell'))
                assert(not Buffeteria_CastButton:GetAttribute('unit'))
            end
            COMBAT = true
            WOW_TIME = 120
            ns.Tracker.Refresh()
            assert(Buffeteria_CastButton.icon.texture:find('OrcAngry$'))
            assert(not Buffeteria_CastButton:GetAttribute('spell'))
            COMBAT = false
            ns.Preview.Set(false)
        """)

    def test_unreadable_observations_keep_orc_grumpy(self):
        lua = full_addon(login=False)
        lua.execute("""
            UnitIsVisible = function() return false end
            ns.App:GetScript('OnEvent')(ns.App, 'PLAYER_LOGIN'); runTimers()
            assert(ns.Tracker.Summary().any)
            assert(ns.Status.Mood(ns.Tracker.Summary()) == 'grumpy')
            assert(Buffeteria_CastButton.icon.texture:find('OrcGrumpy$'))
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
            assert(not Buffeteria_Prefs or not Buffeteria_Prefs:IsShown())
            overlay:GetScript('OnMouseDown')(overlay)
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

    def test_tracker_release_click_and_drag_suppression(self):
        lua = full_addon()
        lua.execute("""
            local button = Buffeteria_CastButton
            assert(table.concat(button.clicks, ',') == 'LeftButtonUp,RightButtonUp')
            assert(button:GetAttribute('useOnKeyDown') == false)
            assert(not button.pushedTexture)
            local casts, toggles = 0, 0
            ns.Actions.MarkCast = function() casts = casts + 1 end
            ns.Options.Toggle = function() toggles = toggles + 1 end
            button:GetScript('OnMouseDown')(button)
            assert(button.icon.vertexColor[1] == 0.75)
            button:GetScript('PostClick')(button, 'LeftButton', true)
            assert(casts == 0)
            button:GetScript('OnMouseUp')(button)
            button:GetScript('PostClick')(button, 'LeftButton', false)
            assert(casts == 1 and button.icon.vertexColor[1] == 1)
            runTimers()
            for _, stopFirst in ipairs({true, false}) do
                button:GetScript('OnMouseDown')(button)
                button:GetScript('OnDragStart')(button)
                assert(Buffeteria_Tracker.moving and button:GetAttribute('*type1') == '')
                assert(button.icon.vertexColor[1] == 1)
                ns.Tracker.Refresh() -- periodic refresh must not re-enable a drag's cast
                assert(button:GetAttribute('*type1') == '')
                if stopFirst then button:GetScript('OnDragStop')(button) end
                button:GetScript('PostClick')(button, 'LeftButton', false)
                button:GetScript('PostClick')(button, 'RightButton', false)
                assert(casts == 1 and toggles == 0)
                if not stopFirst then button:GetScript('OnDragStop')(button) end
                runTimers()
                assert(not Buffeteria_Tracker.moving and not button:GetAttribute('*type1'))
            end
            button:GetScript('OnMouseDown')(button)
            button:GetScript('OnDragStart')(button)
            button:GetScript('OnDragStop')(button)
            COMBAT = true
            runTimers() -- no protected attribute write when combat interrupts a drag
            assert(button:GetAttribute('*type1') == '')
            COMBAT = false
            ns.App:GetScript('OnEvent')(ns.App, 'PLAYER_REGEN_ENABLED')
            assert(not button:GetAttribute('*type1'))
            ns.db.locked = true
            button:GetScript('OnMouseDown')(button)
            button:GetScript('OnDragStart')(button)
            assert(not Buffeteria_Tracker.moving and not button:GetAttribute('*type1'))
            button:GetScript('PostClick')(button, 'RightButton', false)
            assert(toggles == 1)
            button:GetScript('OnMouseDown')(button)
            button:GetScript('PostClick')(button, 'LeftButton', false)
            assert(casts == 2)
            button:GetScript('OnLeave')(button)
            assert(button.icon.vertexColor[1] == 1)
        """)

    def test_minimap_drag_does_not_click_or_announce(self):
        lua = full_addon()
        lua.execute("""
            local button = Buffeteria_MinimapButton
            local toggles, announcements = 0, 0
            ns.Options.Toggle = function() toggles = toggles + 1 end
            ns.Assignments.Announce = function() announcements = announcements + 1 end
            local visible = ns.db.showTracker
            button:GetScript('OnMouseDown')(button)
            button:GetScript('OnDragStart')(button)
            assert(button:GetScript('OnUpdate'))
            button:GetScript('OnDragStop')(button)
            assert(not button:GetScript('OnUpdate'))
            button:GetScript('OnMouseUp')(button)
            button:GetScript('OnClick')(button, 'LeftButton')
            button:GetScript('OnClick')(button, 'RightButton')
            IsShiftKeyDown = function() return true end
            button:GetScript('OnClick')(button, 'LeftButton')
            assert(toggles == 0 and announcements == 0 and ns.db.showTracker == visible)
            button:GetScript('OnMouseDown')(button)
            button:GetScript('OnClick')(button, 'LeftButton')
            assert(announcements == 1)
            IsShiftKeyDown = function() return false end
            button:GetScript('OnMouseDown')(button)
            button:GetScript('OnMouseUp')(button)
            button:GetScript('OnClick')(button, 'LeftButton')
            assert(toggles == 1 and button.icon.vertexColor[1] == 1)
            button:GetScript('OnMouseDown')(button)
            button:GetScript('OnClick')(button, 'RightButton')
            assert(ns.db.showTracker ~= visible)
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
        for name in ("Features/Tracker/View.lua", "Features/Preferences/View.lua", "Features/Paladins/View.lua", "Features/Options/Window.lua"):
            load(lua, name)
        lua.execute("""
            ns.Options.Toggle()
            local tab = findWidget('Paladins')
            assert(tab:IsVisible())
            tab:GetScript('OnClick')(tab)
            local heading = findWidget('Blessings and auras')
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
            -- Wanted buffs are talent buttons: gold when wanted, grey when not.
            local fort = findWidget('Your buffet').parent.wants.FORT
            local wanted = ns.db.wants.FORT and true or false
            fort:GetScript('OnClick')(fort)
            assert((ns.db.wants.FORT and true or false) == not wanted)
            assert(fort.state == (wanted and 'grey' or 'gold'))
            -- The third tree now hosts role-based tank requests.
            assert(findWidget('Tanks'):IsVisible())
            local panel = findWidget('Your buffet').parent
            assert(panel.tankButtons.RFURY:IsShown() and panel.tankButtons.THORNS:IsShown())
            panel.tankRole:GetScript('OnClick')(); runTimers()
            assert(ns.db.tankRole == 'TANK' and ns.Preferences.Get().wants.RFURY)
        """)

    def test_paladin_columns_follow_roster_and_scroll_in_both_hosts(self):
        lua = full_addon()
        lua.execute("""
            ns.Options.Toggle()
            local tab = findWidget('Paladins'); tab:GetScript('OnClick')(tab)
            local panel = findWidget('Blessings and auras').parent
            local function shownSeats()
                local n = 0
                for _, seat in ipairs(panel.seats) do if seat:IsShown() then n = n + 1 end end
                return n
            end
            -- Paladins share the board: two paladins get half of it each, no empty seats.
            assert(#panel.columns == 2 and shownSeats() == 0 and Buffeteria_Prefs:GetWidth() == 652)
            assert(panel.columns[1].width == 317 and panel.columns[2].width == 317)
            assert(not panel.scrollbar:IsShown())
            -- Add paladins through the real roster -> solver -> refresh event path.
            function UnitFullName(unit)
                if unit == 'player' then return 'A', 'Realm' end
                return 'Party' .. unit:match('%d+'), 'Realm'
            end
            GROUP_SIZE = 2
            ns.Assignments.Resolve(); runTimers()
            assert(#panel.columns == 3 and shownSeats() == 0 and Buffeteria_Prefs:GetWidth() == 652)
            assert(panel.columns[1].width == 210)
            assert(panel.columns[2].paladin == 'Party1-Realm')
            assert(panel.columns[3].paladin == 'Party2-Realm')
            assert(not panel.scrollbar:IsShown())
            -- More paladins than trees scroll horizontally without dropping any columns.
            GROUP_SIZE = 9
            ns.Assignments.Resolve(); runTimers()
            assert(#panel.columns == 10 and Buffeteria_Prefs:GetWidth() == 652)
            assert(panel.scrollbar:IsShown())
            for _, column in ipairs(panel.columns) do assert(column:IsVisible()) end
            panel.viewport:GetScript('OnMouseWheel')(panel.viewport, -1)
            assert(panel.viewport.horizontalScroll > 0)
            panel.scrollbar:SetValue(panel.scrollbar.maximum)
            assert(panel.viewport.horizontalScroll == panel.scrollbar.maximum)
            -- Settings uses the same controls, sized to its own available width.
            settingsPage:SetSize(650, 800)
            settingsPage:GetScript('OnShow')(settingsPage)
            assert(panel:GetParent():GetParent() == settingsPage)
            assert(panel:GetParent():GetWidth() == 618 and panel.scrollbar:IsShown())
            settingsPage:SetWidth(800); settingsPage:GetScript('OnSizeChanged')(settingsPage)
            assert(panel:GetParent():GetWidth() == 768)
            -- Remove everyone else: one tree fills the board and stale columns stop accepting edits.
            GROUP_SIZE = 0
            ns.Assignments.Resolve(); runTimers()
            assert(panel.columns[1].paladin == 'A-Realm' and shownSeats() == 0)
            assert(panel.columns[1].width == panel:GetParent():GetWidth() - 16)
            assert(not panel.scrollbar:IsShown())
            assert(panel.viewport.horizontalScroll == 0)
            for i = 2, #panel.columns do
                assert(not panel.columns[i]:IsShown() and panel.columns[i].paladin == nil)
            end
            ns.Options.Toggle()
            assert(Buffeteria_Prefs:GetWidth() == 652 and panel:GetParent():GetWidth() == 652)
            local mine = findWidget('My preferences'); mine:GetScript('OnClick')(mine)
            assert(not panel:IsVisible())
        """)

    def test_each_paladin_column_edits_its_own_capabilities_and_handles_empty_roster(self):
        lua = full_addon()
        lua.execute("""
            ns.Options.Toggle()
            local tab = findWidget('Paladins'); tab:GetScript('OnClick')(tab)
            local panel = findWidget('Blessings and auras').parent
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
            for _, seat in ipairs(panel.seats) do assert(seat:IsShown()) end
        """)

    def test_non_paladins_do_not_see_assignment_tab(self):
        lua = self.core_runtime("ROGUE")
        lua.execute("""
            ns.App:GetScript('OnEvent')(ns.App, 'ADDON_LOADED', 'Buffeteria')
            ns.roster = ns.Roster.Build(); ns.Preview = {active=false}; ns.Tracker = {}
        """)
        for name in ("Features/Tracker/View.lua", "Features/Preferences/View.lua", "Features/Paladins/View.lua", "Features/Options/Window.lua"):
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


    def test_auras_are_unique_prioritized_and_respect_manual_picks(self):
        self.solver("""
            local base = {DEVO=true, RETRI=true, FIRERES=true, FROSTRES=true, SHADOWRES=true}
            local function with(extra) local c = {} for k in pairs(base) do c[k] = true end; c[extra] = true; return c end
            local roster = {members={Holy=member('PALADIN', with('CONC')), Ret=member('PALADIN', with('SANCTITY')),
                Prot=member('PALADIN', base), Rogue=member('ROGUE')}}
            local r = ns.Solver.Solve(roster)
            -- Talented auras land on the paladins who have them; Devotion goes to the other.
            assert(r.auras.Prot == 'DEVO' and r.auras.Holy == 'CONC' and r.auras.Ret == 'SANCTITY')
            assert(r.auras.Rogue == nil)
            roster.paladinAuras = {Prot='FIRERES', Holy='NONE'}
            r = ns.Solver.Solve(roster)
            assert(r.auras.Prot == 'FIRERES' and r.auras.Holy == nil and r.auras.Ret == 'DEVO')
            -- An unknown manual aura falls back to Auto.
            roster.paladinAuras = {Prot='CONC'}
            r = ns.Solver.Solve(roster)
            assert(r.auras.Prot == 'DEVO' and r.auras.Holy == 'CONC')
        """)

    def test_aura_slot_syncs_persists_and_stays_unique(self):
        lua = self.plan_runtime()
        lua.execute("""
            ns.roster.members['A-Realm'].caps.DEVO = true; ns.roster.members['B-Realm'].caps.DEVO = true
            ns.Paladins.Set('A-Realm', 'AURA', 'DEVO')
            assert(ns.db.paladinBlessings.AURA == 'DEVO')
            assert(sent[#sent]:match('^P|2|A%-Realm|10|DEVO|'))
            ns.Paladins.Set('A-Realm', 'AURA', 'KINGS') -- blessings are not auras
            ns.Paladins.Set('A-Realm', 'ROGUE', 'DEVO') -- auras are not blessings
            assert(ns.Paladins.Get('A-Realm', 'AURA') == 'DEVO' and ns.Paladins.Get('A-Realm', 'ROGUE') == 'AUTO')
            ns.Paladins.Set('B-Realm', 'AURA', 'DEVO')
            assert(ns.Paladins.Get('A-Realm', 'AURA') == 'NONE' and ns.Paladins.Get('B-Realm', 'AURA') == 'DEVO')
            ns.Paladins.Set('C-Realm', 'AURA', 'SANCTITY')
            local blessings, auras = ns.Paladins.Assignments(ns.roster)
            assert(auras['C-Realm'] == 'SANCTITY' and auras['B-Realm'] == 'DEVO' and blessings.AURA == nil)
            assert(ns.roster.members['C-Realm'].caps.SANCTITY)
            ns.Paladins.Receive('B-Realm', 'A-Realm', '10', 'RETRI', '9999', 'B-Realm')
            assert(ns.Paladins.Get('A-Realm', 'AURA') == 'RETRI')
            ns.Paladins.Receive('B-Realm', 'A-Realm', '10', 'MIGHT', '99999', 'B-Realm')
            ns.Paladins.Receive('B-Realm', 'A-Realm', '11', 'DEVO', '99999', 'B-Realm')
            assert(ns.Paladins.Get('A-Realm', 'AURA') == 'RETRI')
            ns.Paladins.cells = {}; ns.Paladins.Init()
            assert(ns.Paladins.Get('A-Realm', 'AURA') == 'RETRI')
        """)

    def test_auto_fill_and_clear_from_the_paladins_tab(self):
        lua = full_addon()
        lua.execute("""
            ns.Options.Toggle()
            local tab = findWidget('Paladins'); tab:GetScript('OnClick')(tab)
            local panel = findWidget('Blessings and auras').parent
            -- B has no add-on, so only baseline auras are assumed: it gets Devotion,
            -- and A takes Concentration, which only A knows.
            assert(ns.result.auras['B-Realm'] == 'DEVO' and ns.result.auras['A-Realm'] == 'CONC')
            local aura = panel.columns[1].aura
            assert(aura.state == 'green' and panel.columns[1].note:GetText():find('Concentration Aura'))
            ns.Paladins.Set('A-Realm', 'ROGUE', 'NONE'); runTimers()
            panel.fill:GetScript('OnClick')(panel.fill); runTimers()
            for _, class in ipairs(ns.Buffs.CLASS_KEYS) do
                local b = ns.Paladins.Get('B-Realm', class)
                assert(b ~= 'AUTO' and ns.Buffs.byKey[b].kind == 'blessing')
            end
            assert(ns.Paladins.Get('A-Realm', 'ROGUE') == 'NONE') -- manual picks stay
            assert(ns.Paladins.Get('A-Realm', 'AURA') == 'CONC' and ns.Paladins.Get('B-Realm', 'AURA') == 'DEVO')
            assert(aura.state == 'gold' and panel.columns[1].rows.WARRIOR.state == 'gold')
            local wire = false
            for _, msg in ipairs(delivered) do if msg:match('^P|2|B%-Realm|10|DEVO|') then wire = true end end
            assert(wire)
            -- Cycling the aura button skips auras the paladin can't cast.
            aura:GetScript('OnClick')(aura, 'LeftButton'); runTimers()
            assert(ns.Paladins.Get('A-Realm', 'AURA') == 'SANCTITY')
            aura:GetScript('OnEnter')(aura)
            assert(GameTooltip:GetText() == 'A - Aura')
            panel.clear:GetScript('OnClick')(panel.clear); runTimers()
            assert(ns.Paladins.Get('A-Realm', 'AURA') == 'AUTO' and ns.Paladins.Get('A-Realm', 'ROGUE') == 'AUTO')
            assert(ns.Paladins.Get('B-Realm', 'WARRIOR') == 'AUTO')
            local announced = table.concat(ns.Assignments.Lines(false), ' ; ')
            assert(announced:find('Concentration Aura') and announced:find('Devotion Aura'))
        """)

    def test_tank_roles_requests_and_saved_opt_outs(self):
        lua = full_addon()
        lua.execute("""
            local role = 'NONE'
            function UnitGroupRolesAssigned() return role end
            assert(not ns.Preferences.Get().wants.RFURY and not ns.Preferences.Get().wants.THORNS)
            role = 'TANK'
            ns.App:GetScript('OnEvent')(ns.App, 'ROLE_CHANGED_INFORM'); runTimers()
            assert(ns.result.expected['A-Realm'].RFURY == 'A-Realm')
            assert(ns.Preferences.Get().wants.THORNS)
            local message = delivered[#delivered]
            assert(message:match('^S|2|') and message:find('RFURY') and message:find('THORNS'))
            for _, msg in ipairs(delivered) do assert(#msg <= 255) end
            ns.Options.Toggle()
            local panel = findWidget('Your buffet').parent
            local thorns = panel.tankButtons.THORNS
            thorns:GetScript('OnClick')(thorns); runTimers()
            assert(not ns.Preferences.Get().wants.THORNS)
            role = 'HEALER'
            ns.App:GetScript('OnEvent')(ns.App, 'PLAYER_ROLES_ASSIGNED'); runTimers()
            assert(not ns.result.expected['A-Realm'].RFURY)
            assert(ns.db.tankBuffs.RFURY and not ns.db.tankBuffs.THORNS)
            panel.tankRole:GetScript('OnClick')(); runTimers() -- Auto -> Tank
            assert(ns.result.expected['A-Realm'].RFURY == 'A-Realm')
            panel.tankRole:GetScript('OnClick')(); runTimers() -- Tank -> Not tank
            assert(not ns.Preferences.Get().wants.RFURY)
            ns.Database.Init() -- keep choices on reload
            assert(ns.db.tankRole == 'OFF' and not ns.db.tankBuffs.THORNS)
            ns.Preferences.Reset(); runTimers()
            assert(ns.db.tankRole == 'AUTO' and ns.db.tankBuffs.THORNS)
        """)

    def test_classic_main_tank_detection_and_missing_role_apis(self):
        lua = full_addon()
        lua.execute("""
            assert(not ns.WoW.IsTank('player')) -- role APIs absent
            function GetPartyAssignment(assignment, unit) return assignment == 'MAINTANK' and unit == 'party1' end
            assert(ns.WoW.IsTank('party1') and not ns.WoW.IsTank('player'))
            GetPartyAssignment = nil
            function UnitInRaid(unit) if unit == 'player' then return 1 end end
            function GetRaidRosterInfo(index)
                return 'A-Realm', 0, 1, 60, 'Paladin', 'PALADIN', '', true, false, 'maintank', false, 'NONE'
            end
            assert(ns.WoW.IsTank('player') and ns.WoW.IsTank('raid1'))
            assert(ns.Preferences.Get().wants.RFURY)
            GetRaidRosterInfo = function() return nil, 0, 1, 60, nil, nil, nil, true, false, nil, false, 'TANK' end
            assert(ns.WoW.IsTank('raid1'))
        """)

    def test_tank_solver_self_buffs_and_multiple_druids(self):
        self.solver("""
            local a = member('PALADIN', {RFURY=true})
            local b = member('PALADIN', {RFURY=true})
            local c = member('WARRIOR')
            local d = member('DRUID', {THORNS=true})
            local e = member('DRUID', {THORNS=true})
            a.wants = {RFURY=true, THORNS=true}; b.wants = {RFURY=true, THORNS=true}
            c.wants = {RFURY=true, THORNS=true} -- self spell must reject wrong class
            local roster = {members={A=a, B=b, C=c, D=d, E=e}}
            local result = ns.Solver.Solve(roster)
            assert(result.expected.A.RFURY == 'A' and result.expected.B.RFURY == 'B')
            assert(not result.expected.C.RFURY)
            assert(result.expected.A.THORNS == 'D' and result.expected.B.THORNS == 'E' and result.expected.C.THORNS == 'D')
            assert(not result.expected.D.THORNS and not result.expected.E.THORNS)
            a.caps.RFURY = nil; d.caps.THORNS = nil; e.caps.THORNS = nil
            result = ns.Solver.Solve(roster)
            assert(not result.expected.A.RFURY and not result.expected.A.THORNS)
        """)

    def test_tank_tracker_self_cast_expiry_and_combat(self):
        lua = full_addon()
        lua.execute("""
            GROUP_SIZE = 0
            ns.db.tankRole = 'TANK'; ns.db.wants = {}
            ns.Paladins.Set('A-Realm', 'PALADIN', 'NONE')
            ns.Paladins.Set('A-Realm', 'AURA', 'NONE'); runTimers()
            ns.Tracker.Refresh()
            local button = Buffeteria_CastButton
            assert(button:GetAttribute('spell') == '25780' and button:GetAttribute('unit') == 'player')
            assert(ns.Tracker.Summary().perKey.RFURY.bad == 1)
            C_UnitAuras.GetAuraDataByIndex = function(unit, i)
                if unit == 'player' and i == 1 then return {name='25780', expirationTime=0, sourceUnit='player'} end
            end
            ns.Tracker.Refresh()
            assert(ns.Tracker.Summary().perKey.RFURY.bad == 0 and not button:GetAttribute('spell'))
            C_UnitAuras.GetAuraDataByIndex = function() end
            ns.Tracker.Refresh()
            COMBAT = true
            ns.db.tankRole = 'OFF'; ns.Preferences.Changed(); runTimers()
            assert(button:GetAttribute('spell') == '25780') -- secure attributes held in combat
            COMBAT = false; ns.App:GetScript('OnEvent')(ns.App, 'PLAYER_REGEN_ENABLED')
            assert(not button:GetAttribute('spell'))
        """)

    def test_druid_serves_thorns_to_tanks_without_addon_and_peer_opt_out(self):
        lua = full_addon('DRUID')
        lua.execute("""
            function UnitGroupRolesAssigned(unit) return unit == 'party1' and 'TANK' or 'HEALER' end
            ns.App:GetScript('OnEvent')(ns.App, 'PLAYER_ROLES_ASSIGNED'); runTimers()
            assert(ns.roster.members['B-Realm'].wants.THORNS)
            assert(ns.result.expected['B-Realm'].THORNS == 'A-Realm')
            assert(not ns.Preferences.Get().wants.RFURY)
            assert(ns.Roster.Capabilities().THORNS and not ns.Roster.Capabilities().RFURY)
            ns.Options.Toggle()
            assert(not findWidget('Your buffet').parent.tankButtons.RFURY:IsShown())
            ns.db.wants = {}
            ns.Comm.OnMessage('BUFFETERIA', 'S|2|THORNS|KINGS||MIGHT|0', 'PARTY', 'B-Realm'); runTimers()
            ns.result.pally = {}; ns.result.auras = {} -- isolate the tank cast
            ns.Tracker.Refresh()
            assert(Buffeteria_CastButton:GetAttribute('spell') == '9910')
            assert(Buffeteria_CastButton:GetAttribute('unit') == 'party1')
            assert(table.concat(ns.Assignments.Lines(false), ';'):find('Thorns: A -> B', 1, true))
            C_UnitAuras.GetAuraDataByIndex = function(unit, i)
                if unit == 'party1' and i == 1 then return {name='9910', expirationTime=WOW_TIME+60} end
            end
            ns.Tracker.Refresh()
            assert(ns.Tracker.Summary().perKey.THORNS.warn == 1)
            IsSpellInRange = function() return 0 end
            assert(not ns.Actions.Next(WOW_TIME, 300))
            ns.Comm.OnMessage('BUFFETERIA', 'S|2||KINGS||MIGHT|0', 'PARTY', 'B-Realm'); runTimers()
            assert(not ns.result.expected['B-Realm'].THORNS) -- explicit peer opt-out beats role default
        """)

    def test_tracker_turns_on_my_missing_aura(self):
        lua = full_addon()
        lua.execute("""
            ns.db.showTracker = true
            ns.Tracker.Refresh()
            local summary = ns.Tracker.Summary()
            assert(summary.perKey.CONC.bad == 1 and summary.overall == 'bad')
            local button = Buffeteria_CastButton
            -- Highest known rank of Concentration Aura, cast on myself.
            assert(button:GetAttribute('spell') == '19746' and button:GetAttribute('unit') == 'player')
            -- Another paladin's Concentration Aura is not mine.
            C_UnitAuras.GetAuraDataByIndex = function(unit, i)
                if unit == 'player' and i == 1 then return {name='19746', expirationTime=0, sourceUnit='party1'} end
            end
            assert(ns.Scan.MissingAura() == 'CONC')
            C_UnitAuras.GetAuraDataByIndex = function(unit, i)
                if unit == 'player' and i == 1 then return {name='19746', expirationTime=0, sourceUnit='player'} end
            end
            assert(ns.Scan.MissingAura() == nil)
            ns.Tracker.Refresh()
            assert(ns.Tracker.Summary().perKey.CONC.bad == 0)
            assert(button:GetAttribute('spell') ~= '19746')
        """)

if __name__ == "__main__":
    unittest.main()
