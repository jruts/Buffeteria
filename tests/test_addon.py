"""Run with python tests/test_addon.py (requires lupa with its Lua 5.1 runtime)."""
from pathlib import Path
import struct
import shutil
import sys
import tempfile
import unittest

from lupa.lua51 import LuaRuntime

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
from deploy_dev import DEV_NAME, deploy, dev_toc, digest, runtime_sources


def runtime(addon_name="Buffeteria"):
    lua = LuaRuntime(unpack_returned_tuples=True)
    lua.globals().ADDON_NAME = addon_name
    lua.execute("ns = {}; function loadAddon(source, name) assert(loadstring(source, name))(ADDON_NAME, ns) end")
    return lua


def load(lua, name):
    lua.globals().loadAddon((ROOT / name).read_text(encoding="utf-8"), name)


def addon_files():
    return [line.strip() for line in (ROOT / "Buffeteria.toc").read_text().splitlines()
            if line.strip().endswith(".lua") and not line.startswith("#")]


def full_addon(player_class="PALADIN", login=True, addon_name="Buffeteria"):
    lua = runtime(addon_name)
    lua.execute((ROOT / "tests/wow_mock.lua").read_text(encoding="utf-8"))
    lua.globals().PLAYER_CLASS = player_class
    for name in addon_files():
        load(lua, name)
    lua.execute("ns.App:GetScript('OnEvent')(ns.App, 'ADDON_LOADED', ADDON_NAME)")
    if login:
        lua.execute("ns.App:GetScript('OnEvent')(ns.App, 'PLAYER_LOGIN'); runTimers()")
    return lua


