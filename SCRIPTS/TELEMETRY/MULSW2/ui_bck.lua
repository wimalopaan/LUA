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

local uilib, env = ... 

--local shm       = loadScript(env.dir .. "shm.lua", "btd")(uilib, env);
local fsm       = loadScript(env.dir .. "fsm.lua", "btd")(uilib, env);

local function readPhysical() 
    for i, btn in ipairs(uilib.global.settings.buttons) do
        local btnstate = uilib.global.state.buttons[i];
        if (btn.switch ~= uilib.switchIndexNone) then
            local v = uilib.getSwitchValue(btn.switch);
            local vv = (btnstate.value == 1)
            if (v ~= vv) then
                if (v) then
                    btnstate.value = 1;
                else
                    btnstate.value = 0;
                end
                fsm.update();
            end
        end
    end
end

local function init()
end

local function background()
    readPhysical();
    fsm.tick((function() end));
end

return {
    init = init,
    background = background,
    update = fsm.update,
};