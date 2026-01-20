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
    local settings = uilib:setupPage({name = (function() return "Sets " .. instance .. "/" .. uilib.global.settings.name; end)});

    for row = 1, uilib.global.settings.rows do
        local i = row + (instance - 1) * uilib.global.settings.rows;
        local y = (row - 1) * 14

        local details = uilib.addPage({script = "ui_set_d.lua", instance = i, parent = page});

        settings:addLabel({x = 0, y = y, text = (function() return "O" .. i .. ":"; end)});
        settings:addTextEdit({x = 20, y = y, text = (function() return uilib.global.settings.buttons[i].name; end),
                                             set = (function(v) uilib.global.settings.buttons[i].name = v; saveSettings(); end)});
        settings:addButton({x = 80, y = y, text = (function() return "Details"; end), press = (function()
            uilib.activate(details);
        end)});
    end
end
return {
    init = init,
};
