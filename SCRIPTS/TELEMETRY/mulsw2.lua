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

-- ToDo:
-- implement 4-state switches (UI ???)
-- replace SHM vars with GVs for SBus encoding
-- enable SBus encoding
-- recalculate address table after changing buttons address
-- recalculate addresses after setting global address 
-- make rows/columns changeable -> more than one control page, more than two settings pages
-- better textEdit: highlight only actual cha being edited

-- Done:
-- S.Port protocols
-- immediate update (crsf may not be pushed immediately)
-- more than 8 switches
-- distinguish CRSF protos or use SET4M always

local environment = {
    name = "MulSW",
    longname = "MultiSwitch",
    dir = "/SCRIPTS/TELEMETRY/MULSW2/",
};

local ui = nil;

local function init()
--    print("init");
    ui = loadScript(environment.dir .. "lcdui.lua", "btd")(environment);
    ui.initGlobal("ui_init.lua");
    ui.addBackground("ui_bck.lua");
    local p = ui.addPage({script = "ui_ctrl.lua", instance = 1});
    if (ui.global.settings.pages == 2) then
        ui.addPage({script = "ui_ctrl.lua", instance = 2});
    end
    ui.addPage({script = "ui_set.lua", instance = 1});
    ui.addPage({script = "ui_set.lua", instance = 2});
    if (ui.global.settings.pages == 2) then
        ui.addPage({script = "ui_set.lua", instance = 3});
        ui.addPage({script = "ui_set.lua", instance = 4});
    end
    ui.addPage({script = "ui_glo.lua"});
    ui.addPage({script = "ui_inf.lua"});
    ui.activate(p);
end
local function run(event)
    ui.run(event);
end
local function background()
    ui.background();
end
return {
    init = init,
    run = run,
    background = background,
};