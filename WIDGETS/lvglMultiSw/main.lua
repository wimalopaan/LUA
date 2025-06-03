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

-- for todo-list: see ui.lua

local name = "MultiSwE/L"
local longname = "MultiSwitch-ELRS/L"

local function create(zone, options, dir)
    if (lvgl == nil) then
        return {zone = zone, options = options, name = name};
    end
    if (dir == nil) then
        dir = "/WIDGETS/lvglMultiSw/";
    end
    return loadScript(dir .. "ui.lua")(zone, options, longname, dir);
end

local function refresh(widget, event, touchState)
    widget.refresh(event, touchState)
end

local function background(widget)
    if (lvgl == nil) then 
        return;
    end
    widget.background();
end

local options = {
    { "CRSF",  BOOL, 1 },
    { "Address",  VALUE, 0, 0, 255 },
    { "Intervall",  VALUE, 100, 10, 100 },
    { "Autoconf", BOOL,  0 },
--    { "Protocol", CHOICE, 2, { "Set", "Set4", "Set4M", "Set64", "Set64/4"}},
    { "ShmEncoding", BOOL,  0 },
    { "ShmVar",  VALUE, 1, 1, 16 },
    { "SPort", BOOL,  0 },
    { "SPortPhy", VALUE, 0, 0, 0x1b}, 
    { "SPortApp", VALUE, 0x51, 0, 255}, -- upper 8-bit (lower 8-bit: instance = address) 
    { "SPortProto", CHOICE, 1, { "WM", "ACW1.5", "ACW1.4"}},
}
  
local function update(widget, options)
    widget.options = options;
    if (lvgl == nil) then 
        return;
    end
    widget.update();
end

return {
    useLvgl = true,
    name = name,
    create = create,
    refresh = refresh,
    background = background,
    options = options,
    update = update
}
