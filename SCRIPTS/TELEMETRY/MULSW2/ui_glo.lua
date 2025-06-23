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

    global:addLabel({x = 65, y = y, text = (function() return "Show/P:"; end)});
    global:addNumberEdit({x = 115, y = y, min = 0, max = 1, value = (function() return uilib.global.settings.show_physical; end),
                            set = (function(v) uilib.global.settings.show_physical = v; saveSettings(); end)});

    if (uilib.global.radio ~= 2) then
        -- radio must have enough memory
        y = y + 10;
        global:addLabel({x = 0, y = y, text = (function() return "RF link:"; end)});
        global:addChoice({x = 50, y = y, values = {"CRSF", "S.Port", "SBus"}, 
                                index = (function() return uilib.global.settings.rflink; end),
                                set = (function(v) 
                                    uilib.global.settings.rflink = v; 
                                    saveSettings();
                                    uilib.activeContent = nil; -- reload and init
                                end)});
        
        if (uilib.global.settings.rflink == uilib.global.RF.SPORT) then
            y = y + 10;
            global:addLabel({x = 0, y = y, text = (function() return "S.Port/P:"; end)});
            global:addChoice({x = 50, y = y, values = {"WM", "ACW1.4", "ACW1.5"}, 
                                index = (function() return uilib.global.settings.SPort.Proto; end),
                                set = (function(v) 
                                    uilib.global.settings.SPort.Proto = v; 
                                    saveSettings(); 
                                    uilib.activeContent = nil; -- reload and init
                                end)});
            if (uilib.global.settings.SPort.Proto == 1) then
                y = y + 10;
                global:addLabel({x = 0, y = y, text = (function() return "S/Phy:"; end)});
                global:addNumberEdit({x = 50, y = y, min = 0, max = 1, value = (function() return uilib.global.settings.SPort.Phy; end),
                                        set = (function(v) uilib.global.settings.SPort.Phy = v; saveSettings(); end)});
                global:addLabel({x = 65, y = y, text = (function() return "S/App:"; end)});
                global:addNumberEdit({x = 115, y = y, min = 0, max = 1, value = (function() return uilib.global.settings.SPort.App; end),
                                        set = (function(v) uilib.global.settings.SPort.App = v; saveSettings(); end)});
            end
        end       
    end
end

return {
    init = init,
};
