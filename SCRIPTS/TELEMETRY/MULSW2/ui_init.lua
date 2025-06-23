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

local global = {
    RF = {CRSF = 1, SPORT = 2, SBUS = 3},
    settings = {},
    state = {
        buttons = {}
    };
    version = 5,
    settingsVersion = 3,
    settingsFilename = env.dir .. model.getInfo().name .. ".lua",
--    crsfProto = 2, -- always use SET4M
    radio = 1, -- 1: 192KB, 2: 128kb (disable some menus)
    shm = 0, -- SHM on b&w only available im compiled with SHMBW=YES (WM branch)
}
local function resetState() 
    for i = 1, (global.settings.rows * global.settings.columns) do
        global.state.buttons[i] = { value = 0 };
    end
end
local function updateAddressButtonLookup()
    resetState();
    global.state.addresses = {};
    for i, btn in ipairs(global.settings.buttons) do
        if (global.state.addresses[btn.address] == nil) then
            global.state.addresses[btn.address] = {i};
        else
            global.state.addresses[btn.address][#global.state.addresses[btn.address] + 1] = i;
        end
    end
end
local function resetButtons()
    global.settings.buttons = {};
    global.state.buttons = {};
    for i = 1, (global.settings.rows * global.settings.columns) do
        global.settings.buttons[i] = { name = "Output " .. i, switch = uilib.switchIndexNone,  
                                activation_switch = 0, external_switch = 0,
                                output = ((i - 1) % 8) + 1, address = global.settings.Address + ((i - 1) // 8)};
        global.settings.buttons[i].sport = {pwm_on = 0xff, options = 0x00, type = 0x01};
    end
    updateAddressButtonLookup();
end
local function resetSettings() 
    global.settings = {};
    global.settings.version = global.settingsVersion;
    global.settings.rflink = global.RF.CRSF; 
    global.settings.Address = 0;
    global.settings.SPort = {
        Phy = 0x1b,
        App = 0x51,
        Proto = 1
    };
    global.settings.Intervall = 100;
    global.settings.name = "Beleuchtung";
    global.settings.show_physical = 1;
    global.settings.rows = 4;
    global.settings.columns = 2;
    resetButtons();
end
local function init()
    local ver, radio, maj, minor, rev, osname = getVersion();
    if (radio == "t12") then
        global.radio = 2;
    elseif (radio == "x9d") then
        global.radio = 2;
    elseif (radio == "x9d+") then
        global.radio = 2;
    else 
        global.radio = 1;
    end
    if (getShmVar ~= nil) then
        global.shm = 1;
    end
    local table_read = loadScript(env.dir .. "table_read.lua", "btd")();
    local st = table_read.load(global.settingsFilename);
    if ((st ~= nil) and (st.version == global.settingsVersion)) then
        global.settings = st;
        updateAddressButtonLookup();
    else
        resetSettings();
    end
    return global;
end

return {
    init = init;
}
