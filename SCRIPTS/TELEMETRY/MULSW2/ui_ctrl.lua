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

local function init()
    local control = uilib:setupPage({name = (function() return "Ctrl/" .. uilib.global.settings.name; end)});
    for col = 1, uilib.global.settings.columns do
        for row = 1, uilib.global.settings.rows do
            local i = row + (col - 1) * uilib.global.settings.rows;
            control:addStateButton({x = (col - 1) * 70, y = (row - 1) * 14, 
                                        text = (function() return uilib.global.settings.buttons[i].name; end),
                                        press = (function()
                                            if (uilib.global.state.buttons[i].value == 0) then
                                                uilib.global.state.buttons[i].value = 1;
                                            else 
                                                uilib.global.state.buttons[i].value = 0;
                                            end
                                            uilib.update();
                                        end),
                                        active = (function() if (uilib.global.settings.buttons[i].switch == uilib.switchIndexNone) then return true; end return false; end),
                                        state = (function() return uilib.global.state.buttons[i].value; end),
                                        switch = (function() return uilib.global.settings.buttons[i].switch; end)
            });
        end
    end
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
