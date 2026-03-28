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

local function init(instance, parent, page)
    local global = uilib:setupPage({name = (function() return "Info"; end)});
    local y = 0;
    global:addLabel({x = 0,  y = y, text = (function() return "Version:"; end)});
    global:addLabel({x = 50, y = y, text = (function() return uilib.global.version .. "/" .. uilib.global.settingsVersion; end)});
    y = y + 10;
    global:addLabel({x = 0,  y = y, text = (function() return "Free Mem:"; end)});
    global:addLabel({x = 50, y = y, text = (function() return getAvailableMemory() .. "bytes"; end)});
    y = y + 10;
    global:addLabel({x = 0,  y = y, text = (function() return "Radio:"; end)});
    local ver, radio, maj, minor, rev, osname = getVersion();
    global:addLabel({x = 50, y = y, text = (function() return uilib.global.radio .. "(" .. radio .. ")"; end)});
    y = y + 10;
    global:addLabel({x = 0,  y = y, text = (function() return "SHM:"; end)});
    global:addLabel({x = 50, y = y, text = (function() if (uilib.global.shm > 0) then return "yes"; else return "no"; end end)});
end

return {
    init = init,
};