class AddonTests(unittest.TestCase):
    def test_unsized_settings_preview_does_not_abort_navigation_initialization(self):
        lua = full_addon()
        lua.execute("""
            local refresh = ns.Tracker.SettingsPreview.Refresh
            local sample = ns.Tracker.SettingsPreview.Create(UIParent)
            sample:SetSize(0, 0)
            refresh(sample)
            assert(not sample.gief.font and not sample.visibleCount)
            sample:SetSize(20, 20)
            refresh(sample)
            assert(not sample.gief.font)
            sample:SetSize(300, 205)
            refresh(sample)
            assert(sample.gief.font[2] > 0 and sample.visibleCount > 0)
            -- Enforce the client's zero-size initial frame behavior specifically
            -- for the settings sample, rather than the mock's generic 140px default.
            local create = ns.Tracker.SettingsPreview.Create
            ns.Tracker.SettingsPreview.Create = function(parent)
                local preview = create(parent)
                preview:SetSize(0, 0)
                return preview
            end
            ns.Tracker.SettingsPreview.Refresh = function(preview)
                assert(preview:GetWidth() > 20 and preview:GetHeight() > 20,
                    'options must lay out the settings sample before painting')
                refresh(preview)
            end
            ns.Options.Toggle()
            assert(findWidget('My preferences').parent:IsVisible())
            assert(findWidget('Paladins').parent:IsVisible())
            assert(findWidget('Settings').parent:IsVisible())
            local settings = findWidget('Settings').parent
            assert(settings.point and settings.point[2] == findWidget('Paladins').parent)
            settings:GetScript('OnClick')(settings)
            assert(findWidget('Tracker settings'):IsVisible())
        """)

    def test_navigation_tabs_clear_the_title_bar_and_direct_commands_select_panels(self):
        for player_class in ("PALADIN", "ROGUE"):
            with self.subTest(player_class=player_class):
                lua = full_addon(player_class, addon_name=DEV_NAME)
                lua.execute("""
                    SlashCmdList.BUFFETERIADEV('preferences')
                    local preferences = findWidget('My preferences').parent
                    local settings = findWidget('Settings').parent
                    local paladins = findWidget('Paladins').parent
                    local content = preferences:GetParent()
                    assert(content.point[1] == 'TOPLEFT' and content.point[3] == -30)
                    assert(settings:IsVisible() and settings:GetFrameLevel() > content:GetFrameLevel())
                    assert(settings:GetHeight() == 28)
                    assert(paladins:IsVisible() == (PLAYER_CLASS == 'PALADIN'))
                    SlashCmdList.BUFFETERIADEV('settings')
                    assert(ns.db.optionsTab == 'SETTINGS' and openedCategory == 1)
                    settingsPage:GetScript('OnShow')(settingsPage)
                    assert(findWidget('Tracker settings'):IsVisible())
                    SlashCmdList.BUFFETERIADEV('paladins')
                    assert(BuffeteriaDev_Prefs:IsShown())
                    assert(findWidget('Class blessings'):IsVisible() == (PLAYER_CLASS == 'PALADIN'))
                    assert(ns.db.optionsTab == (PLAYER_CLASS == 'PALADIN' and 'PALADIN' or 'PERSONAL'))
                    SlashCmdList.BUFFETERIADEV('preferences')
                    assert(BuffeteriaDev_Prefs:IsShown() and findWidget('Blessings'):IsVisible())
                    settings:GetScript('OnClick')(settings)
                    assert(findWidget('Tracker settings'):IsVisible())
                """)

    def test_settings_sample_filters_layout_and_combat_do_not_touch_cast_button(self):
        for player_class in ("PALADIN", "ROGUE", "PRIEST", "DRUID", "MAGE", "WARRIOR"):
            with self.subTest(player_class=player_class):
                lua = full_addon(player_class)
                lua.execute("""
                    ns.Options.Toggle()
                    findWidget('Settings').parent:GetScript('OnClick')(findWidget('Settings').parent)
                    local panel = findWidget('Tracker settings').parent
                    local sample, head, frame = panel.preview, Buffeteria_CastButton, Buffeteria_Tracker
                    local spell, unit, point = head:GetAttribute('spell'), head:GetAttribute('*unit1'), frame.point
                    assert(not sample.head.secure and not sample.head:GetScript('OnClick'))
                    assert(not ns.Tracker.Preview.active)
                    ns.Database.Set('showTracker', false)
                    COMBAT = true
                    ns.Database.Set('iconSize', 128)
                    ns.Database.Set('statusIconSize', 64)
                    assert(head:GetWidth() == 96 and sample.head:GetWidth() <= 128)
                    assert(not frame:IsShown() and sample:IsVisible())
                    for _, side in ipairs({'LEFT','RIGHT','TOP','BOTTOM','AUTO'}) do
                        for columns = 2, 4 do
                            ns.Database.Set('iconPosition', side)
                            ns.Database.Set('iconsPerRow', columns)
                            assert(sample.fitScale > 0 and sample.fitScale <= 1)
                            for _, icon in ipairs(sample.icons) do
                                if icon:IsShown() then
                                    local x, y = icon.point[4], icon.point[5]
                                    assert(x >= -sample:GetWidth()/2 and x + icon:GetWidth() <= sample:GetWidth()/2)
                                    assert(y <= sample:GetHeight()/2 and y - icon:GetHeight() >= -sample:GetHeight()/2)
                                end
                            end
                        end
                    end
                    for _, mode in ipairs({'ALL','MISSING','EXPIRING','PROBLEMS'}) do
                        ns.Database.Set('buffDisplay', mode)
                        local n = 0
                        for _, icon in ipairs(sample.icons) do
                            if icon:IsShown() then
                                n = n + 1
                                assert(mode ~= 'MISSING' or icon.state == 'bad')
                                assert(mode ~= 'EXPIRING' or icon.state == 'warn')
                                assert(mode ~= 'PROBLEMS' or icon.state ~= 'ok')
                            end
                        end
                        assert(n == (mode == 'MISSING' and 2 or mode == 'EXPIRING' and 2 or 4))
                    end
                    ns.Database.Set('warnMinutes', 1)
                    ns.Database.Set('buffDisplay', 'EXPIRING')
                    assert(sample.visibleCount == 0)
                    ns.Database.Set('buffDisplay', 'ALL')
                    findWidget('Happy').parent:GetScript('OnClick')(findWidget('Happy').parent)
                    assert(sample.head.icon.texture:find('Happy$') and sample.visibleCount == 4)
                    assert(head:GetAttribute('spell') == spell and head:GetAttribute('*unit1') == unit)
                    assert(frame.point == point and not ns.Tracker.Preview.active)
                    ns.Options.Toggle()
                    ns.Options.Toggle()
                    assert(findWidget('Tracker settings'):IsVisible() and ns.db.optionsTab == 'SETTINGS')
                    COMBAT = false
                    ns.Database.Set('showTracker', true)
                    ns.App:GetScript('OnEvent')(ns.App, 'PLAYER_REGEN_ENABLED')
                    assert(head:GetWidth() == 128)
                """)

    def test_bulk_undo_preserves_newer_registers_and_new_claims(self):
        lua = full_addon()
        lua.execute("""
            ns.Paladins.Set('A-Realm', 'ROGUE', 'KINGS')
            ns.Paladins.Set('B-Realm', 'ROGUE', 'MIGHT')
            runTimers()
            ns.Paladins.Clear(); runTimers()
            assert(ns.Paladins.CanUndo())
            -- A different paladin claims Kings after Reset. Undo must not steal it.
            ns.Paladins.Set('B-Realm', 'ROGUE', 'KINGS'); runTimers()
            ns.Paladins.Undo(); runTimers()
            assert(ns.Paladins.Get('A-Realm', 'ROGUE') == 'AUTO')
            assert(ns.Paladins.Get('B-Realm', 'ROGUE') == 'KINGS')
            assert(not ns.Paladins.CanUndo())
            ns.Paladins.Clear(); runTimers()
            ns.Paladins.Fill(); runTimers()
            local own = ns.Paladins.Get('A-Realm', 'WARRIOR')
            -- Even an identical value from another writer is a newer register.
            ns.Paladins.Receive('B-Realm', 'A-Realm', '1', own,
                tostring(ns.Paladins.revision + 10), 'B-Realm')
            local written = ns.Paladins.cells['A-Realm'].WARRIOR
            ns.Paladins.Undo(); runTimers()
            assert(ns.Paladins.cells['A-Realm'].WARRIOR == written)
            assert(ns.Paladins.Get('B-Realm', 'WARRIOR') == 'AUTO')
            ns.Paladins.Set('A-Realm', 'ROGUE', 'NONE'); runTimers()
            ns.Paladins.Clear(); runTimers()
            assert(ns.Paladins.Undo() > 0); runTimers()
            assert(ns.Paladins.Get('A-Realm', 'ROGUE') == 'NONE')
            ns.Paladins.Clear(); runTimers()
            GROUP_SIZE = 0; ns.Assignments.Resolve(); runTimers()
            assert(not ns.Paladins.CanUndo())
        """)

    def test_blessing_mode_previews_preserve_saved_and_shared_preferences(self):
        lua = full_addon()
        lua.execute("""
            ns.Paladins.Set('A-Realm', 'PALADIN', 'KINGS')
            ns.Paladins.Set('B-Realm', 'PALADIN', 'WISDOM'); runTimers()
            ns.db.order = {'MIGHT','KINGS','WISDOM','LIGHT','SANCT','|','SALV'}
            ns.db.blessingsOverride = false
            local roster = ns.Assignments.roster
            local member = roster.members['A-Realm']
            local result, messages = ns.Assignments.result, #delivered
            local follow, personal = ns.Preferences.BlessingOutcome(false), ns.Preferences.BlessingOutcome(true)
            assert(follow.KINGS and follow.WISDOM and not follow.MIGHT)
            assert(personal.MIGHT and personal.KINGS and not personal.WISDOM)
            assert(ns.Assignments.roster == roster and roster.members['A-Realm'] == member)
            assert(ns.Assignments.result == result and not ns.db.blessingsOverride)
            assert(ns.db.order[1] == 'MIGHT' and #delivered == messages)
        """)

    def test_buff_icons_retry_uncached_data_and_use_all_available_ranks(self):
        lua = full_addon()
        lua.execute("""
            local original = ns.WoW.SpellIcon
            ns.WoW.SpellIcon = function() return 134400 end
            assert(ns.UI.BuffIcon('SANCT') == 'Interface\\\\Icons\\\\Spell_Nature_LightningShield')
            ns.WoW.SpellIcon = function(id) if id == 20912 then return 987654 end end
            assert(ns.UI.BuffIcon('SANCT') == 987654)
            ns.WoW.SpellIcon = function() return nil end
            assert(ns.UI.BuffIcon('SANCT') == 987654)
            ns.WoW.SpellIcon = original
        """)

    def test_dev_identity_and_settings_are_independent_for_every_class(self):
        for player_class in ("WARRIOR", "ROGUE", "HUNTER", "MAGE", "WARLOCK", "PRIEST", "DRUID", "PALADIN", "SHAMAN"):
            with self.subTest(player_class=player_class):
                lua = full_addon(player_class, login=False, addon_name=DEV_NAME)
                lua.execute(r"""
                    BuffeteriaCharDB = {sentinel=true, iconSize=37}
                    local liveDB = BuffeteriaCharDB
                    ns.App:GetScript('OnEvent')(ns.App, 'ADDON_LOADED', 'Buffeteria-Dev')
                    ns.App:GetScript('OnEvent')(ns.App, 'PLAYER_LOGIN'); runTimers()
                    assert(ns.db == BuffeteriaDevCharDB and ns.db ~= liveDB)
                    assert(ns.db.iconSize == 96 and liveDB.iconSize == 37)
                    assert(BuffeteriaCharDB == liveDB and liveDB.sentinel)
                    assert(ns.UI.ICON == 'Interface\\AddOns\\Buffeteria-Dev\\Media\\Icon')
                    assert(BuffeteriaDev_CastButton.icon.texture:find('Buffeteria%-Dev'))
                    assert(not Buffeteria_CastButton and not Buffeteria_MinimapButton)
                    assert(BuffeteriaDev_MinimapButton and BuffeteriaDev_Tracker)
                    assert(SLASH_BUFFETERIADEV1 == '/buffeteriadev' and SLASH_BUFFETERIADEV2 == '/buffdev')
                    assert(not SlashCmdList.BUFFETERIA and not SLASH_BUFFETERIA2)
                    assert(BINDING_HEADER_BUFFETERIADEV == 'Buffeteria-Dev')
                    assert(_G['BINDING_NAME_CLICK BuffeteriaDev_CastButton:LeftButton'] == 'Cast next buff')
                    assert(settingsPage.name == 'Buffeteria-Dev')
                    SlashCmdList.BUFFETERIADEV(''); assert(BuffeteriaDev_Prefs:IsShown())
                    assert(UISpecialFrames[1] == 'BuffeteriaDev_Prefs')
                    BuffeteriaDev_OnAddonCompartmentClick(nil, 'RightButton'); assert(openedCategory == 1)
                    SlashCmdList.BUFFETERIADEV('hide'); assert(not ns.db.showTracker)
                    ns.App:GetScript('OnEvent')(ns.App, 'ADDON_LOADED', 'Buffeteria-Dev')
                    assert(not ns.db.showTracker and BuffeteriaCharDB == liveDB)
                    SlashCmdList.BUFFETERIADEV('preview'); assert(ns.Tracker.Preview.active)
                    assert(ns.Protocol.PREFIX == 'BUFFETERIA') -- works with release users in the group
                """)

    def test_dev_deployment_build_backup_and_live_preservation(self):
        with tempfile.TemporaryDirectory() as temporary:
            base = Path(temporary)
            repo = base / "repo"
            repo.mkdir()
            for relative, source in runtime_sources(ROOT).items():
                target = repo / relative
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(source, target)
            shutil.copy2(ROOT / "Buffeteria.toc", repo / "Buffeteria.toc")
            addons = base / "Interface" / "AddOns"
            live = addons / "Buffeteria"
            live.mkdir(parents=True)
            (live / "Buffeteria.toc").write_bytes(b"CurseForge release sentinel")
            (live / "Bindings.xml").write_bytes(b"Live bindings sentinel")
            live_hashes = {p.name: digest(p) for p in live.iterdir()}
            destination, _, count = deploy(addons, repo)
            self.assertEqual(destination.name, DEV_NAME)
            self.assertEqual(count, len(runtime_sources(repo)) + 1)
            self.assertFalse((destination / "Buffeteria.toc").exists())
            toc = (destination / (DEV_NAME + ".toc")).read_text()
            self.assertEqual(toc, dev_toc((repo / "Buffeteria.toc").read_text()))
            self.assertIn("## SavedVariablesPerCharacter: BuffeteriaDevCharDB", toc)
            bindings = (destination / "Bindings.xml").read_text()
            self.assertIn('name="CLICK BuffeteriaDev_CastButton:LeftButton"', bindings)
            self.assertIn('header="BUFFETERIADEV"', bindings)
            self.assertFalse((destination / "tests").exists())
            self.assertFalse((destination / "tools").exists())
            # Load the actual installed Dev manifest and source, including its asset paths.
            lua = runtime(DEV_NAME)
            lua.execute((ROOT / "tests/wow_mock.lua").read_text())
            for line in toc.splitlines():
                if line.strip().endswith(".lua") and not line.startswith("#"):
                    lua.globals().loadAddon((destination / line.strip()).read_text(), line)
            lua.execute("ns.App:GetScript('OnEvent')(ns.App, 'ADDON_LOADED', ADDON_NAME); ns.App:GetScript('OnEvent')(ns.App, 'PLAYER_LOGIN'); runTimers()")
            self.assertIsNotNone(lua.globals().BuffeteriaDev_CastButton)
            metadata = dict(line[3:].split(": ", 1) for line in toc.splitlines()
                            if line.startswith("## "))
            self.assertEqual(metadata["IconTexture"], lua.globals().ns.UI.ICON)
            self.assertIsNotNone(lua.globals()[metadata["AddonCompartmentFunc"]])
            self.assertEqual(metadata["SavedVariablesPerCharacter"], lua.globals().ns.savedVariable)
            old = b"previous development file"
            (destination / "App" / "State.lua").write_bytes(old)
            _, backup, _ = deploy(addons, repo)
            self.assertEqual((backup / DEV_NAME / "App" / "State.lua").read_bytes(), old)
            for relative, source in runtime_sources(repo).items():
                if relative != Path("Bindings.xml"):
                    self.assertEqual(digest(source), digest(destination / relative))
            self.assertEqual(live_hashes, {p.name: digest(p) for p in live.iterdir()})
            with self.assertRaises(FileNotFoundError):
                deploy(base / "missing", repo)

    def test_icon_grid_uses_chosen_side_and_row_width_without_moving_head(self):
        lua = full_addon()
        lua.execute("""
            local frame, head = Buffeteria_Tracker, Buffeteria_CastButton
            local s = ns.Tracker.Preview.Summary()
            ns.Tracker.Compute = function() return s end
            ns.db.buffDisplay = 'ALL'
            local function check(side, columns, expectedCount)
                ns.db.iconPosition, ns.db.iconsPerRow = side, columns
                local oldPoint, oldHeight, oldWidth = frame.point, frame:GetHeight(), frame:GetWidth()
                ns.Tracker.Refresh()
                local count, rows = 0, {}
                local left, right, bottom, top
                for _, w in ipairs(widgets) do
                    if w.parent == frame and w.key and w.tex and w:IsShown() then
                        count = count + 1
                        assert(w:GetWidth() == ns.db.statusIconSize and w:GetHeight() == ns.db.statusIconSize)
                        assert(w.point[1] == 'TOPLEFT' and w.point[2] == head and w.point[3] == side)
                        local x, y = w.point[4], w.point[5]
                        local r = rows[y] or {count=0, left=x, right=x + w:GetWidth()}
                        rows[y] = r
                        r.count = r.count + 1
                        r.left = math.min(r.left, x)
                        r.right = math.max(r.right, x + w:GetWidth())
                        local step = ns.db.statusIconSize + 2
                        if r.previousX then assert(x - r.previousX == (side == 'LEFT' and -step or step)) end
                        r.previousX = x
                        if side == 'LEFT' then x = x - head:GetWidth() / 2 end
                        if side == 'RIGHT' then x = x + head:GetWidth() / 2 end
                        if side == 'TOP' then y = y + head:GetHeight() / 2 end
                        if side == 'BOTTOM' then y = y - head:GetHeight() / 2 end
                        left = math.min(left or x, x)
                        right = math.max(right or (x + w:GetWidth()), x + w:GetWidth())
                        bottom = math.min(bottom or (y - w:GetHeight()), y - w:GetHeight())
                        top = math.max(top or y, y)
                    end
                end
                assert(count == expectedCount)
                local actualColumns, actualRows = 0, 0
                for _, r in pairs(rows) do
                    actualColumns = math.max(actualColumns, r.count)
                    actualRows = actualRows + 1
                    if side == 'TOP' or side == 'BOTTOM' then assert(r.left == -r.right) end
                    if side == 'LEFT' then assert(r.right == -4) end
                    if side == 'RIGHT' then assert(r.left == 4) end
                end
                assert(actualColumns == math.min(columns, expectedCount))
                assert(actualRows == math.ceil(expectedCount / columns))
                if count > 0 then
                    if side == 'LEFT' then assert(right < -head:GetWidth() / 2 and bottom == -top) end
                    if side == 'RIGHT' then assert(left > head:GetWidth() / 2 and bottom == -top) end
                    if side == 'TOP' then assert(bottom >= head:GetHeight() / 2 + 2 and left == -right) end
                    if side == 'BOTTOM' then assert(top == -head:GetHeight() / 2 - 4 and left == -right) end
                end
                assert(frame.point == oldPoint and frame:GetHeight() == oldHeight and frame:GetWidth() == oldWidth)
            end
            for _, side in ipairs({'LEFT', 'TOP', 'RIGHT', 'BOTTOM'}) do
                for columns = 2, 4 do
                    check(side, columns, 10)
                    -- Screen edges, a small screen, and UI scale never override the setting.
                    for _, position in ipairs({{2, 12}, {1886, 12}, {2, 1000}, {1886, 1000}}) do
                        head.left, head.bottom, head.top = position[1], position[2], position[2] + head:GetHeight()
                        check(side, columns, 10)
                    end
                    UIParent:SetSize(320, 200)
                    head.GetEffectiveScale = function() return 0.5 end
                    check(side, columns, 10)
                    UIParent:SetSize(1920, 1080)
                    head.GetEffectiveScale = function() return 1 end
                end
            end
            for _, size in ipairs({32, 128}) do
                ns.db.iconSize = size; ns.Tracker.Refresh()
                for _, side in ipairs({'LEFT', 'TOP', 'RIGHT', 'BOTTOM'}) do check(side, 3, 10) end
            end
            local spell, unit = head:GetAttribute('spell'), head:GetAttribute('*unit1')
            COMBAT = true
            check('RIGHT', 4, 10)
            assert(head:GetAttribute('spell') == spell and head:GetAttribute('*unit1') == unit)
            COMBAT = false
            head:GetScript('OnDragStart')(head)
            assert(frame.moving)
            check('LEFT', 3, 10)
            head:GetScript('OnDragStop')(head); runTimers()
            assert(not frame.moving)
            EventRegistry:TriggerEvent('EditMode.Enter')
            frame.editOverlay:GetScript('OnDragStart')(frame.editOverlay)
            check('TOP', 2, 10)
            frame.editOverlay:GetScript('OnDragStop')(frame.editOverlay)
            EventRegistry:TriggerEvent('EditMode.Exit')
            -- Exercise every partial row, including transitions through empty.
            local allKeys = {}; for key in pairs(s.perKey) do allKeys[#allKeys + 1] = key end
            for _, iconSize in ipairs({16, 21, 32, 64}) do
                ns.db.statusIconSize = iconSize
                for count = #allKeys, 0, -1 do
                    s.perKey = {}
                    for i = 1, count do s.perKey[allKeys[i]] = {bad=1, warn=0, total=1} end
                    for _, side in ipairs({'LEFT', 'TOP', 'RIGHT', 'BOTTOM'}) do
                        for columns = 2, 4 do check(side, columns, count) end
                    end
                end
            end
        """)

    def test_auto_icons_fit_screen_edges_sizes_scale_and_drag(self):
        lua = full_addon()
        lua.execute("""
            local frame, head = Buffeteria_Tracker, Buffeteria_CastButton
            ns.Tracker.Compute = ns.Tracker.Preview.Summary
            ns.db.iconPosition, ns.db.buffDisplay = 'AUTO', 'ALL'
            local headScale = 1
            head.GetEffectiveScale = function() return headScale end
            local function check(left, bottom, side, minimumColumns, dragging)
                head.left, head.bottom, head.top = left, bottom, bottom + head:GetHeight()
                local point, width, height = frame.point, frame:GetWidth(), frame:GetHeight()
                if dragging then frame:GetScript('OnUpdate')(frame) else ns.Tracker.Refresh() end
                local screenW, screenH = UIParent:GetWidth() / headScale, UIParent:GetHeight() / headScale
                local count, xs, rects = 0, {}, {}
                for _, w in ipairs(widgets) do
                    if w.parent == frame and w.key and w.tex and w:IsShown() then
                        count = count + 1
                        assert(w.point[2] == head and w.point[3] == side)
                        assert(w:GetWidth() == ns.db.statusIconSize and w:GetHeight() == ns.db.statusIconSize)
                        local x = left + head:GetWidth() / 2 + w.point[4]
                        local y = (side == 'TOP' and head.top or head.bottom) + w.point[5]
                        assert(x >= 4 and x + w:GetWidth() <= screenW - 4)
                        assert(y <= screenH - 4 and y - w:GetHeight() >= 4)
                        xs[x] = true
                        for _, r in ipairs(rects) do
                            assert(x + w:GetWidth() <= r.x or x >= r.x + r.size
                                   or y <= r.y - r.size or y - w:GetHeight() >= r.y)
                        end
                        rects[#rects + 1] = {x=x, y=y, size=w:GetWidth()}
                    end
                end
                local columns = 0; for _ in pairs(xs) do columns = columns + 1 end
                assert(count == 10 and columns >= minimumColumns)
                assert(frame.point == point and frame:GetWidth() == width and frame:GetHeight() == height)
            end
            for _, size in ipairs({16, 21, 32, 64}) do
                ns.db.statusIconSize = size
                for columns = 2, 4 do
                    ns.db.iconsPerRow = columns
                    check(800, 500, 'BOTTOM', columns)
                    check(2, 12, 'TOP', columns)
                    check(1850, 12, 'TOP', columns)
                    check(2, 1000, 'BOTTOM', columns)
                    check(1850, 1000, 'BOTTOM', columns)
                end
            end
            ns.db.iconsPerRow = 2
            UIParent:SetSize(320, 200)
            for _, size in ipairs({16, 21}) do
                ns.db.statusIconSize = size
                check(120, 88, 'BOTTOM', 3) -- widen when neither side fits the chosen width
            end
            UIParent:SetSize(1920, 1080)
            headScale = 0.5
            check(3740, 12, 'TOP', 2)
            headScale = 1
            local spell, unit = head:GetAttribute('spell'), head:GetAttribute('*unit1')
            COMBAT = true
            ns.db.statusIconSize = 64
            check(1850, 12, 'TOP', 2)
            assert(head:GetAttribute('spell') == spell and head:GetAttribute('*unit1') == unit)
            COMBAT = false
            head:GetScript('OnDragStart')(head)
            check(800, 500, 'BOTTOM', 2, true)
            check(2, 12, 'TOP', 2, true)
            head:GetScript('OnDragStop')(head); runTimers()
            assert(not frame:GetScript('OnUpdate'))
            EventRegistry:TriggerEvent('EditMode.Enter')
            frame.editOverlay:GetScript('OnDragStart')(frame.editOverlay)
            check(1850, 12, 'TOP', 2, true)
            frame.editOverlay:GetScript('OnDragStop')(frame.editOverlay)
            EventRegistry:TriggerEvent('EditMode.Exit')
            assert(not frame:GetScript('OnUpdate'))
            head.left, head.bottom, head.top = 800, 500, 564
            frame:GetScript('OnEvent')(frame, 'UI_SCALE_CHANGED')
            check(800, 500, 'BOTTOM', 2)
            -- Selecting a fixed position immediately bypasses automatic flipping.
            ns.db.iconPosition = 'BOTTOM'
            head.left, head.bottom, head.top = 2, 12, 76
            ns.Tracker.Refresh()
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
                assert(ns.db.iconsPerRow == 2)
                assert(ns.db.iconPosition == 'BOTTOM')
                assert(ns.db.statusIconSize == 32)
            end
            BuffeteriaCharDB = {onlyProblems=false, buffDisplay='MISSING', iconSize=16}
            ns.Database.Init()
            assert(ns.db.buffDisplay == 'MISSING' and ns.db.iconSize == 32)
            BuffeteriaCharDB = {buffDisplay='invalid', iconSize='invalid'}
            ns.Database.Init()
            assert(ns.db.buffDisplay == 'PROBLEMS' and ns.db.iconSize == 96)
            for _, columns in ipairs({2, 3, 4, '3'}) do
                BuffeteriaCharDB = {iconsPerRow=columns}
                ns.Database.Init()
                assert(ns.db.iconsPerRow == tonumber(columns))
            end
            for _, columns in ipairs({0, 1, 5, 3.5, 'invalid', false}) do
                BuffeteriaCharDB = {iconsPerRow=columns}
                ns.Database.Init()
                assert(ns.db.iconsPerRow == 2)
            end
            for _, side in ipairs({'LEFT', 'TOP', 'RIGHT', 'BOTTOM', 'AUTO'}) do
                BuffeteriaCharDB = {iconPosition=side, iconsPerRow=3}
                ns.Database.Init()
                assert(ns.db.iconPosition == side and ns.db.iconsPerRow == 3)
            end
            for _, side in ipairs({'invalid', 'left', false, 5}) do
                BuffeteriaCharDB = {iconPosition=side}
                ns.Database.Init()
                assert(ns.db.iconPosition == 'BOTTOM')
            end
            for _, sample in ipairs({{16,16}, {64,64}, {32,32}, {'24',24}, {24.6,25},
                                      {0,16}, {100,64}, {'invalid',32}, {false,32}}) do
                BuffeteriaCharDB = {statusIconSize=sample[1], iconSize=96, iconsPerRow=3, iconPosition='LEFT'}
                ns.Database.Init()
                assert(ns.db.statusIconSize == sample[2])
                assert(ns.db.iconSize == 96 and ns.db.iconsPerRow == 3 and ns.db.iconPosition == 'LEFT')
            end
        """)

    def test_settings_tab_for_every_class_and_shared_game_settings_controls(self):
        for player_class in ("PALADIN", "ROGUE"):
            with self.subTest(player_class=player_class):
                lua = full_addon(player_class)
                lua.execute("""
                    ns.Options.Toggle()
                    local tab = findWidget('Settings').parent
                    assert(tab:IsVisible() and not findWidget('Show tracker'):IsVisible())
                    tab:GetScript('OnClick')(tab)
                    assert(findWidget('Tracker settings'):IsVisible())
                    assert(not findWidget('Blessings'):IsVisible())
                    assert(not findWidget('Class blessings'):IsVisible())
                    local show = findWidget('Show tracker').parent
                    show:SetChecked(false); show:GetScript('OnClick')(show)
                    assert(not ns.db.showTracker and not Buffeteria_Tracker:IsShown())
                    show:SetChecked(true); show:GetScript('OnClick')(show)
                    assert(ns.db.showTracker and Buffeteria_Tracker:IsShown())
                    local mode = findWidget('Missing').parent
                    mode:GetScript('OnClick')(mode)
                    assert(ns.db.buffDisplay == 'MISSING' and mode:GetChecked())
                    assert(not findWidget('Missing or expiring').parent:GetChecked())
                    assert(findWidget('Icons per row'):IsVisible())
                    for columns = 2, 4 do
                        local selected
                        for _, w in ipairs(widgets) do
                            if w.columns == columns and w:IsVisible() then selected = w end
                        end
                        assert(selected); selected:GetScript('OnClick')(selected)
                        assert(ns.db.iconsPerRow == columns and selected:GetChecked())
                        for _, w in ipairs(widgets) do
                            if w.columns and w.columns ~= columns then assert(not w:GetChecked()) end
                        end
                    end
                    Buffeteria_IconSize:SetValue(96)
                    assert(findWidget('Icon position'):IsVisible())
                    for _, side in ipairs({'LEFT', 'TOP', 'RIGHT', 'BOTTOM', 'AUTO'}) do
                        local selected
                        for _, w in ipairs(widgets) do
                            if w.side == side and w:IsVisible() then selected = w end
                        end
                        assert(selected); selected:GetScript('OnClick')(selected)
                        assert(ns.db.iconPosition == side and selected:GetChecked())
                        for _, w in ipairs(widgets) do
                            if w.side and w.side ~= side then assert(not w:GetChecked()) end
                        end
                    end
                    assert(ns.db.iconSize == 96 and Buffeteria_CastButton:GetWidth() == 96)
                    local frame, head = Buffeteria_Tracker, Buffeteria_CastButton
                    local point, width, height = frame.point, frame:GetWidth(), frame:GetHeight()
                    local spell, unit = head:GetAttribute('spell'), head:GetAttribute('*unit1')
                    -- Both settings hosts use the same control, including immediate resizing in combat.
                    COMBAT = true
                    for _, size in ipairs({16, 32, 64, 21}) do
                        Buffeteria_StatusIconSize:SetValue(size)
                        assert(ns.db.statusIconSize == size)
                        local visible = 0
                        for _, w in ipairs(widgets) do
                            if w.parent == frame and w.key and w.tex and w:IsShown() then
                                visible = visible + 1
                                assert(w:GetWidth() == size and w:GetHeight() == size)
                            end
                        end
                        assert(visible > 0)
                        assert(frame.point == point and frame:GetWidth() == width and frame:GetHeight() == height)
                        assert(head:GetWidth() == 96 and head:GetAttribute('spell') == spell and head:GetAttribute('*unit1') == unit)
                    end
                    COMBAT = false
                    settingsPage:GetScript('OnShow')(settingsPage)
                    assert(findWidget('Tracker settings'):IsVisible())
                    assert(tab.parent.parent == settingsPage)
                    ns.Options.Toggle()
                    assert(tab.parent.parent == Buffeteria_Prefs)
                    local personal = findWidget('My preferences').parent
                    personal:GetScript('OnClick')(personal)
                    assert(findWidget('Blessings'):IsVisible())
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
            ns.Tracker.Compute = function() return s end
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
                    assert(head:GetAttribute('spell') == action.spell and head:GetAttribute('*unit1') == action.unit)
                end
            end
            s.perKey = {}; ns.Tracker.Refresh()
            assert(frame:GetHeight() == 100)
            ns.db.iconSize = 100
            COMBAT = true; ns.Tracker.Refresh()
            assert(head:GetWidth() == 96 and frame:GetWidth() == 100)
            COMBAT = false
            ns.App:GetScript('OnEvent')(ns.App, 'PLAYER_REGEN_ENABLED')
            assert(head:GetWidth() == 100 and frame:GetWidth() == 104)
        """)

    def test_head_shows_whether_it_is_your_turn_or_you_are_waiting(self):
        lua = full_addon()
        lua.execute("""
            local frame, head = Buffeteria_Tracker, Buffeteria_CastButton
            -- Something to cast: halo behind the face and a click prompt.
            ns.Tracker.Refresh()
            local action = ns.Tracker.Summary().next
            assert(action and head.halo:IsShown() and not head.glow)
            assert(head.halo.texture:find('OrcColoredGlow$') and head.icon:GetAlpha() == 1)
            assert(frame.gief:IsShown())
            assert(frame.gief:GetText() == 'GIEF ' .. ns.Buffs.byKey[action.key].label .. '!')
            assert(frame.tag.point[2] == frame.gief) -- DEV sits above the demand
            assert(frame.gief.font[2] == ns.db.shoutSize)
            ns.db.shoutSize = 22; ns.Tracker.Refresh()
            assert(frame.gief.font[2] == 22 and frame.gief.font[3] == 'OUTLINE')
            -- Run a few animation frames, including the flare.
            local pulse
            for _, w in ipairs(widgets) do
                if w.parent == frame and w.kind == 'Frame' and w:GetScript('OnUpdate') and w:IsShown() then pulse = w end
            end
            for i = 0, 4 do WOW_TIME = WOW_TIME + 0.1; pulse:GetScript('OnUpdate')(pulse) end
            assert(head.halo.width > head:GetWidth())
            -- Annoyed glows a soft orange; angry glows full red.
            local compute = ns.Tracker.Compute
            local function glowFor(bad)
                ns.Tracker.Compute = function()
                    return {any=true, overall='bad', problems={}, yours={FORT=true}, needs={},
                        next=action, perKey={FORT={bad=bad, warn=0, total=2, casters={}}}}
                end
                ns.Tracker.Refresh()
                pulse:GetScript('OnUpdate')(pulse)
                return head.halo.vertexColor, head.halo:GetAlpha()
            end
            local c, annoyed = glowFor(1)
            assert(c[1] == 1 and c[2] > 0.5 and c[3] < 0.2)
            local c2, angry = glowFor(2)
            assert(c2[1] == 1 and c2[2] < 0.2 and annoyed < angry)
            ns.Tracker.Compute = compute
            -- Nothing to cast: no glow, but the head never fades.
            local s = {any=true, overall='bad', problems={}, yours={KINGS=true},
                needs={{key='FORT', status='bad', caster='B-Realm'}}, perKey={
                FORT={bad=1, warn=0, total=2, casters={['B-Realm']=true}},
                INT={bad=1, warn=0, total=2, casters={['B-Realm']=true}},
                KINGS={bad=1, warn=0, total=2, casters={['A-Realm']=true}},
            }}
            ns.Tracker.Compute = function() return s end
            ns.db.buffDisplay = 'ALL'; ns.Tracker.Refresh()
            assert(not head.glow and not head.halo:IsShown())
            assert(not frame.gief:IsShown() and frame.tag.point[2] == frame)
            assert(head.icon:GetAlpha() == 1)
            local alpha = {}
            for _, w in ipairs(widgets) do
                if w.parent == frame and w.key and w.tex and w:IsShown() then alpha[w.key] = w:GetAlpha() end
            end
            assert(alpha.FORT == 1 and alpha.KINGS == 1 and alpha.INT < 1)
            -- The badge: my pending count, a check when done, nothing with no job.
            s.mine = {total=3, pending=2}; ns.Tracker.Refresh()
            assert(head.owed:IsShown() and head.owed:GetText() == 2 and not head.done:IsShown())
            assert(head.owed.font[2] == math.floor(head:GetWidth() * 0.18 + 0.5) and head.owed.font[3] == 'OUTLINE')
            s.mine = {total=3, pending=0}; ns.Tracker.Refresh()
            assert(head.done:IsShown() and not head.owed:IsShown())
            assert(head.done.width == math.floor(head:GetWidth() * 0.16 + 0.5) and head.done:GetAlpha() < 1)
            assert(head.done.point[1] == 'TOPRIGHT' and head.done.point[2] == head)
            -- Beside the remove-unwanted-buff button, which owns the corner.
            s.cancel = 'Blessing of Salvation'; ns.Tracker.Refresh()
            assert(Buffeteria_CancelButton:IsShown() and head.done.point[2] == Buffeteria_CancelButton)
            s.cancel = nil
            s.mine = {total=0, pending=0}; ns.Tracker.Refresh()
            assert(not head.done:IsShown() and not head.owed:IsShown())
            -- The tooltip names who I'm waiting for.
            local lines = {}
            local add = GameTooltip.AddDoubleLine
            GameTooltip.AddDoubleLine = function(_, l, r) lines[#lines + 1] = r end
            head:GetScript('OnEnter')(head)
            GameTooltip.AddDoubleLine = add
            assert(table.concat(lines, ';'):find('from', 1, true))
            COMBAT = true; ns.Tracker.Refresh()
            assert(head.icon:GetAlpha() == 1 and not frame.gief:IsShown())
            COMBAT = false
        """)

    def test_preview_shows_gief_only_for_classes_with_something_to_cast(self):
        for player_class, gief in (("PALADIN", True), ("PRIEST", True), ("WARRIOR", False), ("ROGUE", False)):
            with self.subTest(player_class=player_class):
                lua = full_addon(player_class)
                lua.execute("""
                    ns.Tracker.Preview.Set(true)
                    WOW_TIME = 100; ns.Tracker.Refresh()
                    local s, frame = ns.Tracker.Summary(), Buffeteria_Tracker
                    assert(frame.gief:IsShown() == %s and Buffeteria_CastButton.halo:IsShown() == %s)
                    assert((s.next ~= nil) == %s and (#s.needs > 0) ~= %s)
                    assert(Buffeteria_CastButton.owed:IsShown() == %s)
                    ns.Tracker.Preview.Set(false)
                """ % ((("true" if gief else "false"),) * 5))

    def test_tracker_icons_keep_color_and_share_status_borders_for_buffs_and_auras(self):
        lua = full_addon()
        lua.execute("""
            local frame = Buffeteria_Tracker
            local s = {any=true, overall='bad', problems={}, perKey={}}
            ns.Tracker.Compute = function() return s end
            local keys = {'CONC', 'DEVO', 'FORT', 'INT', 'KINGS'}
            -- Reuse every icon across healthy, expiring, and missing states.
            for _, status in ipairs({'ok', 'warn', 'bad', 'ok'}) do
                for _, key in ipairs(keys) do
                    s.perKey[key] = {bad=status == 'bad' and 1 or 0,
                                    warn=status ~= 'ok' and 1 or 0, total=2}
                end
                for _, mode in ipairs({'ALL', 'PROBLEMS', 'MISSING', 'EXPIRING'}) do
                    ns.db.buffDisplay = mode; ns.Tracker.Refresh()
                    local visible = 0
                    for _, w in ipairs(widgets) do
                        if w.parent == frame and w.key and w.tex and w:IsShown() then
                            visible = visible + 1
                            assert(w.key == keys[visible]) -- no type-specific grouping
                            assert(w.tex.desaturated == false)
                            local color = ns.Tracker.Status.COLORS[status]
                            for i = 1, 3 do assert(w.borderColor[i] == color[i]) end
                        end
                    end
                    local shown = mode == 'ALL' or (status ~= 'ok' and mode ~= 'MISSING')
                                  or (status == 'bad' and mode == 'MISSING')
                    assert(visible == (shown and #keys or 0))
                end
            end
        """)

    def test_mascot_textures_have_matching_dimensions_and_real_transparency(self):
        for name in (prefix + variant + mood for prefix in ("Orc", "Gnome", "NightElf", "Tauren", "Human", "Troll", "Undead", "Xaryu")
                     for variant in ("", "Colored")
                     for mood in ("Happy", "Grumpy", "Angry", "Glow")):
            with self.subTest(name=name):
                data = (ROOT / "Media" / f"{name}.tga").read_bytes()
                image_type = data[2]
                width, height, depth, descriptor = struct.unpack_from("<HHBB", data, 12)
                self.assertEqual((image_type, width, height, depth), (2, 256, 256, 32))
                self.assertEqual(descriptor & 15, 8)
                start = 18 + data[0]
                alpha = data[start + 3:start + width * height * 4:4]
                self.assertEqual(len(alpha), width * height)
                self.assertIn(0, alpha)
                self.assertGreaterEqual(max(alpha), 250)
                for corner in (0, width - 1, (height - 1) * width, height * width - 1):
                    self.assertEqual(alpha[corner], 0)

    def test_colored_hair_defaults_and_saved_opt_out_survive_login(self):
        for addon_name in ("Buffeteria", DEV_NAME):
            for saved in (None, True, False):
                with self.subTest(addon_name=addon_name, saved=saved):
                    lua = full_addon(login=False, addon_name=addon_name)
                    lua.globals().SAVED_HAIR = saved
                    lua.execute("""
                        _G[ns.savedVariable].coloredHair = SAVED_HAIR
                        ns.Database.Init()
                        assert(ns.db.coloredHair == (SAVED_HAIR ~= false))
                        ns.App:GetScript('OnEvent')(ns.App, 'PLAYER_LOGIN'); runTimers()
                        ns.Database.Init()
                        assert(ns.db.coloredHair == (SAVED_HAIR ~= false))
                        local variant = ns.db.coloredHair and 'Colored' or ''
                        assert(ns.Tracker.Art.Texture('happy') == ns.mediaPath .. 'Orc' .. variant .. 'Happy')
                    """)

    def test_colored_hair_toggle_updates_all_portraits_and_preserves_cast_in_combat(self):
        for addon_name in ("Buffeteria", DEV_NAME):
            with self.subTest(addon_name=addon_name):
                lua = full_addon(addon_name=addon_name)
                lua.execute("""
                    ns.Options.Toggle()
                    findWidget('Settings').parent:GetScript('OnClick')(findWidget('Settings').parent)
                    local toggle = findWidget('Colored hair').parent
                    local picker = _G[ns.globalPrefix .. '_HeadPicker']
                    local head = _G[ns.globalPrefix .. '_CastButton']
                    local frame = _G[ns.globalPrefix .. '_Tracker']
                    assert(toggle:IsVisible() and toggle:GetChecked())
                    local compute = ns.Tracker.Compute
                    local s = ns.Tracker.Summary()
                    assert(s.next and head:GetAttribute('spell'))
                    local spell, unit, point = head:GetAttribute('spell'), head:GetAttribute('*unit1'), frame.point
                    COMBAT = true
                    for _, enabled in ipairs({false, true, false}) do
                        toggle:SetChecked(enabled)
                        toggle:GetScript('OnClick')(toggle)
                        assert(ns.db.coloredHair == enabled)
                        local variant = enabled and 'Colored' or ''
                        for _, choice in ipairs(ns.Tracker.Art.CHOICES) do
                            ns.Database.Set('headStyle', choice.key)
                            assert(picker.portrait.texture == ns.mediaPath .. choice.prefix .. variant .. 'Happy')
                            for _, w in ipairs(widgets) do
                                if w.style == choice.key then
                                    assert(w.portrait.texture == picker.portrait.texture)
                                end
                            end
                            assert(head.halo.texture == ns.mediaPath .. choice.prefix .. variant .. 'Glow')
                            assert(head:GetAttribute('spell') == spell and head:GetAttribute('*unit1') == unit)
                            assert(frame.point == point)
                            for _, entry in ipairs({{'ok', 'Happy'}, {'warn', 'Grumpy'}, {'bad', 'Angry'}}) do
                                ns.Tracker.Compute = function()
                                    return {any=true, overall=entry[1], perKey={FORT={total=1,
                                        bad=entry[1] == 'bad' and 1 or 0, warn=entry[1] == 'warn' and 1 or 0}}, next=s.next}
                                end
                                ns.Tracker.Refresh()
                                assert(head.icon.texture == ns.mediaPath .. choice.prefix .. variant .. entry[2])
                                assert(head.shade.texture == head.icon.texture)
                            end
                            ns.Tracker.Compute = compute
                        end
                    end
                    COMBAT = false
                    ns.Database.Init()
                    settingsPage:GetScript('OnShow')(settingsPage)
                    assert(not ns.db.coloredHair and not toggle:GetChecked())
                    assert(picker.caption:GetText() == 'Head: Xaru' and ns.db.headStyle == 'XARYU')
                """)

    def test_saved_head_choice_defaults_validates_and_survives_login(self):
        for style in (None, "ORC", "GNOME", "NIGHTELF", "TAUREN", "HUMAN", "TROLL", "UNDEAD", "XARYU", "invalid", False):
            with self.subTest(style=style):
                lua = full_addon(login=False)
                lua.globals().SAVED_HEAD = style
                lua.execute("""
                    BuffeteriaCharDB.headStyle = SAVED_HEAD
                    ns.Database.Init()
                    local expected = ({ORC='Orc', GNOME='Gnome', NIGHTELF='NightElf', TAUREN='Tauren', HUMAN='Human', TROLL='Troll', UNDEAD='Undead', XARYU='Xaryu'})[SAVED_HEAD] or 'Orc'
                    assert(ns.db.headStyle == (expected == 'Orc' and 'ORC' or SAVED_HEAD))
                    ns.App:GetScript('OnEvent')(ns.App, 'PLAYER_LOGIN'); runTimers()
                    assert(Buffeteria_CastButton.icon.texture:find(expected .. '%a+$'))
                    ns.Database.Init()
                    assert(ns.Tracker.Art.Glow() == ns.mediaPath .. expected .. 'ColoredGlow')
                    ns.Database.Set('headStyle', 'removed')
                    assert(ns.db.headStyle == 'ORC')
                """)

    def test_head_picker_updates_both_hosts_moods_glow_and_preserves_cast_in_combat(self):
        for addon_name, player_class in (("Buffeteria", "PALADIN"), (DEV_NAME, "ROGUE")):
            with self.subTest(addon_name=addon_name, player_class=player_class):
                lua = full_addon(player_class, addon_name=addon_name)
                lua.execute("""
                    local head, frame = _G[ns.globalPrefix .. '_CastButton'], _G[ns.globalPrefix .. '_Tracker']
                    ns.Options.Toggle()
                    findWidget('Settings').parent:GetScript('OnClick')(findWidget('Settings').parent)
                    local picker = _G[ns.globalPrefix .. '_HeadPicker']
                    local function choiceButton(style)
                        for _, w in ipairs(widgets) do if w.style == style then return w end end
                        error('missing head choice ' .. style)
                    end
                    assert(#ns.Tracker.Art.CHOICES == 8 and picker:IsVisible() and not picker.menu:IsShown())
                    assert(picker.caption:GetText() == 'Head: Orc')
                    local spell, unit, point = head:GetAttribute('spell'), head:GetAttribute('*unit1'), frame.point
                    COMBAT = true
                    for _, choice in ipairs(ns.Tracker.Art.CHOICES) do
                        picker:GetScript('OnClick')(picker)
                        assert(picker.menu:IsShown())
                        local chip = choiceButton(choice.key)
                        assert(chip:IsVisible() and chip.portrait.texture == ns.mediaPath .. choice.prefix .. 'ColoredHappy')
                        chip:GetScript('OnClick')(chip)
                        assert(not picker.menu:IsShown() and picker.caption:GetText() == 'Head: ' .. choice.label)
                        assert(picker.portrait.texture == ns.mediaPath .. choice.prefix .. 'ColoredHappy')
                        assert(ns.db.headStyle == choice.key and chip:GetChecked())
                        for _, other in ipairs(ns.Tracker.Art.CHOICES) do
                            assert(choiceButton(other.key):GetChecked() == (other.key == choice.key))
                        end
                        assert(head.icon.texture == ns.Tracker.Art.Texture(ns.Tracker.Status.Mood(ns.Tracker.Summary())))
                        assert(not head.glow and head.halo.texture == ns.mediaPath .. choice.prefix .. 'ColoredGlow')
                        assert(head:GetAttribute('spell') == spell and head:GetAttribute('*unit1') == unit)
                        assert(frame.point == point and head:GetWidth() == 96)
                    end
                    COMBAT = false
                    settingsPage:GetScript('OnShow')(settingsPage)
                    assert(choiceButton('XARYU'):GetChecked() and picker.caption:GetText() == 'Head: Xaru')
                    picker:GetScript('OnClick')(picker)
                    choiceButton('GNOME'):GetScript('OnClick')(choiceButton('GNOME'))
                    assert(ns.db.headStyle == 'GNOME')
                    ns.Options.Toggle()
                    assert(choiceButton('GNOME'):GetChecked() and picker.caption:GetText() == 'Head: Gnome')
                    picker:GetScript('OnClick')(picker)
                    picker:GetScript('OnClick')(picker)
                    assert(not picker.menu:IsShown())
                    ns.Tracker.Preview.Set(true)
                    COMBAT = true
                    for _, choice in ipairs(ns.Tracker.Art.CHOICES) do
                        ns.Database.Set('headStyle', choice.key)
                        for phase, suffix in ipairs({'Angry', 'Grumpy', 'Grumpy', 'Happy'}) do
                            WOW_TIME = 100 + (phase - 1) * 5
                            ns.Tracker.Refresh()
                            assert(head.icon.texture == ns.mediaPath .. choice.prefix .. 'Colored' .. suffix)
                            assert(not head.glow)
                            assert(head.halo.texture == ns.mediaPath .. choice.prefix .. 'ColoredGlow')
                            assert(not head.icon.desaturated and not head:GetAttribute('spell') and not head:GetAttribute('*unit1'))
                        end
                    end
                    COMBAT = false
                    ns.Tracker.Preview.Set(false)
                    local compute = ns.Tracker.Compute
                    ns.Tracker.Compute = function() return {any=false, overall='idle', perKey={}} end
                    ns.Tracker.Refresh()
                    assert(head.icon.texture:find('XaryuColoredGrumpy$') and head.icon.desaturated)
                    assert(not head.halo:IsShown() and not head.glow)
                    ns.Tracker.Compute = compute
                """)

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
                    assert(ns.Assignments.roster.members['A-Realm'].class == PLAYER_CLASS)
                    assert(ns.Assignments.result.expected['A-Realm'])
                    assert(ns.Tracker.Summary().any)
                    assert(#tickers == 2) -- comm retry and tracker; the minimap listens for summaries
                    for _, message in ipairs(delivered) do assert(#message <= 255) end
                    SlashCmdList.BUFFETERIA('show'); assert(ns.db.showTracker)
                    SlashCmdList.BUFFETERIA('hide'); assert(not ns.db.showTracker)
                    SlashCmdList.BUFFETERIA('lock'); assert(ns.db.locked)
                    SlashCmdList.BUFFETERIA('minimap'); assert(ns.db.minimap.hide)
                    ns.db.blessingsOverride = true
                    SlashCmdList.BUFFETERIA('reset'); runTimers()
                    assert(not ns.db.blessingsOverride)
                    SlashCmdList.BUFFETERIA(''); assert(Buffeteria_Prefs:IsShown())
                    assert(findWidget('Paladins').parent:IsVisible() == (PLAYER_CLASS == 'PALADIN'))
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
            ns.Preferences.Changed() -- refreshes the open view at once
            refreshes = 0
            ns.Assignments.Resolve(); ns.Assignments.Resolve()
            assert(#timers == 1) -- resolving repeated changes is debounced
            runTimers()
            assert(refreshes == 1 and ns.Tracker.Summary().any)
        """)

    def test_orc_moods_distinguish_partial_empty_and_unreadable_buffs(self):
        lua = runtime()
        load(lua, "Features/Tracker/Status.lua")
        lua.execute("""
            local mood = ns.Tracker.Status.Mood
            assert(mood({any = false, overall = 'idle', perKey = {}}) == 'idle')
            local s = {any = true, overall = 'bad', perKey = {
                FORT = {bad = 2, warn = 0, total = 2},
                INT = {bad = 1, warn = 0, total = 2},
            }}
            assert(mood(s) == 'grumpy') -- a missing buff is not an empty group
            s.perKey.INT.bad = 2
            assert(mood(s) == 'angry')
            s.perKey.INT = {bad = 1, warn = 0, total = 2, unknown = 1}
            assert(mood(s) == 'angry') -- every readable pair is missing
            s.perKey.INT.bad = 0
            assert(mood(s) == 'grumpy')
            s.overall = 'ok'
            s.perKey = {FORT = {bad = 0, warn = 0, total = 2, unknown = 2}}
            assert(mood(s) == 'idle') -- nothing readable: can't judge
            s.perKey.FORT.unknown = 1
            assert(mood(s) == 'happy') -- out-of-range players don't upset him
            s.perKey.FORT.unknown = 0
            assert(mood(s) == 'happy')
            s.overall = 'warn'; s.perKey.FORT.warn = 1
            assert(mood(s) == 'grumpy')
        """)

    def test_preview_cycles_orc_artwork_without_casting_and_updates_in_combat(self):
        lua = full_addon()
        lua.execute("""
            ns.Tracker.Preview.Set(true)
            local expected = {'Angry', 'Grumpy', 'Grumpy', 'Happy'}
            for phase, suffix in ipairs(expected) do
                WOW_TIME = 100 + (phase - 1) * 5
                ns.Tracker.Refresh()
                assert(Buffeteria_CastButton.icon.texture ==
                    'Interface\\\\AddOns\\\\Buffeteria\\\\Media\\\\OrcColored' .. suffix)
                assert(not Buffeteria_CastButton.icon.desaturated)
                assert(not Buffeteria_CastButton:GetAttribute('spell'))
                assert(not Buffeteria_CastButton:GetAttribute('*unit1'))
            end
            COMBAT = true
            WOW_TIME = 120
            ns.Tracker.Refresh()
            assert(Buffeteria_CastButton.icon.texture:find('OrcColoredAngry$'))
            assert(not Buffeteria_CastButton:GetAttribute('spell'))
            COMBAT = false
            ns.Tracker.Preview.Set(false)
        """)

    def test_unreadable_observations_do_not_count_toward_mood(self):
        lua = full_addon(login=False)
        lua.execute("""
            UnitIsVisible = function() return false end
            ns.App:GetScript('OnEvent')(ns.App, 'PLAYER_LOGIN'); runTimers()
            local s = ns.Tracker.Summary()
            assert(s.any and s.perKey.KINGS.unknown == s.perKey.KINGS.total)
            assert(ns.Tracker.Status.Mood(s) == 'angry') -- only my own missing aura is readable
            C_UnitAuras.GetAuraDataByIndex = function(unit, i)
                if unit == 'player' and i == 1 then return {name='19746', expirationTime=0, sourceUnit='player'} end
            end
            ns.Tracker.Refresh()
            assert(ns.Tracker.Status.Mood(ns.Tracker.Summary()) == 'happy') -- the rest is out of range
            assert(#ns.Tracker.Summary().unreadable == 2)
        """)

    def test_out_of_range_member_is_listed_but_does_not_upset_orc(self):
        lua = full_addon()
        lua.execute("""
            local me, far = 'A-Realm', 'B-Realm'
            -- Give me every buff I'm expected to have, with my aura cast by me.
            local mine = {}
            for key in pairs(ns.Assignments.result.expected[me]) do mine[#mine + 1] = ns.Buffs.byKey[key].ids[1] end
            for _, key in pairs(ns.Assignments.result.auras or {}) do mine[#mine + 1] = ns.Buffs.byKey[key].ids[1] end
            C_UnitAuras.GetAuraDataByIndex = function(unit, i)
                if unit == 'player' and mine[i] then
                    return {name=tostring(mine[i]), expirationTime=0, sourceUnit='player'}
                end
            end
            -- B was read in range once (missing everything), then walked away.
            ns.Tracker.Refresh()
            assert(ns.Tracker.Status.Mood(ns.Tracker.Summary()) ~= 'happy')
            UnitIsVisible = function(unit) return unit == 'player' end
            ns.Tracker.Refresh()
            local s = ns.Tracker.Summary()
            assert(#s.unreadable == 1 and s.unreadable[1] == far)
            for _, p in ipairs(s.problems) do assert(p.who ~= far) end -- no stale read
            assert(ns.Tracker.Status.Mood(s) == 'happy')
            assert(Buffeteria_CastButton.icon.texture:find('OrcColoredHappy$'))
            local lines = {}
            local add = GameTooltip.AddDoubleLine
            GameTooltip.AddDoubleLine = function(_, l, r) lines[#lines + 1] = r end
            Buffeteria_CastButton:GetScript('OnEnter')(Buffeteria_CastButton)
            GameTooltip.AddDoubleLine = add
            assert(table.concat(lines, ';'):find('out of range', 1, true))
            -- Back in range without his buffs: orange again, naming what he misses.
            UnitIsVisible = function() return true end
            ns.Tracker.Refresh()
            s = ns.Tracker.Summary()
            assert(#s.unreadable == 0 and ns.Tracker.Status.Mood(s) == 'grumpy')
            local named = false
            for _, p in ipairs(s.problems) do if p.who == far and p.status == 'bad' then named = true end end
            assert(named)
        """)

    def test_preview_and_combat_preserve_secure_button_behavior(self):
        lua = full_addon()
        lua.execute("""
            assert(Buffeteria_CastButton:GetAttribute('spell'))
            assert(Buffeteria_CastButton:GetAttribute('type2') == 'macro')
            assert(Buffeteria_CastButton:GetAttribute('macrotext2') == '')
            ns.Tracker.Preview.Set(true)
            assert(not Buffeteria_CastButton:GetAttribute('spell'))
            assert(not Buffeteria_CastButton:GetAttribute('*unit1'))
            assert(not Buffeteria_CancelButton:GetAttribute('spell'))
            assert(not Buffeteria_CancelButton:IsShown())
            ns.Tracker.Preview.Set(false)
            local spell, unit = Buffeteria_CastButton:GetAttribute('spell'), Buffeteria_CastButton:GetAttribute('*unit1')
            COMBAT = true
            ns.Tracker.Refresh()
            assert(Buffeteria_CastButton:GetAttribute('spell') == spell)
            assert(Buffeteria_CastButton:GetAttribute('*unit1') == unit)
            COMBAT = false
            ns.App:GetScript('OnEvent')(ns.App, 'PLAYER_REGEN_ENABLED')
            local pending = ns.Tracker.Summary().next
            Buffeteria_CastButton:GetScript('PostClick')(Buffeteria_CastButton, 'LeftButton', false)
            runTimers(); ns.Tracker.Refresh()
            local same = ns.Tracker.Summary().next
            assert(same.who == pending.who and same.key == pending.key)
            -- Another spell, or the right one long after the click, isn't the button's.
            local frame = Buffeteria_Tracker
            frame:GetScript('OnEvent')(frame, 'UNIT_SPELLCAST_SUCCEEDED', 'player', 'guid', 1)
            WOW_TIME = WOW_TIME + 2
            frame:GetScript('OnEvent')(frame, 'UNIT_SPELLCAST_SUCCEEDED', 'player', 'guid', pending.spellID)
            assert(ns.Tracker.Summary().next.who == pending.who)
            Buffeteria_CastButton:GetScript('PostClick')(Buffeteria_CastButton, 'LeftButton', false)
            frame:GetScript('OnEvent')(frame, 'UNIT_SPELLCAST_SUCCEEDED', 'player', 'guid', pending.spellID)
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
            assert(findWidget('My preferences').parent.parent.parent == settingsPage)
            ns.Options.Toggle()
            assert(findWidget('My preferences').parent.parent.parent == Buffeteria_Prefs)
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
            ns.Tracker.Actions.MarkCast = function() casts = casts + 1 end
            local function landed()
                local frame = Buffeteria_Tracker
                frame:GetScript('OnEvent')(frame, 'UNIT_SPELLCAST_SUCCEEDED', 'player', 'guid', button.pending.spellID)
            end
            ns.Options.Toggle = function() toggles = toggles + 1 end
            button:GetScript('OnMouseDown')(button)
            assert(button.icon.vertexColor[1] == 0.75)
            button:GetScript('PostClick')(button, 'LeftButton', true)
            assert(casts == 0)
            button:GetScript('OnMouseUp')(button)
            button:GetScript('PostClick')(button, 'LeftButton', false)
            assert(casts == 0) -- not yet: the cast may still fail (global cooldown)
            landed()
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
            landed()
            assert(casts == 2)
            button:GetScript('OnLeave')(button)
            assert(button.icon.vertexColor[1] == 1)
        """)

    def test_tracker_holds_presses_during_global_cooldown(self):
        lua = full_addon()
        lua.execute("""
            local button, frame = Buffeteria_CastButton, Buffeteria_Tracker
            local errorsOn = true
            UIErrorsFrame = {
                UnregisterEvent = function(_, e) assert(e == 'UI_ERROR_MESSAGE'); errorsOn = false end,
                RegisterEvent = function(_, e) assert(e == 'UI_ERROR_MESSAGE'); errorsOn = true end,
            }
            local cd = { startTime = 0, duration = 0 }
            C_Spell.GetSpellCooldown = function() return cd end
            local function press(mouseButton)
                local typeDuringClick
                button:GetScript('PreClick')(button, mouseButton or 'LeftButton', false)
                typeDuringClick = button:GetAttribute('*type1')
                local errorsDuringClick = errorsOn
                button:GetScript('PostClick')(button, mouseButton or 'LeftButton', false)
                return typeDuringClick, errorsDuringClick
            end
            assert(button.pending)
            -- Ready: the press casts, and is remembered for the cast that lands.
            local t, e = press()
            assert(t == nil and e and button.clickedAt == WOW_TIME)
            -- Global cooldown: the press does nothing at all.
            button.clickedAt = nil
            cd = { startTime = WOW_TIME - 0.5, duration = 1.5 }
            t, e = press()
            assert(t == '' and e and not button.clickedAt)
            assert(not button:GetAttribute('*type1'))
            -- The shadow covers the part still to wait, draining from the top.
            frame:GetScript('OnEvent')(frame, 'SPELL_UPDATE_COOLDOWN')
            local shade = button.shade
            assert(shade:IsShown() and shade.texture == button.icon.texture)
            assert(math.abs(shade.height - button:GetHeight() * 2 / 3) < 1e-6)
            assert(math.abs(shade.texCoord[3] - 1 / 3) < 1e-6 and shade.texCoord[4] == 1)
            -- Pressing the head doesn't look like a press.
            button.icon.vertexColor = { 1, 1, 1 }
            button:GetScript('OnMouseDown')(button)
            assert(button.icon.vertexColor[1] == 1)
            button:GetScript('OnMouseUp')(button)
            -- Right-click still opens options while the cooldown runs.
            local toggles = 0
            ns.Options.Toggle = function() toggles = toggles + 1 end
            t = press('RightButton')
            assert(t == nil and toggles == 1)
            -- Once it ends, presses cast again.
            WOW_TIME = WOW_TIME + 1
            frame:GetScript('OnEvent')(frame, 'SPELL_UPDATE_COOLDOWN')
            assert(not shade:IsShown() and not button.inert)
            button:GetScript('OnMouseDown')(button)
            assert(button.icon.vertexColor[1] < 1)
            button:GetScript('OnMouseUp')(button)
            t = press()
            assert(t == nil and button.clickedAt == WOW_TIME)
            -- In combat attributes are locked: the press goes through quietly.
            cd = { startTime = WOW_TIME, duration = 1.5 }
            COMBAT = true
            t, e = press()
            assert(t == nil and not e and errorsOn)
            -- Hidden cooldowns fall back to the time since my last cast.
            C_Spell.GetSpellCooldown = nil
            frame:GetScript('OnEvent')(frame, 'UNIT_SPELLCAST_SUCCEEDED', 'player', 'guid', 1)
            assert(shade:IsShown() and button.inert)
            t, e = press()
            assert(not e and errorsOn)
            WOW_TIME = WOW_TIME + 2
            t, e = press()
            assert(e)
            COMBAT = false
            -- After the last buff the cooldown still runs out on the face, and
            -- with nothing to cast the head never looks pressed.
            C_Spell.GetSpellCooldown = function() return cd end
            cd = { startTime = WOW_TIME, duration = 1.5 }
            button.lastCast, button.pending = button.pending, nil
            frame:GetScript('OnEvent')(frame, 'SPELL_UPDATE_COOLDOWN')
            assert(shade:IsShown())
            WOW_TIME = WOW_TIME + 2
            frame:GetScript('OnEvent')(frame, 'SPELL_UPDATE_COOLDOWN')
            assert(not shade:IsShown() and button.inert)
            button:GetScript('OnMouseDown')(button)
            assert(button.icon.vertexColor[1] == 1)
            t = press()
            assert(t == nil and not button.held)
        """)

    def test_tracker_shows_cast_cursor_only_when_clickable(self):
        lua = full_addon()
        lua.execute("""
            local button, frame = Buffeteria_CastButton, Buffeteria_Tracker
            local cursor
            local CAST = 'CAST_CURSOR'
            SetCursor = function(c) cursor = c end
            ResetCursor = function() cursor = nil end
            local cd = { startTime = 0, duration = 0 }
            C_Spell.GetSpellCooldown = function() return cd end
            assert(button.pending and button:GetAttribute('*unit1'))
            -- No plain unit attribute: the client would treat the head as a unit
            -- frame and take over the cursor for that mouseover unit.
            assert(button:GetAttribute('unit') == nil)
            -- Set after the tooltip, whose showing resets the cursor.
            local show = GameTooltip.Show
            GameTooltip.Show = function(...) ResetCursor(); return show(...) end
            button:GetScript('OnEnter')(button)
            GameTooltip.Show = show
            assert(cursor == CAST)
            -- The client taking the cursor back doesn't stick while hovered.
            ResetCursor()
            for _, w in ipairs(widgets) do
                local tick = w.parent == frame and w:IsShown() and w:GetScript('OnUpdate')
                if tick then tick(w) end
            end
            assert(cursor == CAST)
            -- The global cooldown makes the head inert: back to the normal cursor.
            cd = { startTime = WOW_TIME, duration = 1.5 }
            frame:GetScript('OnEvent')(frame, 'SPELL_UPDATE_COOLDOWN')
            assert(cursor == nil)
            WOW_TIME = WOW_TIME + 2
            frame:GetScript('OnEvent')(frame, 'SPELL_UPDATE_COOLDOWN')
            assert(cursor == CAST)
            -- Dragging and leaving restore it.
            button:GetScript('OnMouseDown')(button)
            button:GetScript('OnDragStart')(button)
            assert(cursor == nil)
            button:GetScript('OnDragStop')(button)
            assert(cursor == CAST)
            button:GetScript('OnLeave')(button)
            assert(cursor == nil)
            -- Nothing to cast: no cast cursor, and others' cursors are left alone.
            button.pending = nil
            frame:GetScript('OnEvent')(frame, 'SPELL_UPDATE_COOLDOWN')
            button:GetScript('OnEnter')(button)
            assert(cursor == nil)
            cursor = 'UI_MOVE_CURSOR'
            button:GetScript('OnLeave')(button)
            assert(cursor == 'UI_MOVE_CURSOR')
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

    def test_announce_bursts_collapse_and_plan_messages_skip_roster_rebuilds(self):
        lua = full_addon()
        lua.execute("""
            runTimers(); delivered = {}
            WOW_TIME = WOW_TIME + 1 -- inside the anti-spam window of the login broadcast
            for _ = 1, 10 do ns.Comm.Announce() end
            assert(#timers == 1)
            runTimers()
            local states = 0
            for _, message in ipairs(delivered) do if message:sub(1, 2) == 'S|' then states = states + 1 end end
            assert(states == 1)
            local builds, build = 0, ns.Roster.Build
            ns.Roster.Build = function() builds = builds + 1; return build() end
            ns.Comm.OnMessage('BUFFETERIA', 'P|2|B-Realm|1|KINGS|5000|B-Realm', 'PARTY', 'B-Realm')
            assert(builds == 0 and ns.Paladins.Get('B-Realm', 'WARRIOR') == 'KINGS')
        """)

    def test_every_settings_entry_point_updates_open_controls(self):
        lua = full_addon()
        lua.execute("""
            ns.Options.Toggle()
            local tab = findWidget('Settings').parent; tab:GetScript('OnClick')(tab)
            local show, minimap = findWidget('Show tracker').parent, findWidget('Minimap button').parent
            assert(show:GetChecked() and minimap:GetChecked())
            Buffeteria_MinimapButton:GetScript('OnClick')(Buffeteria_MinimapButton, 'RightButton')
            assert(not ns.db.showTracker and not show:GetChecked() and not Buffeteria_Tracker:IsShown())
            SlashCmdList.BUFFETERIA('show'); assert(show:GetChecked() and Buffeteria_Tracker:IsShown())
            SlashCmdList.BUFFETERIA('minimap')
            assert(ns.db.minimap.hide and not minimap:GetChecked() and not Buffeteria_MinimapButton:IsShown())
        """)

    def test_lua51_syntax(self):
        lua = runtime()
        compile_lua = lua.eval("function(s,n) local f,e=loadstring(s,n); assert(f,e) end")
        for path in ROOT.rglob("*.lua"):
            compile_lua(path.read_text(encoding="utf-8"), path.name)

    def solver(self, code):
        lua = runtime()
        load(lua, "Features/Buffs/Catalog.lua")
        load(lua, "Shared/Util.lua")
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
            "App/State.lua", "Shared/Util.lua", "Shared/Events.lua", "Shared/WoW.lua", "Features/Buffs/Catalog.lua",
            "Shared/UI.lua", "Features/Sync/Protocol.lua", "Features/Tracker/Status.lua", "Features/Tracker/Art.lua",
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
            assert(ns.Roster.Build().members['A-Realm'].ranking[1] == 'MIGHT')
            assert(ns.db.order[1] == 'SALV') -- preserve the order for re-enabling
            ns.Roster.peers['B-Realm'] = {caps={KINGS=true},ranking={'SALV'},excluded={},wants={},blessingsOverride=true}
            assert(ns.Roster.Build().members['B-Realm'].blessingsOverride)
            ns.Roster.peers['B-Realm'].blessingsOverride = false
            assert(ns.Roster.Build().members['B-Realm'].ranking[1] == 'WISDOM') -- paladin default
            BuffeteriaCharDB = {}
            ns.App:GetScript('OnEvent')(ns.App, 'ADDON_LOADED', 'Buffeteria')
            assert(not ns.db.blessingsOverride)
        """)

    def test_paladin_editor_and_settings_share_controls(self):
        lua = self.core_runtime()
        lua.execute("""
            ns.App:GetScript('OnEvent')(ns.App, 'ADDON_LOADED', 'Buffeteria')
            ns.Paladins.Init(); ns.Assignments.roster = ns.Roster.Build(); ns.Assignments.result = ns.Solver.Solve(ns.Assignments.roster)
            ns.Tracker.Preview = {active=false}; ns.Tracker.Refresh = function() end
        """)
        for name in ("Features/Tracker/Layout.lua", "Features/Tracker/SettingsPreview.lua", "Features/Tracker/View.lua", "Features/Preferences/RankList.lua", "Features/Preferences/View.lua", "Features/Paladins/View.lua", "Features/Options/Window.lua"):
            load(lua, name)
        lua.execute("""
            ns.Options.Toggle()
            local tab = findWidget('Paladins').parent
            assert(tab:IsVisible())
            tab:GetScript('OnClick')(tab)
            local heading = findWidget('Class blessings')
            assert(heading:IsVisible())
            local columns = heading.parent.columns
            assert(#columns == 2 and columns[1].paladin == 'A-Realm' and columns[2].paladin == 'B-Realm')
            local rows = 0
            for _, w in pairs(columns[1].rows) do
                rows = rows + 1
                IsShiftKeyDown = function() return true end; w:GetScript('OnClick')(w, 'LeftButton'); IsShiftKeyDown = function() return false end
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
            local mine = findWidget('My preferences').parent; mine:GetScript('OnClick')(mine)
            assert(not heading:IsVisible())
            local override = findWidget('Use my ranking').parent
            override:GetScript('OnClick')(override)
            assert(ns.db.blessingsOverride)
            -- Wanted buffs are talent buttons: gold when wanted, grey when not.
            local fort = findWidget('Blessings').parent.parent.wants.FORT
            local wanted = ns.db.wants.FORT and true or false
            fort:GetScript('OnClick')(fort)
            assert((ns.db.wants.FORT and true or false) == not wanted)
            assert(fort.state == (wanted and 'grey' or 'gold'))
            -- The third tree now hosts role-based tank requests.
            assert(findWidget('Tank role'):IsVisible())
            local panel = findWidget('Blessings').parent.parent
            assert(panel.tankButtons.RFURY:IsShown() and panel.tankButtons.THORNS:IsShown())
            panel.roles[2]:GetScript('OnClick')(panel.roles[2]); runTimers()
            assert(ns.db.tankRole == 'TANK' and ns.Preferences.Get().wants.RFURY)
            -- Dragging a blessing lifts it, reorders while moving, and saves on release.
            local list, rankRows, ghost = panel.rankList, panel.rankRows, panel.rankGhost
            local cursor, held = 0, true
            GetCursorPosition = function() return 0, cursor end
            IsMouseButtonDown = function() return held end
            list.top = 500; ns.db.blessingsOverride = false
            local first = ns.db.order[1]
            cursor = 485
            rankRows[1]:GetScript('OnMouseDown')(rankRows[1], 'LeftButton')
            assert(ghost:IsShown() and list:GetScript('OnUpdate'))
            assert(not rankRows[1].text.shown and ghost.text:GetText():find(ns.Buffs.byKey[first].label, 1, true))
            cursor = 409; list:GetScript('OnUpdate')(list, 0.01)
            assert(ns.db.order[3] == first and not ns.db.blessingsOverride)
            assert(rankRows[1].offset ~= 0 and rankRows[2].offset ~= 0)
            held = false
            for _ = 1, 50 do
                local update = list:GetScript('OnUpdate')
                if not update then break end
                update(list, 0.1)
            end
            assert(not list:GetScript('OnUpdate') and not ghost:IsShown())
            assert(ns.db.order[3] == first and ns.db.blessingsOverride)
            assert(rankRows[3].text.shown and rankRows[1].offset == 0)
        """)

    def test_paladin_grid_fits_five_and_scrolls_larger_rosters_in_both_hosts(self):
        lua = full_addon()
        lua.execute("""
            ns.Options.Toggle()
            findWidget('Paladins').parent:GetScript('OnClick')(findWidget('Paladins').parent)
            local panel = findWidget('Class blessings').parent
            assert(#panel.columns == 2 and Buffeteria_Prefs:GetWidth() == 900)
            assert(not panel.scrollbar:IsShown())
            function UnitFullName(unit)
                if unit == 'player' then return 'A', 'Realm' end
                return 'Party' .. unit:match('%d+'), 'Realm'
            end
            GROUP_SIZE = 4
            ns.Assignments.Resolve(); runTimers()
            assert(#panel.columns == 5 and not panel.scrollbar:IsShown())
            assert(panel.columns[5].paladin == 'Party4-Realm')
            for _, column in ipairs(panel.columns) do
                assert(column:GetWidth() >= 130)
                local cells = 0
                for _, cell in pairs(column.rows) do cells = cells + 1; assert(cell:IsVisible()) end
                assert(cells == 9)
            end
            GROUP_SIZE = 9
            ns.Assignments.Resolve(); runTimers()
            assert(#panel.columns == 10 and panel.scrollbar:IsShown())
            panel.viewport:GetScript('OnMouseWheel')(panel.viewport, -1)
            assert(panel.viewport.horizontalScroll > 0)
            panel.scrollbar:SetValue(panel.scrollbar.maximum)
            assert(panel.viewport.horizontalScroll == panel.scrollbar.maximum)
            settingsPage:SetSize(650, 800)
            settingsPage:GetScript('OnShow')(settingsPage)
            assert(panel:GetParent():GetParent() == settingsPage)
            assert(panel:GetParent():GetWidth() == 820 and panel:GetParent().scale < 1)
            settingsPage:SetWidth(1000); settingsPage:GetScript('OnSizeChanged')(settingsPage)
            assert(panel:GetParent():GetWidth() == 968)
            GROUP_SIZE = 0
            ns.Assignments.Resolve(); runTimers()
            assert(panel.columns[1].paladin == 'A-Realm' and not panel.scrollbar:IsShown())
            assert(panel.viewport.horizontalScroll == 0)
            for i = 2, #panel.columns do
                assert(not panel.columns[i]:IsShown() and panel.columns[i].paladin == nil)
            end
            ns.Options.Toggle()
            assert(Buffeteria_Prefs:GetWidth() == 900 and panel:GetParent():GetWidth() == 900)
        """)

    def test_assignment_picker_capabilities_resets_and_departed_paladins(self):
        lua = full_addon()
        lua.execute("""
            ns.Options.Toggle()
            findWidget('Paladins').parent:GetScript('OnClick')(findWidget('Paladins').parent)
            local panel = findWidget('Class blessings').parent
            ns.Assignments.roster.members['A-Realm'].caps = {WISDOM=true}
            ns.Assignments.roster.members['B-Realm'].hasAddon = false
            ns.Events.Emit('AssignmentsChanged')
            local a, b = panel.columns[1].rows.ROGUE, panel.columns[2].rows.ROGUE
            a:GetScript('OnClick')(a, 'LeftButton')
            assert(panel.picker:IsShown() and ns.Paladins.Get('A-Realm', 'ROGUE') == 'AUTO')
            assert(panel.picker.choices[1].key == 'AUTO')
            assert(panel.picker.choices[2].key == 'WISDOM' and panel.picker.choices[3].key == 'NONE')
            panel.picker.choices[2]:GetScript('OnClick')(panel.picker.choices[2]); runTimers()
            assert(ns.Paladins.Get('A-Realm', 'ROGUE') == 'WISDOM' and not panel.picker:IsShown())
            a:GetScript('OnClick')(a, 'RightButton'); runTimers()
            assert(ns.Paladins.Get('A-Realm', 'ROGUE') == 'AUTO' and a.auto:IsShown())
            IsShiftKeyDown = function() return true end
            a:GetScript('OnClick')(a, 'LeftButton'); runTimers()
            IsShiftKeyDown = function() return false end
            assert(ns.Paladins.Get('A-Realm', 'ROGUE') == 'NONE' and not a.auto:IsShown())
            b:GetScript('OnClick')(b, 'LeftButton')
            assert(panel.picker.help:GetText():find('unverified'))
            assert(panel.picker.choices[2].key == 'KINGS')
            panel.picker.choices[2]:GetScript('OnClick')(panel.picker.choices[2]); runTimers()
            assert(ns.Paladins.Get('B-Realm', 'ROGUE') == 'KINGS')
            a:GetScript('OnEnter')(a)
            assert(GameTooltip:GetText() == 'A - ROGUE')
            a:GetScript('OnLeave')(a); assert(not GameTooltip:IsShown())
            b:GetScript('OnClick')(b, 'LeftButton')
            local oldChoice = panel.picker.choices[2]
            ns.Assignments.roster.members = {}
            ns.Events.Emit('AssignmentsChanged')
            assert(findWidget('No paladins in the group'):IsVisible() and not panel.picker:IsShown())
            for _, column in ipairs(panel.columns) do assert(not column:IsShown()) end
            oldChoice:GetScript('OnClick')(oldChoice)
            b:GetScript('OnClick')(b, 'LeftButton')
            assert(ns.Paladins.Get('B-Realm', 'ROGUE') == 'KINGS')
        """)

    def test_non_paladins_do_not_see_assignment_tab(self):
        lua = self.core_runtime("ROGUE")
        lua.execute("""
            ns.App:GetScript('OnEvent')(ns.App, 'ADDON_LOADED', 'Buffeteria')
            ns.Assignments.roster = ns.Roster.Build(); ns.Tracker.Preview = {active=false}
        """)
        for name in ("Features/Tracker/Layout.lua", "Features/Tracker/SettingsPreview.lua", "Features/Tracker/View.lua", "Features/Preferences/RankList.lua", "Features/Preferences/View.lua", "Features/Paladins/View.lua", "Features/Options/Window.lua"):
            load(lua, name)
        lua.execute("ns.Options.Toggle(); assert(not findWidget('Paladins').parent:IsVisible())")

    def test_manual_plan_and_opt_in_priority(self):
        self.solver("""
            local roster = {members={Pal=member('PALADIN', all),
                Offline=member('ROGUE'), Default=member('ROGUE', {}, false),
                Custom=member('ROGUE', {}, true)}, paladinAssignments={ROGUE={Pal='SALV'}}}
            local r = ns.Solver.Solve(roster)
            assert(r.pally.ROGUE.Pal == 'SALV')
            assert(r.expected.Offline.SALV == 'Pal' and r.expected.Default.SALV == 'Pal')
            assert(r.expected.Custom.MIGHT == 'Pal' and r.expected.Custom.SALV == nil)
            assert(r.overrides.Custom.Pal == 'MIGHT')
        """)

    def test_class_defaults_lead_with_role_blessing_and_migrate_untouched_orders(self):
        self.solver("""
            assert(ns.Buffs.DEFAULT_ORDER.WARLOCK[1] == 'WISDOM' and ns.Buffs.DEFAULT_ORDER.WARRIOR[1] == 'MIGHT')
            assert(ns.Buffs.DEFAULT_ORDER.HUNTER[1] == 'KINGS')
            -- One paladin and nobody with the add-on: Auto plans each class's top default.
            local r = ns.Solver.Solve({members={Pal=member('PALADIN', all)}})
            assert(r.pally.WARLOCK.Pal == 'WISDOM' and r.pally.ROGUE.Pal == 'MIGHT' and r.pally.HUNTER.Pal == 'KINGS')
        """)
        lua = self.core_runtime("WARLOCK")
        lua.execute("""
            local legacy = {'KINGS','SALV','WISDOM','LIGHT','SANCT','|','MIGHT'}
            BuffeteriaCharDB = {order={unpack(legacy)}, blessingsOverride=false}
            ns.App:GetScript('OnEvent')(ns.App, 'ADDON_LOADED', 'Buffeteria')
            assert(ns.db.order[1] == 'WISDOM' and not ns.db.blessingsOverride)
            -- Once migrated, a ranking that matches the old default is a choice.
            ns.db.order = {unpack(legacy)}
            ns.App:GetScript('OnEvent')(ns.App, 'ADDON_LOADED', 'Buffeteria')
            assert(ns.db.order[1] == 'KINGS')
            BuffeteriaCharDB = {order={unpack(legacy)}, blessingsOverride=true}
            ns.App:GetScript('OnEvent')(ns.App, 'ADDON_LOADED', 'Buffeteria')
            assert(ns.db.order[1] == 'KINGS' and ns.db.blessingsOverride)
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
        load(lua, "Shared/WoW.lua")
        lua.execute("ns.Preferences = {}; ns.Roster = {}; ns.Assignments = {}")
        load(lua, "Shared/Events.lua")
        load(lua, "Features/Sync/Protocol.lua")
        load(lua, "Features/Tracker/Status.lua")
        lua.execute("""
            function GetNormalizedRealmName() return 'Realm' end
            function GetTime() return 100 end
            function time() return 1000 end
            function UnitClass() return 'Paladin','PALADIN' end
            ns.WoW.FullName = function() return 'A-Realm' end
            ns.db = {paladinBlessings={}}
            ns.Assignments.Resolve = function() ns.solves = (ns.solves or 0) + 1 end
            ns.Assignments.roster = {members={['A-Realm']={class='PALADIN', hasAddon=true, caps={KINGS=true,MIGHT=true}},
                ['B-Realm']={class='PALADIN', hasAddon=true, caps={KINGS=true,MIGHT=true}},
                ['C-Realm']={class='PALADIN', caps={}}, ['R-Realm']={class='ROGUE', caps={}}}}
            ns.Roster.Build = function() return ns.Assignments.roster end
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
            local blessings, _, assumed = ns.Paladins.Assignments(ns.Assignments.roster)
            assert(blessings.ROGUE['C-Realm'] == 'SANCT' and assumed['C-Realm'].SANCT)
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
            assert(ns.Paladins.revision >= oldRevision)
            -- The saved cell keeps its revision, so newer group edits still win.
            assert(ns.Paladins.cells['A-Realm'].ROGUE.key == 'AUTO')
            assert(ns.Paladins.cells['A-Realm'].ROGUE.revision == oldRevision)
            ns.Paladins.Set('A-Realm', 'ROGUE', 'MIGHT')
            assert(ns.Paladins.cells['A-Realm'].ROGUE.revision > oldRevision)
        """)

    def test_edits_made_while_a_paladin_was_away_survive_their_login(self):
        def client(me, other, saved=None):
            lua = full_addon(login=False)
            lua.execute(f"function UnitFullName(u) return u == 'player' and '{me}' or '{other}', 'Realm' end")
            lua.execute("CLOCK = 1000; function time() return CLOCK end")
            if saved:
                lua.globals().ns.db.paladinBlessings = lua.table_from(dict(saved.eval("ns.db.paladinBlessings")))
                cells = lua.table_from({slot: lua.table_from(dict(cell))
                                        for slot, cell in saved.eval("ns.db.paladinCells").items()})
                lua.globals().ns.db.paladinCells = cells
                lua.globals().ns.db.paladinRevision = saved.eval("ns.db.paladinRevision")
                lua.globals().CLOCK = saved.globals().CLOCK + 100
            lua.execute("ns.App:GetScript('OnEvent')(ns.App, 'PLAYER_LOGIN'); runTimers()")
            return lua

        clients = {"A": client("A", "B"), "B": client("B", "A")}

        def exchange(away=()):
            for _ in range(4):
                for sender, receiver in (("A", "B"), ("B", "A")):
                    messages = list(clients[sender].globals().delivered.values())
                    clients[sender].execute("delivered = {}")
                    if receiver in away:
                        continue
                    for message in messages:
                        clients[receiver].globals().ns.Comm.OnMessage("BUFFETERIA", message, "PARTY", sender + "-Realm")
                for lua in clients.values():
                    lua.execute("runTimers()")

        def plan(lua):
            return dict(lua.eval("ns.Assignments.result.pally.WARRIOR").items())

        def edit(name, mine, other):
            lua = clients[name]
            lua.execute("CLOCK = CLOCK + 10")
            lua.execute(f"ns.Paladins.Set(ns.WoW.Me(), 'WARRIOR', '{mine}')")
            peer = "B-Realm" if name == "A" else "A-Realm"
            lua.execute(f"ns.Paladins.Set('{peer}', 'WARRIOR', '{other}'); runTimers()")

        edit("B", "KINGS", "WISDOM")
        exchange()
        edit("A", "KINGS", "WISDOM")
        exchange(away=("B",))
        clients["B"] = client("B", "A", clients["B"])
        exchange()
        expected = {"A-Realm": "KINGS", "B-Realm": "WISDOM"}
        self.assertEqual(plan(clients["A"]), expected)
        self.assertEqual(plan(clients["B"]), expected)
        self.assertEqual(clients["B"].eval("ns.db.paladinBlessings.WARRIOR"), "WISDOM")

    def test_stale_edits_are_answered_and_state_requests_ask_back(self):
        lua = self.plan_runtime()
        lua.execute("""
            ns.Paladins.Set('A-Realm', 'ROGUE', 'KINGS'); sent = {}
            ns.Paladins.Receive('B-Realm', 'A-Realm', '2', 'MIGHT', '500', 'B-Realm')
            assert(#sent == 1 and sent[1]:find('|KINGS|', 1, true) and ns.Paladins.Get('A-Realm', 'ROGUE') == 'KINGS')
            local cell = ns.Paladins.cells['A-Realm'].ROGUE; sent = {}
            ns.Paladins.Receive('B-Realm', 'A-Realm', '2', 'KINGS', tostring(cell.revision), cell.author)
            ns.Paladins.Receive('R-Realm', 'A-Realm', '2', 'MIGHT', '500', 'R-Realm')
            assert(#sent == 0)
        """)
        lua = full_addon()
        lua.execute("""
            GROUP_SIZE = 1; WOW_TIME = WOW_TIME + 20; delivered = {}
            ns.Comm.OnMessage('BUFFETERIA', 'R|2', 'PARTY', 'B-Realm'); runTimers()
            local asked = false
            for _, msg in ipairs(delivered) do asked = asked or msg == 'R|2' end
            assert(asked)
            delivered = {}
            ns.Comm.OnMessage('BUFFETERIA', 'R|2', 'PARTY', 'B-Realm'); runTimers()
            for _, msg in ipairs(delivered) do assert(msg ~= 'R|2') end
        """)

    def test_simultaneous_duplicate_slots_have_one_winner(self):
        lua = self.plan_runtime()
        lua.execute("""
            local a = ns.Paladins
            a.Receive('A-Realm', 'A-Realm', '2', 'KINGS', '2000', 'A-Realm')
            a.Receive('B-Realm', 'B-Realm', '2', 'KINGS', '2000', 'B-Realm')
            local assignments = a.Assignments(ns.Assignments.roster)
            assert(assignments.ROGUE['A-Realm'] == 'NONE' and assignments.ROGUE['B-Realm'] == 'KINGS')
            a.cells = {}
            a.Receive('B-Realm', 'B-Realm', '2', 'KINGS', '2000', 'B-Realm')
            a.Receive('A-Realm', 'A-Realm', '2', 'KINGS', '2000', 'A-Realm')
            assignments = a.Assignments(ns.Assignments.roster)
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
            ns.Assignments.roster.members['B-Realm'] = nil; a.Prune(ns.Assignments.roster)
            assert(a.Get('A-Realm','ROGUE') == 'MIGHT') -- editor leaving keeps the plan
            a.Set('A-Realm','ROGUE','KINGS')
            assert(a.Get('A-Realm','ROGUE') == 'KINGS') -- observed clock advances
            ns.Assignments.roster.members['A-Realm'] = nil; a.Prune(ns.Assignments.roster)
            assert(a.Get('A-Realm','ROGUE') == 'AUTO')
        """)

    def test_message_retry_keeps_every_cell_and_latest_state(self):
        lua = self.plan_runtime()
        load(lua, "Features/Roster/Roster.lua")
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

    def test_names_normalize_across_roster_messages_and_unloaded_units(self):
        lua = runtime()
        lua.execute("ns.title = 'Buffeteria'")
        load(lua, "Shared/WoW.lua")
        lua.execute("""
            function GetNormalizedRealmName() return 'AzjolNerub' end
            local N = ns.WoW.NormalizeName
            assert(N('Bob') == 'Bob-AzjolNerub' and N('Bob-Azjol-Nerub') == 'Bob-AzjolNerub')
            assert(N('Bob-Living Flame') == 'Bob-LivingFlame' and N('') == nil and N(nil) == nil)
            -- Some clients report addon-message senders as "Name Realm".
            assert(N('Bob AzjolNerub') == 'Bob-AzjolNerub' and N('Bob Living Flame') == 'Bob-LivingFlame')
            function UnitFullName(u) if u == 'player' then return 'Me', nil end return 'Unknown', nil end
            assert(ns.WoW.FullName('player') == 'Me-AzjolNerub' and ns.WoW.FullName('party1') == nil)
            -- Realm API not ready yet: fall back to the display realm name.
            GetNormalizedRealmName = function() return nil end
            function GetRealmName() return 'Azjol-Nerub' end
            assert(ns.WoW.FullName('player') == 'Me-AzjolNerub')
        """)

    def test_late_messages_apply_personal_preferences_and_paladin_plan(self):
        lua = full_addon("WARRIOR")
        lua.execute("""
            NAMES = {player='A', party1='Pal', party2='Rogue'}
            CLASSES = {player='WARRIOR', party1='PALADIN', party2='ROGUE'}
            function UnitFullName(u) return NAMES[u], nil end
            function UnitClass(u) return CLASSES[u], CLASSES[u] end
            -- The group is forming: messages arrive before the roster lists the senders.
            GROUP_SIZE = 0
            function IsInGroup(category) return category == nil end
            runTimers()
            ns.Comm.OnMessage('BUFFETERIA', 'S|2||SALV,KINGS|MIGHT,WISDOM,LIGHT,SANCT||1', 'PARTY', 'Rogue')
            ns.Comm.OnMessage('BUFFETERIA', 'S|2||WISDOM,KINGS,SALV,MIGHT,LIGHT,SANCT||KINGS,MIGHT,SALV,WISDOM,gMIGHT,gKINGS|0', 'PARTY', 'Pal-Realm')
            ns.Comm.OnMessage('BUFFETERIA', 'P|2|Pal-Realm|2|MIGHT|5000|Pal-Realm', 'PARTY', 'Pal')
            ns.Comm.OnMessage('BUFFETERIA', 'P|2|Pal-Realm|1|KINGS|5000|Pal-Realm', 'PARTY', 'Pal')
            assert(ns.Paladins.Get('Pal-Realm', 'ROGUE') == 'AUTO')
            GROUP_SIZE = 2
            ns.Assignments.Resolve(); runTimers()
            local r, pal = ns.Assignments.result, 'Pal-Realm'
            assert(ns.Assignments.roster.members[pal].hasAddon)
            assert(ns.Paladins.Get(pal, 'ROGUE') == 'MIGHT' and ns.Paladins.Get(pal, 'WARRIOR') == 'KINGS')
            assert(r.pally.ROGUE[pal] == 'MIGHT' and r.pally.WARRIOR[pal] == 'KINGS')
            -- The rogue's explicit ranking beats the preset; the warrior follows it.
            assert(r.expected['Rogue-Realm'].SALV == pal and r.overrides['Rogue-Realm'][pal] == 'SALV')
            assert(r.expected['A-Realm'].KINGS == pal and not r.overrides['A-Realm'])
            -- A paladin briefly missing from the roster keeps their plan.
            GROUP_SIZE = 1; NAMES.party1 = 'Rogue'; CLASSES.party1 = 'ROGUE'; ns.Assignments.Resolve(); runTimers()
            assert(ns.Paladins.Get(pal, 'ROGUE') == 'MIGHT')
            GROUP_SIZE = 2; NAMES.party1 = 'Pal'; CLASSES.party1 = 'PALADIN'
            ns.Assignments.Resolve(); runTimers()
            assert(ns.Assignments.result.pally.ROGUE[pal] == 'MIGHT')
            -- Leaving the group clears other paladins' cells.
            GROUP_SIZE = 0; IsInGroup = function() return false end; ns.Assignments.Resolve(); runTimers()
            assert(ns.Paladins.Get(pal, 'ROGUE') == 'AUTO')
        """)

    def test_pending_plan_edits_expire_and_never_bypass_validation(self):
        lua = self.plan_runtime()
        lua.execute("""
            local a = ns.Paladins
            a.Receive('D-Realm', 'D-Realm', '2', 'KINGS', '2000', 'D-Realm')
            a.Receive('X-Realm', 'C-Realm', '2', 'KINGS', '2000', 'X-Realm')
            a.Receive('E-Realm', 'E-Realm', '2', 'MIGHT', '2000', 'E-Realm')
            assert(a.Get('D-Realm', 'ROGUE') == 'AUTO')
            ns.Assignments.roster.members['D-Realm'] = {class='PALADIN', caps={}}
            ns.Assignments.roster.members['X-Realm'] = {class='ROGUE', caps={}}
            assert(a.Replay(ns.Assignments.roster))
            assert(a.Get('D-Realm', 'ROGUE') == 'KINGS')
            assert(a.Get('C-Realm', 'ROGUE') == 'AUTO') -- non-paladin editors stay rejected
            function GetTime() return 1000 end
            a.Replay(ns.Assignments.roster)
            ns.Assignments.roster.members['E-Realm'] = {class='PALADIN', caps={}}
            a.Replay(ns.Assignments.roster)
            assert(a.Get('E-Realm', 'ROGUE') == 'AUTO') -- expired before E appeared
        """)

    def test_rejected_messages_do_not_block_the_queue(self):
        lua = self.plan_runtime()
        lua.execute("""
            ns.WoW.Print = function() end
            function IsInGroup(category) return category == nil end
            function IsInRaid() return false end
            function strsplit(sep, str)
                local out = {}; for part in (str..sep):gmatch('(.-)'..sep) do out[#out+1]=part end
                return unpack(out)
            end
            delivered = {}; throttled = true
            C_ChatInfo = {SendAddonMessage=function(_, msg)
                if #msg > 255 then error('message too long') end
                if throttled then return false end
                table.insert(delivered, msg); return 0
            end}
        """)
        load(lua, "Features/Sync/Comm.lua")
        lua.execute("""
            ns.Comm.Send(string.rep('x', 300))
            ns.Comm.Send('P|2|A-Realm|1|KINGS|1|A-Realm')
            ns.Comm.Flush(); assert(#delivered == 0)
            throttled = false; ns.Comm.Flush()
            assert(#delivered == 1 and delivered[1] == 'P|2|A-Realm|1|KINGS|1|A-Realm')
        """)

    def test_party_channel_without_instance_category_and_rejections_do_not_stall(self):
        lua = self.plan_runtime()
        lua.execute("""
            ns.WoW.Print = function(m) printed = m end
            ns.WoW.Short = function(n) return (n:match('^[^-]+')) end
            LE_PARTY_CATEGORY_INSTANCE = nil; LE_PARTY_CATEGORY_HOME = nil
            function IsInGroup(category) return true end
            function IsInRaid() return false end
            function strsplit(sep, str)
                local out = {}; for part in (str..sep):gmatch('(.-)'..sep) do out[#out+1]=part end
                return unpack(out)
            end
            Enum = {SendAddonMessageResult={Success=0, AddonMessageThrottle=3, InvalidChatType=4}}
            delivered = {}; result = 0
            C_ChatInfo = {SendAddonMessage=function(_, msg, chan)
                if result ~= 0 then return result end
                table.insert(delivered, chan .. ':' .. msg); return 0
            end}
        """)
        load(lua, "Features/Sync/Comm.lua")
        lua.execute("""
            assert(ns.Comm.Channel() == 'PARTY')
            ns.Comm.Send('S|2|||||0'); assert(delivered[1] == 'PARTY:S|2|||||0')
            result = 4; ns.Comm.Send('P|2|A-Realm|1|KINGS|1|A-Realm')
            assert(printed:find('InvalidChatType on PARTY'))
            result = 0; ns.Comm.Send('S|2|||||1'); assert(delivered[2] == 'PARTY:S|2|||||1', table.concat(delivered, ' '))
            result = 3; ns.Comm.Send('P|2|A-Realm|2|MIGHT|2|A-Realm'); ns.Comm.Flush(); assert(#delivered == 2, table.concat(delivered, ' '))
            result = 0; ns.Comm.Flush(); assert(delivered[3] == 'PARTY:P|2|A-Realm|2|MIGHT|2|A-Realm')
            ns.Comm.OnMessage('BUFFETERIA', 'X|2', 'PARTY', 'B-Realm')
            local report = table.concat(ns.Comm.Report(), '\\n')
            assert(report:find('channel PARTY, 3 sent, 1 failed, 0 waiting') and report:find('B %(1%)'), report)
            LE_PARTY_CATEGORY_HOME, LE_PARTY_CATEGORY_INSTANCE = 1, 2
            function IsInGroup(category) return category == 2 end
            assert(ns.Comm.Channel() == 'INSTANCE_CHAT')
        """)

    def test_randomized_plans_and_personal_rankings_stay_consistent(self):
        self.solver("""
            local B, KEYS = ns.Buffs, ns.Buffs.BLESSING_KEYS
            local CLASSES = {'WARRIOR', 'ROGUE', 'MAGE', 'PRIEST', 'HUNTER', 'PALADIN'}
            local function shuffled()
                local t = {}
                for i, k in ipairs(KEYS) do t[i] = k end
                for i = #t, 2, -1 do local j = math.random(i); t[i], t[j] = t[j], t[i] end
                table.insert(t, math.random(1, #t + 1), '|')
                return t
            end
            -- Best achievable personal result by brute force, as a 0/1 string in ranking order.
            local function best(m, pals, members, plan)
                local top
                local function rec(i, got, used)
                    if i > #pals then
                        local v = {}
                        for _, b in ipairs(m.ranking) do if not m.excluded[b] then v[#v + 1] = got[b] and 1 or 0 end end
                        local s = table.concat(v)
                        if not top or s > top then top = s end
                        return
                    end
                    local p, c = pals[i], members[pals[i]].caps
                    rec(i + 1, got, used)
                    for _, b in ipairs(m.ranking) do
                        if not used[b] and not m.excluded[b] and (c[b] or (plan[p] == b and c['g' .. b])) then
                            used[b] = true; got[b] = true; rec(i + 1, got, used); used[b] = nil; got[b] = nil
                        end
                    end
                end
                rec(1, {}, {})
                return top
            end
            for seed = 1, 1500 do
                math.randomseed(seed)
                local members, pals, manual = {}, {}, {}
                for i = 1, math.random(1, 4) do
                    local caps = {}
                    for _, k in ipairs(KEYS) do
                        if math.random() < 0.75 then caps[k] = true; if math.random() < 0.7 then caps['g' .. k] = true end end
                    end
                    members['P' .. i] = {class='PALADIN', caps=caps}; pals[i] = 'P' .. i
                end
                for i = 1, math.random(0, 6) do members['M' .. i] = {class=CLASSES[math.random(#CLASSES)], caps={}} end
                for _, m in pairs(members) do
                    m.group, m.wants = 1, {}
                    m.blessingsOverride = math.random() < 0.5
                    m.ranking, m.excluded = B.SplitOrder(m.blessingsOverride and shuffled() or B.DEFAULT_ORDER[m.class])
                end
                for _, class in ipairs(B.CLASS_KEYS) do
                    manual[class] = {}
                    for _, p in ipairs(pals) do
                        local roll = math.random()
                        if roll < 0.15 then manual[class][p] = 'NONE'
                        elseif roll < 0.4 then manual[class][p] = KEYS[math.random(#KEYS)] end
                    end
                end
                local r = ns.Solver.Solve({members=members, paladinAssignments=manual})
                local function knows(p, b) local c = members[p].caps; return c[b] or c['g' .. b] end
                local where = 'seed ' .. seed .. ': '
                for _, class in ipairs(B.CLASS_KEYS) do
                    local plan, seen = r.pally[class] or {}, {}
                    for p, b in pairs(plan) do
                        assert(not seen[b] and knows(p, b) and manual[class][p] ~= 'NONE', where .. 'class plan ' .. class)
                        seen[b] = true
                    end
                    for _, p in ipairs(pals) do
                        local b, claimed = manual[class][p], false
                        for _, q in ipairs(pals) do if q < p and manual[class][q] == b then claimed = true end end
                        if b and b ~= 'NONE' and knows(p, b) and not claimed then
                            assert(plan[p] == b, where .. 'preset ignored ' .. class .. ' ' .. p)
                        end
                    end
                end
                for name, m in pairs(members) do
                    local expected, overrides, plan, got = r.expected[name], r.overrides[name] or {}, r.pally[m.class] or {}, {}
                    for _, p in ipairs(pals) do
                        -- What this paladin actually casts on the member.
                        local b = plan[p]
                        if overrides[p] ~= nil then
                            b = overrides[p] or nil
                            assert(not b or members[p].caps[b], where .. 'single not known')
                        end
                        if b then
                            assert(not got[b] and expected[b] == p, where .. name .. ' tracker mismatch ' .. b)
                            got[b] = p
                        end
                    end
                    for _, b in ipairs(KEYS) do assert(not expected[b] or got[b], where .. name .. ' expects uncast ' .. b) end
                    if m.blessingsOverride then
                        local v = {}
                        for _, b in ipairs(m.ranking) do
                            if not m.excluded[b] then v[#v + 1] = got[b] and 1 or 0 end
                        end
                        for b in pairs(got) do assert(not m.excluded[b], where .. name .. ' excluded ' .. b) end
                        assert(table.concat(v) == best(m, pals, members, plan), where .. name .. ' personal ranking not optimal')
                    end
                end
            end
        """)

    def test_tracker_uses_singles_around_personal_overrides(self):
        lua = runtime()
        load(lua, "Features/Buffs/Catalog.lua")
        load(lua, "Shared/Util.lua")
        lua.execute("ns.WoW = {}; ns.Preferences = {}; ns.Roster = {}")
        load(lua, "Shared/Events.lua")
        load(lua, "Features/Sync/Protocol.lua")
        load(lua, "Features/Tracker/Status.lua")
        load(lua, "Features/Assignments/Assignments.lua")
        lua.execute("""
            function GetTime() return 100 end
            function UnitIsVisible() return true end
            C_UnitAuras = {GetAuraDataByIndex=function() return nil end}
            ns.WoW.FullName = function() return 'Pal' end; ns.WoW.Short = function(n) return n end
            ns.WoW.Me = function() return ns.WoW.FullName('player') end
            ns.WoW.ClassName = function(c) return c end
            ns.WoW.SpellName = function(id) return tostring(id) end
            ns.WoW.SpellIcon = function(id) return id end
            ns.WoW.KnowsAny = function(ids) return true, ids[#ids] end
            ns.WoW.ItemCount = function() return 10 end
            ns.db = {warnMinutes=5}
            ns.Assignments.roster = {members={R={class='ROGUE',unit='party1'}, C={class='ROGUE',unit='party2'}},
                units={R='party1', C='party2'}}
            ns.Assignments.result = {groups={}, auras={}, pally={ROGUE={Pal='KINGS'}},
                expected={R={KINGS='Pal'}, C={MIGHT='Pal'}}, overrides={C={Pal='MIGHT'}}}
        """)
        load(lua, "Features/Tracker/Scan.lua")
        load(lua, "Features/Tracker/Actions.lua")
        lua.execute("""
            local function nextCast() ns.Tracker.Scan.Update(100, 300); return ns.Tracker.Actions.Next(100, 300) end
            local action = nextCast()
            assert(action and not action.big)
            assert(action.spell == '20217')
            ns.Assignments.result.overrides = {}; ns.Assignments.result.expected.C = {KINGS='Pal'}
            action = nextCast()
            assert(action.big and action.spell == '25898')
            ns.Assignments.result.overrides = {C={Pal=false}}; ns.Assignments.result.expected.C = {}
            assert(not nextCast().big)
            ns.WoW.FullName = function() return 'R' end
            ns.Assignments.roster.members.R.excluded = {WISDOM=true}
            ns.Assignments.result.expected.R = {WISDOM='Pal'}
            C_UnitAuras.GetAuraDataByIndex = function(_, i)
                if i == 1 then return {name='25290', expirationTime=0} end
            end
            local summary = ns.Tracker.Scan.Update(100, 300)
            assert(not ns.Tracker.Scan.UnwantedOnMe())
            for _, problem in ipairs(summary.problems) do assert(problem.status ~= 'unwanted') end
            ns.Assignments.result.expected.R = {}
            assert(ns.Tracker.Scan.UnwantedOnMe() == '25290')
        """)


    def test_group_buffs_split_by_work_and_home_group(self):
        self.solver("""
            local function at(m, g) m.group = g; return m end
            local members = {P1=at(member('PRIEST', {FORT=true, gFORT=true}), 1), P2=at(member('PRIEST', {FORT=true}), 2)}
            for i = 1, 4 do members['A' .. i] = at(member('ROGUE'), 1); members['B' .. i] = at(member('ROGUE'), 2) end
            members.C1 = at(member('ROGUE'), 3)
            -- Prayer makes a group one cast for P1; P2 casts singles, so gets the small group.
            local r = ns.Solver.Solve({members=members})
            assert(r.groups.FORT[1] == 'P1' and r.groups.FORT[2] == 'P1' and r.groups.FORT[3] == 'P2')
            assert(r.expected.C1.FORT == 'P2' and r.expected.B1.FORT == 'P1')
            -- Equal work: each priest keeps their own group (in range), whatever the names.
            members.P2.caps.gFORT = true; members.P1.group = 2; members.P2.group = 1; members.C1 = nil
            r = ns.Solver.Solve({members=members})
            assert(r.groups.FORT[1] == 'P2' and r.groups.FORT[2] == 'P1')
        """)

    def tracker_actions(self, setup):
        lua = runtime()
        load(lua, "Features/Buffs/Catalog.lua")
        load(lua, "Shared/Util.lua")
        lua.execute("ns.WoW = {}; ns.Preferences = {}; ns.Roster = {}")
        load(lua, "Shared/Events.lua")
        load(lua, "Features/Sync/Protocol.lua")
        load(lua, "Features/Tracker/Status.lua")
        load(lua, "Features/Assignments/Assignments.lua")
        lua.execute("""
            NOW = 100
            function GetTime() return NOW end
            VISIBLE = {}; DEAD = {}
            function UnitIsVisible(unit) return VISIBLE[unit] ~= false end
            function UnitIsDeadOrGhost(unit) return DEAD[unit] == true end
            HAVE = {}
            C_UnitAuras = {GetAuraDataByIndex=function(unit, i)
                if i == 1 and HAVE[unit] then return {name=HAVE[unit], expirationTime=0} end
            end}
            ns.WoW.Me = function() return 'Me' end; ns.WoW.Short = function(n) return n end
            ns.WoW.ClassName = function(c) return c end
            ns.WoW.SpellName = function(id) return tostring(id) end
            ns.WoW.SpellIcon = function(id) return id end
            ns.WoW.KnowsAny = function(ids) if #ids == 0 then return false end return true, ids[#ids] end
            ns.WoW.ItemCount = function() return 10 end
            ns.WoW.SpellUsable = function() return true end
        """)
        lua.execute(setup)
        load(lua, "Features/Tracker/Scan.lua")
        load(lua, "Features/Tracker/Actions.lua")
        lua.execute("""
            function nextCast(help)
                ns.Tracker.Scan.Update(NOW, 300)
                return ns.Tracker.Actions.Next(NOW, 300, nil, false, help)
            end
        """)
        return lua

    def test_group_cast_marks_everyone_it_covers(self):
        lua = self.tracker_actions("""
            local members, units, expected = {Me={class='PRIEST', group=1, unit='player'}}, {Me='player'}, {}
            for i = 1, 4 do
                local n = 'R' .. i
                members[n] = {class='ROGUE', group=1, unit='party' .. i}; units[n] = 'party' .. i
                expected[n] = {FORT='Me'}
            end
            ns.Assignments.roster = {members=members, units=units}
            ns.Assignments.result = {groups={FORT={[1]='Me'}}, auras={}, pally={}, expected=expected, overrides={}}
        """)
        lua.execute("""
            local cast = nextCast()
            assert(cast.big and cast.spell == '21564' and #cast.covers == 4)
            ns.Tracker.Actions.MarkCast(cast)
            -- Until the auras arrive, nobody in the group is offered a redundant single.
            assert(nextCast() == nil)
            NOW = NOW + 4
            assert(nextCast().big)
        """)

    def test_cover_for_another_caster_after_grace_or_when_away(self):
        lua = self.tracker_actions("""
            ns.Assignments.roster = {members={Me={class='PRIEST', group=2, unit='raid1', caps={FORT=true}},
                Other={class='PRIEST', group=1, unit='raid2', caps={FORT=true}},
                R={class='ROGUE', group=1, unit='raid3'}, P={class='PALADIN', group=1, unit='raid4'}},
                units={Me='raid1', Other='raid2', R='raid3', P='raid4'}}
            ns.Assignments.result = {groups={FORT={[1]='Other'}}, auras={}, pally={ROGUE={P='MIGHT'}},
                expected={R={FORT='Other', MIGHT='P'}}, overrides={}}
        """)
        lua.execute("""
            HAVE.raid1 = '1243'
            assert(nextCast(true) == nil) -- just went missing: Other gets the first go
            NOW = NOW + 29
            assert(nextCast(true) == nil)
            NOW = NOW + 1
            assert(nextCast(false) == nil) -- the setting is off
            local cast = nextCast(true)
            assert(cast.key == 'FORT' and cast.who == 'R' and cast.helping == 'Other')
            -- Blessings stay with their paladin: I am not offered Might.
            HAVE.raid3 = '10938'
            assert(nextCast(true) == nil)
            -- A helper earlier in line goes first.
            HAVE.raid3 = nil; NOW = 1000
            ns.Assignments.roster.members.Aaa = {class='PRIEST', group=3, unit='raid5', caps={gFORT=true}}
            assert(nextCast(true) == nil)
            NOW = NOW + 39; assert(nextCast(true) == nil)
            NOW = NOW + 1; assert(nextCast(true).helping == 'Other')
            -- A dead or distant caster: no grace, just the turn behind Aaa.
            local function fresh() HAVE.raid3 = '10938'; nextCast(true); HAVE.raid3 = nil end
            NOW = 2000; DEAD.raid2 = true; fresh()
            assert(nextCast(true) == nil)
            NOW = NOW + 10; assert(nextCast(true).helping == 'Other')
            DEAD.raid2 = false; VISIBLE.raid2 = false; NOW = 3000; fresh()
            assert(nextCast(true) == nil)
            NOW = NOW + 10; assert(nextCast(true).helping == 'Other')
        """)

    def test_aura_changes_refresh_the_tracker_once_out_of_combat(self):
        lua = full_addon()
        lua.execute("""
            local frame, refreshes = Buffeteria_Tracker, 0
            local refresh = ns.Tracker.Refresh
            ns.Tracker.Refresh = function() refreshes = refreshes + 1; return refresh() end
            for _, unit in ipairs({'player', 'party1', 'raid12', 'party1', 'nameplate3', 'raidpet1', 'target'}) do
                frame:GetScript('OnEvent')(frame, 'UNIT_AURA', unit)
            end
            runTimers()
            assert(refreshes == 1)
            COMBAT = true
            frame:GetScript('OnEvent')(frame, 'UNIT_AURA', 'party1'); runTimers()
            assert(refreshes == 1)
            COMBAT = false
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
            ns.Assignments.roster.members['A-Realm'].caps.DEVO = true; ns.Assignments.roster.members['B-Realm'].caps.DEVO = true
            ns.Paladins.Set('A-Realm', 'AURA', 'DEVO')
            assert(ns.db.paladinBlessings.AURA == 'DEVO')
            assert(sent[#sent]:match('^P|2|A%-Realm|10|DEVO|'))
            ns.Paladins.Set('A-Realm', 'AURA', 'KINGS') -- blessings are not auras
            ns.Paladins.Set('A-Realm', 'ROGUE', 'DEVO') -- auras are not blessings
            assert(ns.Paladins.Get('A-Realm', 'AURA') == 'DEVO' and ns.Paladins.Get('A-Realm', 'ROGUE') == 'AUTO')
            ns.Paladins.Set('B-Realm', 'AURA', 'DEVO')
            assert(ns.Paladins.Get('A-Realm', 'AURA') == 'NONE' and ns.Paladins.Get('B-Realm', 'AURA') == 'DEVO')
            ns.Paladins.Set('C-Realm', 'AURA', 'SANCTITY')
            local blessings, auras, assumed = ns.Paladins.Assignments(ns.Assignments.roster)
            assert(auras['C-Realm'] == 'SANCTITY' and auras['B-Realm'] == 'DEVO' and blessings.AURA == nil)
            assert(assumed['C-Realm'].SANCTITY)
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
            local tab = findWidget('Paladins').parent; tab:GetScript('OnClick')(tab)
            local panel = findWidget('Class blessings').parent
            -- B has no add-on, so only baseline auras are assumed: it gets Devotion,
            -- and A takes Concentration, which only A knows.
            assert(ns.Assignments.result.auras['B-Realm'] == 'DEVO' and ns.Assignments.result.auras['A-Realm'] == 'CONC')
            local aura = panel.columns[1].aura
            assert(aura.state == 'green' and aura.detail == 'Auto: Concentration Aura')
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
            -- The aura picker exposes available auras without cycling.
            aura:GetScript('OnClick')(aura, 'LeftButton')
            for _, choice in ipairs(panel.picker.choices) do
                if choice.key == 'SANCTITY' then choice:GetScript('OnClick')(choice) end
            end
            runTimers()
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
            assert(ns.Assignments.result.expected['A-Realm'].RFURY == 'A-Realm')
            assert(ns.Preferences.Get().wants.THORNS)
            local message = delivered[#delivered]
            assert(message:match('^S|2|') and message:find('RFURY') and message:find('THORNS'))
            for _, msg in ipairs(delivered) do assert(#msg <= 255) end
            ns.Options.Toggle()
            local panel = findWidget('Blessings').parent.parent
            local thorns = panel.tankButtons.THORNS
            thorns:GetScript('OnClick')(thorns); runTimers()
            assert(not ns.Preferences.Get().wants.THORNS)
            role = 'HEALER'
            ns.App:GetScript('OnEvent')(ns.App, 'PLAYER_ROLES_ASSIGNED'); runTimers()
            assert(not ns.Assignments.result.expected['A-Realm'].RFURY)
            assert(ns.db.tankBuffs.RFURY and not ns.db.tankBuffs.THORNS)
            panel.roles[2]:GetScript('OnClick')(panel.roles[2]); runTimers()
            assert(ns.Assignments.result.expected['A-Realm'].RFURY == 'A-Realm')
            panel.roles[3]:GetScript('OnClick')(panel.roles[3]); runTimers()
            assert(not ns.Preferences.Get().wants.RFURY)
            ns.Database.Init(); ns.Preferences.Init() -- keep choices on reload
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
            assert(button:GetAttribute('spell') == '25780' and button:GetAttribute('*unit1') == 'player')
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

    def test_warrior_battle_shout_is_optional_self_buff_with_short_warning(self):
        lua = full_addon('WARRIOR')
        lua.execute("""
            assert(ns.db.wants.BSHOUT and ns.Preferences.Get().wants.BSHOUT)
            ns.db.wants.BSHOUT = nil; ns.Database.Init(); ns.Preferences.Init() -- older saved wants enable it
            assert(ns.db.wants.BSHOUT == true)
            ns.Preferences.Changed(); runTimers()
            assert(ns.Assignments.result.expected['A-Realm'].BSHOUT == 'A-Realm')
            assert(ns.Roster.Capabilities().BSHOUT)
            ns.Assignments.result.pally = {}; ns.Assignments.result.auras = {}
            ns.Tracker.Refresh()
            local button = Buffeteria_CastButton
            assert(button:GetAttribute('spell') == '25289' and button:GetAttribute('*unit1') == 'player')
            -- 60 seconds left is fine; 20 seconds left warns despite the 5-minute setting.
            local left = 60
            C_UnitAuras.GetAuraDataByIndex = function(unit, i)
                if i == 1 then return {name='25289', expirationTime=WOW_TIME + left, sourceUnit='player'} end
            end
            ns.Tracker.Refresh()
            assert(ns.Tracker.Summary().perKey.BSHOUT.warn == 0 and not button:GetAttribute('spell'))
            left = 20; ns.Tracker.Refresh()
            assert(ns.Tracker.Summary().perKey.BSHOUT.warn == 1)
            -- Not enough rage: still tracked, but nothing to cast.
            C_Spell.IsSpellUsable = function() return false, true end
            ns.Tracker.Refresh()
            assert(not button:GetAttribute('spell'))
            C_Spell.IsSpellUsable = nil
            ns.Options.Toggle()
            local panel = findWidget('Blessings').parent.parent
            local shout = panel.wants.BSHOUT
            assert(shout:IsShown())
            shout:GetScript('OnClick')(shout); runTimers()
            assert(not ns.db.wants.BSHOUT and not ns.Assignments.result.expected['A-Realm'].BSHOUT)
            ns.Database.Init(); ns.Preferences.Init()
            assert(ns.db.wants.BSHOUT == false) -- skip survives reload
            ns.Preferences.Reset(); runTimers()
            assert(ns.db.wants.BSHOUT)
        """)

    def test_combat_self_buffs_stay_castable_during_combat(self):
        for player_class, key, spell in (("WARRIOR", "BSHOUT", "25289"), ("PRIEST", "IFIRE", "10952")):
            with self.subTest(player_class):
                lua = full_addon(player_class)
                lua.execute("""
                    local key, spell = '%s', '%s'
                    local frame, head = Buffeteria_Tracker, Buffeteria_CastButton
                    ns.Assignments.result.pally = {}; ns.Assignments.result.auras = {}
                    ns.Assignments.result.expected['B-Realm'] = {}
                    -- The buff is up when the fight starts: nothing to do yet.
                    local up = true
                    C_UnitAuras.GetAuraDataByIndex = function(unit, i)
                        if up and unit == 'player' and i == 1 then
                            return {name=spell, expirationTime=WOW_TIME + 100, sourceUnit='player'}
                        end
                    end
                    ns.Tracker.Refresh()
                    frame:GetScript('OnEvent')(frame, 'PLAYER_REGEN_DISABLED')
                    COMBAT = true; ns.Tracker.Refresh()
                    assert(head:GetAttribute('spell') == spell and head:GetAttribute('*unit1') == 'player')
                    assert(not ns.Tracker.Summary().next and not frame.gief:IsShown())
                    -- It falls off mid-fight: the head demands it and the click casts it.
                    up = false; ns.Tracker.Refresh()
                    assert(ns.Tracker.Summary().next.key == key and frame.gief:IsShown())
                    assert(frame.gief:GetText() == 'GIEF ' .. ns.Buffs.byKey[key].label .. '!')
                    head:GetScript('PostClick')(head, 'LeftButton', false)
                    frame:GetScript('OnEvent')(frame, 'UNIT_SPELLCAST_SUCCEEDED', 'player', 'guid', tonumber(spell))
                    ns.Tracker.Refresh()
                    assert(not frame.gief:IsShown()) -- waiting for the cast's aura
                    COMBAT = false; ns.App:GetScript('OnEvent')(ns.App, 'PLAYER_REGEN_ENABLED')
                """ % (key, spell))

    def test_combat_self_buffs_tracked_while_auras_are_hidden(self):
        lua = full_addon('WARRIOR')
        lua.execute("""
            local frame, head = Buffeteria_Tracker, Buffeteria_CastButton
            ns.Assignments.result.pally = {}; ns.Assignments.result.auras = {}
            ns.Assignments.result.expected['B-Realm'] = {}
            local function call() return ns.Tracker.Summary().next and ns.Tracker.Summary().next.key end
            -- Out of combat: a readable shout with 100 seconds left (a talented 150-second one).
            C_UnitAuras.GetAuraDataByIndex = function(unit, i)
                if COMBAT then error('blocked in combat') end
                if unit == 'player' and i == 1 then
                    return {name='25289', expirationTime=WOW_TIME + 100, duration=150, sourceUnit='player'}
                end
            end
            ns.Tracker.Refresh()
            frame:GetScript('OnEvent')(frame, 'PLAYER_REGEN_DISABLED')
            COMBAT = true; ns.Tracker.Refresh()
            assert(call() == nil)
            -- It runs out mid-fight: dated from the last read.
            WOW_TIME = WOW_TIME + 75; ns.Tracker.Refresh()
            assert(call() == 'BSHOUT' and ns.Tracker.Summary().perKey.BSHOUT.warn == 1)
            WOW_TIME = WOW_TIME + 30; ns.Tracker.Refresh()
            assert(call() == 'BSHOUT' and ns.Tracker.Summary().perKey.BSHOUT.bad == 1)
            -- Recast in combat: good for the learned duration, not the base two minutes.
            frame:GetScript('OnEvent')(frame, 'UNIT_SPELLCAST_SUCCEEDED', 'player', 'guid', 25289)
            assert(call() == nil)
            WOW_TIME = WOW_TIME + 110; ns.Tracker.Refresh()
            assert(call() == nil)
            -- Other units and other spells change nothing.
            frame:GetScript('OnEvent')(frame, 'UNIT_SPELLCAST_SUCCEEDED', 'party1', 'guid', 25289)
            frame:GetScript('OnEvent')(frame, 'UNIT_SPELLCAST_SUCCEEDED', 'player', 'guid', 12345)
            WOW_TIME = WOW_TIME + 20; ns.Tracker.Refresh()
            assert(call() == 'BSHOUT')
            COMBAT = false; ns.App:GetScript('OnEvent')(ns.App, 'PLAYER_REGEN_ENABLED')
            assert(call() == nil) -- readable again: the real aura wins
            -- Lost early mid-fight: hidden until combat ends, then read.
            frame:GetScript('OnEvent')(frame, 'PLAYER_REGEN_DISABLED')
            COMBAT = true; ns.Tracker.Refresh()
            local gone = true
            local read = C_UnitAuras.GetAuraDataByIndex
            C_UnitAuras.GetAuraDataByIndex = function(unit, i)
                if gone and not COMBAT then return nil end
                return read(unit, i)
            end
            ns.Tracker.Refresh()
            assert(call() == nil)
            COMBAT = false; ns.App:GetScript('OnEvent')(ns.App, 'PLAYER_REGEN_ENABLED')
            assert(ns.Tracker.Summary().perKey.BSHOUT.bad == 1)
        """)

    def test_long_buffs_wait_until_after_combat(self):
        lua = full_addon('PRIEST')
        lua.execute("""
            local frame, head = Buffeteria_Tracker, Buffeteria_CastButton
            ns.db.wants.IFIRE = false; ns.Preferences.Changed(); runTimers()
            ns.Tracker.Refresh()
            local before = head:GetAttribute('spell')
            assert(ns.Tracker.Summary().next and ns.Tracker.Summary().next.key ~= 'IFIRE')
            frame:GetScript('OnEvent')(frame, 'PLAYER_REGEN_DISABLED')
            COMBAT = true; ns.Tracker.Refresh()
            assert(head:GetAttribute('spell') == before) -- nothing to arm
            assert(not ns.Tracker.Summary().next and not frame.gief:IsShown())
            COMBAT = false; ns.App:GetScript('OnEvent')(ns.App, 'PLAYER_REGEN_ENABLED')
            assert(ns.Tracker.Summary().next and frame.gief:IsShown())
        """)

    def test_battle_shout_is_warrior_only(self):
        lua = full_addon('PRIEST')
        lua.execute("""
            assert(ns.db.wants.BSHOUT == false and not ns.Preferences.Get().wants.BSHOUT)
            assert(not ns.Roster.Capabilities().BSHOUT)
            ns.Options.Toggle()
            assert(not findWidget('Blessings').parent.parent.wants.BSHOUT:IsShown())
            ns.db.wants.BSHOUT = true
            assert(not ns.Preferences.Get().wants.BSHOUT)
        """)
        self.solver("""
            local w = member('WARRIOR'); w.wants = {BSHOUT=true}; w.caps = {BSHOUT=true}
            local p = member('PALADIN'); p.wants = {BSHOUT=true}; p.caps.BSHOUT = true
            local x = member('WARRIOR'); x.wants = {BSHOUT=true} -- not learned
            local result = ns.Solver.Solve({members={W=w, P=p, X=x}})
            assert(result.expected.W.BSHOUT == 'W' and not result.expected.P.BSHOUT and not result.expected.X.BSHOUT)
        """)

    def test_priest_inner_fire_is_optional_self_buff_with_short_warning(self):
        lua = full_addon('PRIEST')
        lua.execute("""
            assert(ns.db.wants.IFIRE and ns.Preferences.Get().wants.IFIRE)
            ns.db.wants.IFIRE = nil; ns.Database.Init(); ns.Preferences.Init() -- older saved wants enable it
            assert(ns.db.wants.IFIRE == true)
            ns.db.wants.FORT = false; ns.db.wants.SPIRIT = false
            ns.Preferences.Changed(); runTimers()
            assert(ns.Assignments.result.expected['A-Realm'].IFIRE == 'A-Realm')
            assert(ns.Roster.Capabilities().IFIRE)
            -- Leave only Inner Fire to cast.
            ns.Assignments.result.pally = {}; ns.Assignments.result.auras = {}
            ns.Assignments.result.expected['B-Realm'] = {}
            ns.Tracker.Refresh()
            local button = Buffeteria_CastButton
            assert(button:GetAttribute('spell') == '10952' and button:GetAttribute('*unit1') == 'player')
            -- 90 seconds left is fine; 45 seconds left warns despite the 5-minute setting.
            local left = 90
            C_UnitAuras.GetAuraDataByIndex = function(unit, i)
                if i == 1 then return {name='10952', expirationTime=WOW_TIME + left, sourceUnit='player'} end
            end
            ns.Tracker.Refresh()
            assert(ns.Tracker.Summary().perKey.IFIRE.warn == 0 and not button:GetAttribute('spell'))
            left = 45; ns.Tracker.Refresh()
            assert(ns.Tracker.Summary().perKey.IFIRE.warn == 1)
            -- Not enough mana: still tracked, but nothing to cast.
            C_Spell.IsSpellUsable = function() return false, true end
            ns.Tracker.Refresh()
            assert(not button:GetAttribute('spell'))
            C_Spell.IsSpellUsable = nil
            ns.Options.Toggle()
            local panel = findWidget('Blessings').parent.parent
            local fire = panel.wants.IFIRE
            assert(fire:IsShown() and not panel.wants.BSHOUT:IsShown())
            fire:GetScript('OnClick')(fire); runTimers()
            assert(not ns.db.wants.IFIRE and not ns.Assignments.result.expected['A-Realm'].IFIRE)
            ns.Database.Init(); ns.Preferences.Init()
            assert(ns.db.wants.IFIRE == false) -- skip survives reload
            ns.Preferences.Reset(); runTimers()
            assert(ns.db.wants.IFIRE)
        """)

    def test_inner_fire_waits_until_learned(self):
        lua = full_addon('PRIEST')
        lua.execute("""
            local learned = false
            local inner = {}
            for _, id in ipairs(ns.Buffs.byKey.IFIRE.ids) do inner[id] = true end
            IsPlayerSpell = function(id) return learned or not inner[id] end
            ns.Assignments.Resolve(); runTimers()
            assert(ns.db.wants.IFIRE and not ns.Assignments.result.expected['A-Realm'].IFIRE)
            ns.Tracker.Refresh()
            local s = ns.Tracker.Summary()
            assert(not s.perKey.IFIRE and not (s.next and s.next.key == 'IFIRE'))
            ns.Options.Toggle()
            local panel = findWidget('Blessings').parent.parent
            assert(not panel.wants.IFIRE:IsShown())
            -- Level 12: the spell arrives and so does the tracking.
            learned = true
            ns.App:GetScript('OnEvent')(ns.App, 'SPELLS_CHANGED'); runTimers()
            assert(ns.Assignments.result.expected['A-Realm'].IFIRE == 'A-Realm')
            assert(panel.wants.IFIRE:IsShown())
        """)

    def test_inner_fire_is_priest_only(self):
        lua = full_addon('WARRIOR')
        lua.execute("""
            assert(ns.db.wants.IFIRE == false and not ns.Preferences.Get().wants.IFIRE)
            assert(not ns.Roster.Capabilities().IFIRE)
            ns.Options.Toggle()
            assert(not findWidget('Blessings').parent.parent.wants.IFIRE:IsShown())
            ns.db.wants.IFIRE = true
            assert(not ns.Preferences.Get().wants.IFIRE)
        """)
        self.solver("""
            local p = member('PRIEST'); p.wants = {IFIRE=true}; p.caps = {IFIRE=true}
            local w = member('WARRIOR'); w.wants = {IFIRE=true}; w.caps = {IFIRE=true}
            local x = member('PRIEST'); x.wants = {IFIRE=true}; x.caps = {} -- not learned
            local result = ns.Solver.Solve({members={P=p, W=w, X=x}})
            assert(result.expected.P.IFIRE == 'P' and not result.expected.W.IFIRE and not result.expected.X.IFIRE)
        """)

    def test_druid_serves_thorns_to_tanks_without_addon_and_peer_opt_out(self):
        lua = full_addon('DRUID')
        lua.execute("""
            function UnitGroupRolesAssigned(unit) return unit == 'party1' and 'TANK' or 'HEALER' end
            ns.App:GetScript('OnEvent')(ns.App, 'PLAYER_ROLES_ASSIGNED'); runTimers()
            assert(ns.Assignments.roster.members['B-Realm'].wants.THORNS)
            assert(ns.Assignments.result.expected['B-Realm'].THORNS == 'A-Realm')
            assert(not ns.Preferences.Get().wants.RFURY)
            assert(ns.Roster.Capabilities().THORNS and not ns.Roster.Capabilities().RFURY)
            ns.Options.Toggle()
            assert(not findWidget('Blessings').parent.parent.tankButtons.RFURY:IsShown())
            ns.db.wants = {}
            ns.Comm.OnMessage('BUFFETERIA', 'S|2|THORNS|KINGS||MIGHT|0', 'PARTY', 'B-Realm'); runTimers()
            ns.Assignments.result.pally = {}; ns.Assignments.result.auras = {} -- isolate the tank cast
            ns.Tracker.Refresh()
            assert(Buffeteria_CastButton:GetAttribute('spell') == '9910')
            assert(Buffeteria_CastButton:GetAttribute('*unit1') == 'party1')
            assert(table.concat(ns.Assignments.Lines(false), ';'):find('Thorns: A -> B', 1, true))
            C_UnitAuras.GetAuraDataByIndex = function(unit, i)
                if unit == 'party1' and i == 1 then return {name='9910', expirationTime=WOW_TIME+60} end
            end
            ns.Tracker.Refresh()
            assert(ns.Tracker.Summary().perKey.THORNS.warn == 1)
            IsSpellInRange = function() return 0 end
            assert(not ns.Tracker.Actions.Next(WOW_TIME, 300))
            ns.Comm.OnMessage('BUFFETERIA', 'S|2||KINGS||MIGHT|0', 'PARTY', 'B-Realm'); runTimers()
            assert(not ns.Assignments.result.expected['B-Realm'].THORNS) -- explicit peer opt-out beats role default
        """)

    def test_tracker_turns_on_my_missing_aura(self):
        lua = full_addon()
        lua.execute("""
            ns.db.showTracker = true
            ns.Tracker.Refresh()
            local summary = ns.Tracker.Summary()
            assert(summary.perKey.CONC.bad == 1 and summary.overall == 'bad')
            -- My part counts every recipient assigned to me, plus my aura.
            local mineTotal, me = 1, ns.WoW.Me()
            for _, exp in pairs(ns.Assignments.result.expected) do
                for _, caster in pairs(exp) do if caster == me then mineTotal = mineTotal + 1 end end
            end
            assert(summary.mine.total == mineTotal and summary.mine.pending >= 1)
            local pendingBefore = summary.mine.pending
            local button = Buffeteria_CastButton
            -- Highest known rank of Concentration Aura, cast on myself.
            assert(button:GetAttribute('spell') == '19746' and button:GetAttribute('*unit1') == 'player')
            -- Another paladin's Concentration Aura hides mine and covers the group.
            C_UnitAuras.GetAuraDataByIndex = function(unit, i)
                if unit == 'player' and i == 1 then return {name='19746', expirationTime=0, sourceUnit='party1'} end
            end
            assert(ns.Tracker.Scan.MissingAura() == nil)
            C_UnitAuras.GetAuraDataByIndex = function(unit, i)
                if unit == 'player' and i == 1 then return {name='465', expirationTime=0, sourceUnit='party1'} end
            end
            assert(ns.Tracker.Scan.MissingAura() == 'CONC') -- a different aura doesn't count
            C_UnitAuras.GetAuraDataByIndex = function(unit, i)
                if unit == 'player' and i == 1 then return {name='19746', expirationTime=0, sourceUnit='player'} end
            end
            assert(ns.Tracker.Scan.MissingAura() == nil)
            ns.Tracker.Refresh()
            assert(ns.Tracker.Summary().perKey.CONC.bad == 0)
            assert(ns.Tracker.Summary().mine.pending == pendingBefore - 1)
            assert(button:GetAttribute('spell') ~= '19746')
        """)

if __name__ == "__main__":
    unittest.main()
