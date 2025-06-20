-- WM EdgeTx LUA 
-- Copyright (C) 2016 - 2025 Wilhelm Meier <wilhelm.wm.meier@googlemail.com>
--
-- This program is free software: you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation, either version 3 of the License, or
-- (at your option) any later version.
--
-- This program is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU General Public License for more details.
--
-- You should have received a copy of the GNU General Public License
-- along with this program.  If not, see <http://www.gnu.org/licenses/>.
--

local uilib, environment = ...

local function saveSettings() 
    local serialize = loadScript(environment.dir .. "table_write.lua", "btd")();
    serialize.save(uilib.global.settings, uilib.global.settingsFilename);        
end

local function init(instance, parent, page)
    local global = uilib:setupPage({name = (function() return "Globals"; end)});
    local y = 0;
    global:addLabel({x = 0, y = y, text = (function() return "Name:"; end)});
    global:addTextEdit({x = 50, y = y, text = (function() return uilib.global.settings.name; end),
                                             set = (function(v) uilib.global.settings.name = v; saveSettings(); end)});
    y = y + 10;
    global:addLabel({x = 0, y = y, text = (function() return "Address:"; end)});
    global:addNumberEdit({x = 50, y = y, min = 0, max = 255, value = (function() return uilib.global.settings.Address; end),
                            set = (function(v) uilib.global.settings.Address = v; saveSettings(); end)});
    y = y + 10;
    global:addLabel({x = 0, y = y, text = (function() return "CRSF:"; end)});
    global:addNumberEdit({x = 50, y = y, min = 0, max = 1, value = (function() return uilib.global.settings.CRSF; end),
                            set = (function(v) uilib.global.settings.CRSF = v; saveSettings(); end)});
--    y = y + 10;
    global:addLabel({x = 65, y = y, text = (function() return "SPort:"; end)});
    global:addNumberEdit({x = 115, y = y, min = 0, max = 1, value = (function() return uilib.global.settings.SPort.On; end),
                            set = (function(v) uilib.global.settings.SPort.On = v; saveSettings(); end)});
    y = y + 10;
    global:addLabel({x = 0, y = y, text = (function() return "S/Phy:"; end)});
    global:addNumberEdit({x = 50, y = y, min = 0, max = 1, value = (function() return uilib.global.settings.SPort.Phy; end),
                            set = (function(v) uilib.global.settings.SPort.Phy = v; saveSettings(); end)});
--    y = y + 10;
    global:addLabel({x = 65, y = y, text = (function() return "S/App:"; end)});
    global:addNumberEdit({x = 115, y = y, min = 0, max = 1, value = (function() return uilib.global.settings.SPort.App; end),
                            set = (function(v) uilib.global.settings.SPort.App = v; saveSettings(); end)});
    y = y + 10;
    global:addLabel({x = 0, y = y, text = (function() return "S/Pro:"; end)});
    global:addNumberEdit({x = 50, y = y, min = 0, max = 1, value = (function() return uilib.global.settings.SPort.Proto; end),
                            set = (function(v) uilib.global.settings.SPort.Proto = v; saveSettings(); end)});
    global:addLabel({x = 65, y = y, text = (function() return "Show/P:"; end)});
    global:addNumberEdit({x = 115, y = y, min = 0, max = 1, value = (function() return uilib.global.settings.show_physical; end),
                            set = (function(v) uilib.global.settings.show_physical = v; saveSettings(); end)});
end

return {
    init = init,
};
