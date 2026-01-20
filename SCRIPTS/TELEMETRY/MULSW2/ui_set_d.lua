-- WM EdgeTx LUA 
-- Copyright (C) 2016 - 2026 Wilhelm Meier <wilhelm.wm.meier@googlemail.com>
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
    local details = uilib:setupPage({parent = parent, name = (function() return "Dets " .. instance .. "/" .. uilib.global.settings.name; end)});
    local y = 0;
    details:addLabel({x = 0, y = y, text = (function() return "Address:"; end)});
    details:addNumberEdit({x = 60, y = y, min = 0, max = 255, 
                            value = (function() return uilib.global.settings.buttons[instance].address; end),
                            set = (function(v) uilib.global.settings.buttons[instance].address = v; saveSettings(); end)});
    y = y + 10;
    details:addLabel({x = 0, y = y, text = (function() return "Output:"; end)});
    details:addNumberEdit({x = 60, y = y, min = 0, max = 255, 
                            value = (function() return uilib.global.settings.buttons[instance].output; end),
                            set = (function(v) uilib.global.settings.buttons[instance].output = v; saveSettings(); end)});
    y = y + 10;
    details:addLabel({x = 0, y = y, text = (function() return "Switch:"; end)});
    details:addSwitchSelect({x = 60, y = y, min = 0, max = 255, 
                            value = (function() return uilib.global.settings.buttons[instance].switch; end),
                            set = (function(v) uilib.global.settings.buttons[instance].switch = v; saveSettings(); end)});
end

-- local function run(event)
-- end

-- local function background()
-- end

return {
    init = init,
    -- run = run,
    -- background = background
};
