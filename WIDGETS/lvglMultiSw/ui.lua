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

--  requires
--- EdgeTx 2.11.1
--- Edgetx 2.11.2 momentary bug in EdgeTx, fix: PR 6460 
--- EdgeTx 2.11.3 
--- EdgeTx PR 6958 (physical switch does not set button in checked state)

-- bugs 
--- maybe: touch button press experience some delay to sending crsf package? hw-button maybe without delay?

-- todo
--- option to transfer morse-text (like rgb-color)
--- adapt for larger screens (e.g. use percent based height of buttons)
--- use explicit layout instead of box layout for less overhead
--- remove top-level box layout and use page directly (maybe need Edge PR 6841)
--- place logo image
--- introduce config page (remove widget options)
--- global page: nicer (rectangle for line heigth and column width, columns)
--- move some (all) Widget-settings to global config dialog
--- implement 4-state switches(e.g. Led4x4) 
--- remove switch picker workaround (special case if switch name is nil)
--- S.Port queue for multiple addresses / do WM like ACW
--- Set64 protocol
--- images on non-buttons
--- text placing if images are used

-- done
--- prop-set with physical source does not work 
--- show loading error if config file errorneous
--- saving/loading settings sometimes may not work: SD-card problem? CPU-limit?
--- produce logging data (optional)
--- grey-out label in settings if button unvisible
--- auto-mutex-group, if virtual-inputs are used
--- introduce state counter to visualize longer loading/saving times
--- split UI in different files (control, settings, global)
--- increase max height of buttons (e.g. for 2x1 design)
--- visualize states of state-machine
--- check for lvgl only in create()
--- load submodules in state-machine
--- add setting a value for virtual inputs
--- fixed settingsDetails page switching issue
--- real event-queue
--- make background a state-machine to distributed compute intense tasks to different calls e.g. resetButtons() and saveSettings()
--- use events to control the background state-machine,e.g. change the number of cols/rows
--- reaches CPU limit if saving config after converting
--- reaches CPU limit if saving of old config enabled (see setting SAVE_OLD_CONFIG)
--- sliders don't use correct switch-address 
--- read all crsf messages from queue and parse them (reduces the change of congestion of widget queue)
--- adapt to new passthru format (with switch address, maybe display crsf-address)
--- configure / set LS or VS by telemetry 
--- get ArduPilot/PassThru tunnel messages transporting MultiSwitch-Input (In0, In1) states (make that optional)
--- display ArduPilot/PassThru SubType=Switch and AppId=Status in header line or left/right of buttons
--- add command broadcast address option (ELRS V3 does not route BCast. ELRS V4 is correct )
--- sendProp Bug
--- implement seetings version mirgration (save old settings in: <name>_<address>.lua.<version>)
--- converting theme / predefined colors to RGB888 does not work correctly. Workaround: use RGB color picker
--- theme colors are stored as indices, so: how to convert color indices to RGB565 / RGB565 values?
--- add setting to activate color protocol setRGB
--- implement color updates
--- reset also external switches in mutex-group 
--- add synchronization between this widget and mixer script crsfch.lua (suspend crsfch.lua as long as updates are send from widget)
--- add exclusive-groups (default N/2 groups, select a group for a swicth or none)
--- enable virtual-switches (switch-picker, activate vswitches in global options)
--- adapt SHM protocol if multiple addresses are found (maybe send only buttons with widget address)
--- state update for sbus encoding
--- reset button state if leaving/entering without changing anything (regression error)
--- use the visible attribute
--- timeout for SPort sending (WM) -> ok on radio
--- don't duplicate settings into state
--- A.Cwalina S.port proto 
--- switching address causes nil access
--- Enabling Options: SHM, S.Port, CRSF
--- S.Port 
--- display version number (storage version)
--- flexible layout: column / row count
--- per-button: address/output 
--- indicator, if button has different address as widget 
--- new SET4M protocol
--- images on buttons
--- cleanup settings page 
--- restore button state when switch page/update

-- Settings:

local SAVE_OLD_CONFIG = true; -- saves old config if converting to new config file version
local logging = {
    enabled = false,
    file = "log.txt",
    console = true;
};

-- End of Settings

local zone, options, name, dir = ...
local widget = {}
widget.options = options;
widget.zone = zone;
widget.name = name;
widget.dir = dir;
widget.logging = {};
function widget.logging.log() end;

local C = {};
C.PAGE_NONE       = 0;
C.PAGE_CONTROL    = 1;
C.PAGE_SETTINGS   = 2;
C.PAGE_GLOBALS    = 3;
C.PAGE_TELEMETRY  = 4;
C.PAGE_SETTINGS_D = 5;
C.PAGE_VIRTUALS   = 6;

C.TYPE_BUTTON    = 1;
C.TYPE_TOGGLE    = 2;
C.TYPE_3POS      = 3;
C.TYPE_MOMENTARY = 4;
C.TYPE_SLIDER    = 5;

C.EVT_NONE          = 0;
C.EVT_FILE_CHANCE   = 1;
C.EVT_WIDGET_CHANGE = 2;
C.EVT_STATE_CHANGE  = 3;
C.EVT_INIT          = 4;
C.EVT_RESET         = 5;
C.EVT_ALT_FILE      = 6;

widget.C = C;

widget.ui = nil;
widget.activePage    = C.PAGE_NONE;
widget.settings = {};
widget.hasVirtualInputs = (getVirtualSwitch ~= nil);

local state = {};

local version = 34;
local settingsVersion = 30;
local versionString = "[" .. version .. "." .. settingsVersion .. "]";

local settingsFilename = nil;

local eventQueue = {};
local function eventPush(e)
    eventQueue[#eventQueue + 1] = e;
end
local function eventPop(evt)
    for k, e in pairs(eventQueue) do
        if (e == evt) then
            eventQueue[k] = nil;
            return true;
        end
    end
    return false;
end

local BG_STATE_UNDEF          = 0;
local BG_STATE_INIT           = 1;
local BG_STATE_HAS_FILE       = 2;
local BG_STATE_NO_FILE        = 3;
local BG_STATE_CONVERT        = 4;
local BG_STATE_SAVE           = 5;
local BG_STATE_SAVE_OLD       = 6;
local BG_STATE_UPDATE_MAPPINGS= 7;
local BG_STATE_ACTIVATE_VS    = 8;
local BG_STATE_RUN            = 10;
local BG_STATE_LOAD_UTILS0    = 11;
local BG_STATE_LOAD_UTILS1    = 12;
local BG_STATE_LOAD_UTILS2    = 13;
local BG_STATE_LOAD_UTILS3    = 14;
local BG_STATE_LOAD_UTILS4    = 15;
local BG_STATE_LOAD_UTILS5    = 16;
local BG_STATE_LOAD_UTILS6    = 17;
local BG_STATE_LOAD_CONTROL   = 18;
local BG_STATE_LOAD_SETTINGS  = 19;
local BG_STATE_LOAD_GLOBAL    = 20;
local BG_STATE_LOAD_VIRTUAL   = 21;
local BG_STATE_LOAD_TELEMETRY = 22;
local BG_STATE_ERROR_STOP     = 23;
local BG_STATE_SAVE_UPDATE    = 24;

local bg_state = BG_STATE_UNDEF;
local stateCounter = 0;

local function addressString() 
    local min = widget.options.Address;
    local max = widget.options.Address;
    for _, btn in pairs(widget.settings.buttons) do
        if (btn.address < min) then
            min = btn.address;
        elseif (btn.address > max) then
            max = btn.address;
        end
    end
    if (min == max) then
        return min;
    else
        return "[" .. min .. "," .. max .. "]";
    end
end
function widget.titleString() 
    local statusString = "[_]";
    if (widget.fsm.getStatusOk()) then
        statusString = "[C]";
    end
    return widget.name .. "@" .. addressString() .. " : " .. widget.settings.name .. "  " .. versionString .. " " .. statusString;
end
local function saveSettingsIncremental() 
    if (settingsFilename ~= nil) then
        return widget.serialize.saveIncremental(widget.settings, settingsFilename);        
    end
    return true;
end
local function resetState() 
    state.remoteStatus = {};
    for i = 1, 8 do
        state.remoteStatus[i] = 0;
    end
    for i = 1, (widget.settings.rows * widget.settings.columns) do
        state.buttons[i] = { value = 0 };
    end
    if (widget.hasVirtualInputs) then
        for i, btns in pairs(state.virtuals) do
            setVirtualInput(i, widget.settings.virtualInputs[i].off * 10.24);
        end
    end
end
function widget.updateAddressButtonLookup()
    state.addresses = {};
    for i, btn in ipairs(widget.settings.buttons) do
        if (state.addresses[btn.address] == nil) then
            state.addresses[btn.address] = {i};
        else
            state.addresses[btn.address][#state.addresses[btn.address] + 1] = i;
        end
    end
    local count = 0; 
    for _ in pairs(state.addresses) do
        count = count + 1; -- need to count because #-op does count only contiguous tables 
    end
    if (count > 1) then -- use SET4M protocol
        widget.crsf.switchProtocol(2);
    else
        widget.crsf.switchProtocol(1);
    end
end
function widget.virtualInputAutoMutexGroup(btn)
    if (widget.settings.buttons[btn].virtualAutoMutexGroup > 0) then
        local vi = widget.settings.buttons[btn].setVirtualInput;
        if (vi > 0) then
            local count = 0;
            local egr = 0;
            local max_egr = 0;
            for i, b in ipairs(widget.settings.buttons) do
                if (b.exclusive_group > max_egr) then
                    max_egr = b.exclusive_group;
                end
                if (i ~= btn) then
                    if (vi == b.setVirtualInput) then
                        count = count + 1;
                        egr = b.exclusive_group;
                    end                    
                end
            end
            if (count > 0) then
                if (egr > 0) then
                    widget.settings.buttons[btn].exclusive_group = egr;
                else
                    egr = max_egr + 1;
                    widget.settings.buttons[btn].exclusive_group = egr;
                    for i, b in ipairs(widget.settings.buttons) do
                        if (i ~= btn) then
                            if (vi == b.setVirtualInput) then
                                b.exclusive_group = egr;
                            end                    
                        end
                    end
                end
            end
        end
    end
end
function widget.updateVirtualInputButtons()
    state.virtuals = {};
    for i, btn in ipairs(widget.settings.buttons) do
        if (btn.setVirtualInput > 0) then
            if (state.virtuals[btn.setVirtualInput] == nil) then
                state.virtuals[btn.setVirtualInput] = {i};
            else
                state.virtuals[btn.setVirtualInput][#state.virtuals[btn.setVirtualInput] + 1] = i;
            end
        end
    end
end
local function resetButton(i)
    widget.settings.buttons[i] = { name = "Output " .. i, type = C.TYPE_BUTTON, switch = 0, switch2 = 0, source = 0, visible = 1,
                            exclusive_group = 0,
                            activation_switch = 0, external_switch = 0, image = "",
                            setVirtualInput = 0, setVirtualValue = 0, virtualAutoMutexGroup = 1,
                            output = ((i - 1) % 8) + 1, address = widget.options.Address + ((i - 1) // 8),
                            sport = {pwm_on = 0xff, options = 0x00, type = 0x01},
                            color = COLOR_THEME_SECONDARY3, textColor = COLOR_THEME_PRIMARY3, font = 0 };
end
function widget.resetButtons()
    widget.logging.log("resetButtons");
    widget.settings.buttons = {};
    widget.settings.telemActions = {};
    for i = 1, 8 do
        widget.settings.telemActions[i] = {name = "In" .. i, input = i, switch = 0, address = widget.options.Address,
                                            colorOff = COLOR_THEME_SECONDARY2, colorOn = COLOR_THEME_WARNING};
    end
    widget.settings.virtualInputs = {};
    for i = 1, 16 do
        widget.settings.virtualInputs[i] = {off = 0};
    end
    state.buttons = {};
    for i = 1, (widget.settings.rows * widget.settings.columns) do
        resetButton(i);
    end
    widget.updateAddressButtonLookup();
    widget.updateVirtualInputButtons();
    resetState();    
    eventPush(C.EVT_FILE_CHANCE);
end
local function resetSettingsOnly()
    widget.logging.log("resetSettingsOnly");
    widget.settings.version = settingsVersion;
    widget.settings.imagesdir = "/IMAGES/";
    widget.settings.name = "Beleuchtung";
    widget.settings.momentaryButton_radius = 20;
    widget.settings.show_physical = 1;
    widget.settings.activate_vswitches = 0;
    widget.settings.activate_color_proto = 0;
    widget.settings.rows = 4;
    widget.settings.columns = 2;
    widget.settings.line_height = (LCD_H * 0.75) / widget.settings.rows;
    widget.settings.commandBroadcastAddress = 0xc8;
    widget.settings.statusPassthru = 0;
    widget.settings.logging = 0;
end
function widget.resetSettings() 
    widget.logging.log("resetSettings");
    resetSettingsOnly();
    widget.resetButtons();
end
--resetSettings();
local function isValidSettingsTable(t) 
    widget.logging.log("iSValidSettings");
    if (t.version ~= nil) then
        if (t.version == settingsVersion) then
            return true;
        end
    end
    return false;
end
local function updateFilename()
    widget.logging.log("updateFilename");
    local fname = dir .. model.getInfo().name .. "_" .. widget.options.Address .. ".lua";
    if (fname ~= settingsFilename) then
        settingsFilename = fname;
        return true;
    end
    return false;
end
updateFilename();

function widget.activateVirtualSwitches() 
    if (widget.settings.activate_vswitches > 0) then
        if (widget.hasVirtualInputs) then
            for i = 1, 64 do
                activateVirtualSwitch(i, true);        
            end
            for i = 1, 16 do
                activateVirtualInput(i, true);        
            end
        end        
    end
end

local function bool2int(v)
    if (v) then return 1; end
    return 0;
end

local function setButton(btnstate, v, v2)
    local vv = bool2int(v) + 2 * bool2int(v2);
    if (vv ~= btnstate.value) then
        btnstate.value = vv;
        widget.fsm.update();
        return true;
    end
    return false;
end
function widget.setLSorVs(sw, on)
    if (sw > 0) then
        local swname = getSwitchName(sw);
        local swtype = string.sub(swname, 1, 1);
        if (swtype == "L") then
            local lsnumber = string.sub(swname, 2, 3);
            local lsn = tonumber(lsnumber) - 1;
            setStickySwitch(lsn, on);
        elseif (swtype == "V") then
            if (widget.hasVirtualInputs) then
                local vsnumber = string.sub(swname, 3, 4);
                setVirtualSwitch(vsnumber, on);
            end
        end
    end
end
function widget.checkButton(i, v)
    if (widget.ui ~= nil) then
        -- todo: caching ref
        local b = widget.ui["b" .. i];
        if (b ~= nil) then
            b:set({checked = v});
        end
    end        
end

local function readPhysical() 
    for i, btn in ipairs(widget.settings.buttons) do
        local btnstate = state.buttons[i];
        if (btn.type == C.TYPE_SLIDER) then
            if (btn.source ~= 0) then
                local v = getSourceValue(btn.source);
                if (v ~= nil) then
                    v = math.max(v / 10.24, 0);
                    if (math.abs(v - btnstate.value) > 1) then
                        btnstate.value = v;
                        widget.crsf.sendProp(i, v);                    
                    end
                end
            end
        else
            if (btn.switch > 0) then
                local v  = (btn.switch > 0 ) and getSwitchValue(btn.switch);
                local v2 = (btn.switch2 > 0) and getSwitchValue(btn.switch2);
                if (setButton(btnstate, v, v2)) then
                    widget.checkButton(i, v);
                end
            end
        end      
    end
end

function widget.switchPage(id, nosave)
    widget.logging.log("switchPage %d %s", id, nosave);
    widget.fsm.sendEvent(2);
    if (id == widget.activePage) then
        return;
    end
    lvgl.clear()
    if (id == C.PAGE_CONTROL) then
        widget.controlPage()
    elseif (id == C.PAGE_SETTINGS) then
        widget.settingsPage()
    elseif (id == C.PAGE_GLOBALS) then
        widget.globalsPage()
    elseif (id == C.PAGE_TELEMETRY) then
        widget.telemetryPage()
    elseif (id == C.PAGE_VIRTUALS) then
        widget.virtualInputsPage()
    else
        --print("unknown id:", id)
    end
    widget.activePage = id;
    if (not nosave) then
        eventPush(C.EVT_FILE_CHANCE);
    end
end
function widget.askClose(save)
    lvgl.confirm({title="Exit", message="Really exit?", confirm=(function() 
        lvgl.exitFullScreen();
        if (save) then
            eventPush(C.EVT_FILE_CHANCE);
        end
    end) })
end
function widget.sendColors()
    widget.fsm.sendColors();
end
function widget.saveIndicator() 
    return {type = "rectangle", x = 0, y = 0, w = LCD_W, h = 2, filled = true, 
            color = (function()
                if ((bg_state == BG_STATE_SAVE) or (bg_state == BG_STATE_SAVE_OLD)) then
                    return COLOR_THEME_WARNING; 
                else
                    return COLOR_THEME_SECONDARY3; 
                end 
            end)};
end

local converted = false;
function widget.widgetPage()
    widget.logging.log("widgetPage");
    lvgl.clear();
    widget.ui = lvgl.build({
        { type = "box", flexFlow = lvgl.FLOW_COLUMN, children = {
            { type = "label", text = widget.name, w = widget.zone.x, align = CENTER},
            { type = "label", text = (function() 
                if (converted) then
                    converted = false;
                    return widget.settings.name .. "@" .. addressString() .. " (CV)";
                else
                    return widget.settings.name .. "@" .. addressString();
                end
                end), 
                w = widget.zone.x, align = CENTER }, 
            { type = "label", text = "V: " .. versionString, w = widget.zone.x, align = CENTER, font = SMLSIZE},
--            { type = "image", file = dir .. "Logo_small_64_8.png"}
            }
        }
    });
end
function widget.loadingPage()
    widget.logging.log("loadingPage");
    lvgl.clear();
    widget.ui = lvgl.build({
        { type = "box", flexFlow = lvgl.FLOW_COLUMN, children = {
            { type = "label", text = widget.name, w = widget.zone.x, align = CENTER},
            { type = "label", text = (function() return "Loading ... " .. bg_state .. "/" .. stateCounter; end), w = widget.zone.x, align = CENTER }
        }}
    });
end
local alternatesettingsfilename = settingsFilename;
local err_reason = "-";
function widget.errorPage()
    widget.logging.log("errorPage");
    lvgl.clear();
    widget.ui = lvgl.build({
        { type = "box", flexFlow = lvgl.FLOW_COLUMN, children = {
            { type = "label", text = widget.name, w = widget.zone.x, align = CENTER},
            { type = "label", text = "Error!", w = widget.zone.x, align = CENTER },
            { type = "label", text = "Please switch to fullscreen!", w = widget.zone.x, align = CENTER }
        }}
    });
end
function widget.errorPageFull()
    widget.logging.log("errorPageFull");
    lvgl.clear();
    local page = lvgl.page({
        title = widget.titleString(),
        subtitle = "Error Handling",
        icon = widget.dir .. "Logo_30_inv.png";
        back = (function() widget.askClose(false); end),
    });
    widget.ui = page:build({
        {type = "box", flexFlow = lvgl.FLOW_COLUMN, children = {
            {type = "label", text = "Sadly an error occurred. Now you have the following options:"},
            {type = "label", text = "Reason: " .. err_reason},
            {type = "button", text = "Reset and overwrite config file", 
                    press = (function() 
                        eventPush(C.EVT_RESET); 
                        err_reason = "-";
                    end)},
            {type = "button", text = "Retry", press = (function() eventPush(C.EVT_INIT); end)},
            {type = "button", text = "Stop widget", press = (function() widget.askClose(false); end)},
            {type = "box", flexFlow = lvgl.FLOW_ROW, children = {
                {type = "file", title = "Config file", folder = widget.dir, 
                        set = (function(f) alternatesettingsfilename = widget.dir .. f; end),
                        get = (function() return alternatesettingsfilename; end)},
                {type = "button", text = "Reset with alternative config file", press = (function() 
                    eventPush(C.EVT_ALT_FILE); 
                    err_reason = "-";
                end)},
            }},
            {type = "label",  
                    visible = (function() return bg_state ~= BG_STATE_ERROR_STOP; end), 
                    text = (function() return "Loading ... " .. bg_state .. "/" .. stateCounter; end), w = widget.zone.x, align = CENTER }
            }
        }
    });
end
local function convertSettings(t)
    widget.logging.log("conertSettings");
    if (t.version ~= nil) then
        resetSettingsOnly();
        for k, v in pairs(t) do
            if (k ~= "buttons") then
                widget.settings[k] = v;
            else
                for bi, b in ipairs(t.buttons) do
                    resetButton(bi);
                    for kk, vv in pairs(b) do
                        widget.settings.buttons[bi][kk] = vv;                    
                    end
                end
            end
        end
        widget.settings.version = settingsVersion;
        resetState();
        return true;
    end
    return false;
end

function widget.update()
    widget.logging.log("update");
    if(updateFilename()) then
        eventPush(C.EVT_FILE_CHANCE);
    else 
        eventPush(C.EVT_WIDGET_CHANGE);
    end
end

local function configItemCallback(item)
end 

local lastTlm = 0;
local function gotConnected()
    local tlm = getValue("RQly");
    local r = false;
    if (lastTlm == 0) and (tlm > 0) then
        r = true;
    end
    lastTlm = tlm;
    return r;
end

local st = nil;
function widget.background()
    --print("background");
    local oldstate = bg_state;
    stateCounter = stateCounter + 1;
    if (bg_state == BG_STATE_UNDEF) then
        bg_state = BG_STATE_LOAD_UTILS0;       
    elseif (bg_state == BG_STATE_LOAD_UTILS0) then
        widget.logging = loadScript(dir .. "log.lua", "btd")(widget, logging);
        bg_state = BG_STATE_LOAD_UTILS1;       
    elseif (bg_state == BG_STATE_LOAD_UTILS1) then
        widget.serialize = loadScript(dir .. "tableser.lua", "btd")(widget.logging);
        bg_state = BG_STATE_LOAD_UTILS2;       
    elseif (bg_state == BG_STATE_LOAD_UTILS2) then
        widget.util      = loadScript(dir .. "util.lua", "btd")();
        bg_state = BG_STATE_LOAD_UTILS3;       
    elseif (bg_state == BG_STATE_LOAD_UTILS3) then
        widget.crsf      = loadScript(dir .. "crsf.lua", "btd")(state, widget, dir);
        bg_state = BG_STATE_LOAD_UTILS4;       
    elseif (bg_state == BG_STATE_LOAD_UTILS4) then
        widget.sport     = loadScript(dir .. "sport.lua", "btd")(state, widget, dir);
        bg_state = BG_STATE_LOAD_UTILS5;       
    elseif (bg_state == BG_STATE_LOAD_UTILS5) then
        widget.fsm       = loadScript(dir .. "fsm.lua", "btd")(widget, state);
        bg_state = BG_STATE_LOAD_UTILS6;       
    elseif (bg_state == BG_STATE_LOAD_UTILS6) then
        widget.shm       = loadScript(dir .. "shm.lua", "btd")(widget, state);
        widget.resetSettings();
        bg_state = BG_STATE_LOAD_SETTINGS;       
    elseif (bg_state == BG_STATE_LOAD_SETTINGS) then
        local s = loadScript(dir .. "ui_settings.lua", "btd")(state, widget);
        bg_state = BG_STATE_LOAD_CONTROL;       
    elseif (bg_state == BG_STATE_LOAD_CONTROL) then
        local s = loadScript(dir .. "ui_control.lua", "btd")(state, widget);
        bg_state = BG_STATE_LOAD_GLOBAL;       
    elseif (bg_state == BG_STATE_LOAD_GLOBAL) then
        local s = loadScript(dir .. "ui_global.lua", "btd")(state, widget);
        bg_state = BG_STATE_LOAD_VIRTUAL;       
    elseif (bg_state == BG_STATE_LOAD_VIRTUAL) then
        local s = loadScript(dir .. "ui_virtual.lua", "btd")(state, widget);
        bg_state = BG_STATE_LOAD_TELEMETRY;       
    elseif (bg_state == BG_STATE_LOAD_TELEMETRY) then
        local s = loadScript(dir .. "ui_telemetry.lua", "btd")(state, widget);
        bg_state = BG_STATE_INIT;       
    elseif (bg_state == BG_STATE_INIT) then
        local err;
        st, err = widget.serialize.load(settingsFilename);
        if (st ~= nil) then
            bg_state = BG_STATE_HAS_FILE;
        else
            widget.logging.log("loading error: %s", err);
            if (err) then
                err_reason = err;            
            end
            eventPush(C.EVT_WIDGET_CHANGE);
            bg_state = BG_STATE_ERROR_STOP;
        end
    elseif (bg_state == BG_STATE_HAS_FILE) then
        if (isValidSettingsTable(st)) then
            widget.settings = st;
            bg_state = BG_STATE_UPDATE_MAPPINGS;
        else
            bg_state = BG_STATE_CONVERT;
        end
    elseif (bg_state == BG_STATE_CONVERT) then
        if (not convertSettings(st)) then
            eventPush(C.EVT_WIDGET_CHANGE);
            bg_state = BG_STATE_ERROR_STOP;
        else
            converted = true;
            if (SAVE_OLD_CONFIG) then
                bg_state = BG_STATE_SAVE_OLD;
            else
                bg_state = BG_STATE_SAVE_UPDATE;
            end
        end
    elseif (bg_state == BG_STATE_NO_FILE) then
        widget.resetSettings();
        bg_state = BG_STATE_SAVE_UPDATE;
    elseif (bg_state == BG_STATE_SAVE_OLD) then
        if (widget.serialize.saveIncremental(st, settingsFilename .. "." .. st.version)) then -- save old file with new name
            bg_state = BG_STATE_SAVE_UPDATE;
        end
    elseif (bg_state == BG_STATE_UPDATE_MAPPINGS) then
        widget.updateAddressButtonLookup();
        widget.updateVirtualInputButtons();
        resetState();
        bg_state = BG_STATE_ACTIVATE_VS;
    elseif (bg_state == BG_STATE_ACTIVATE_VS) then
        widget.activateVirtualSwitches();
        eventPush(C.EVT_WIDGET_CHANGE);
        bg_state = BG_STATE_RUN;
    elseif (bg_state == BG_STATE_SAVE_UPDATE) then
        if (saveSettingsIncremental()) then
            bg_state = BG_STATE_UPDATE_MAPPINGS;  
        end
    elseif (bg_state == BG_STATE_SAVE) then
        if (saveSettingsIncremental()) then
            eventPush(C.EVT_WIDGET_CHANGE);
            bg_state = BG_STATE_RUN;  
        end
    elseif (bg_state == BG_STATE_RUN) then
        if (eventPop(C.EVT_FILE_CHANCE)) then
            bg_state = BG_STATE_SAVE;
        end
        if (gotConnected()) then
            widget.fsm.sendEvent(2);
        end
        widget.fsm.tick(configItemCallback);
        readPhysical();
        widget.shm.encode();
    elseif (bg_state == BG_STATE_ERROR_STOP) then
        if (eventPop(C.EVT_FILE_CHANCE)) then
            err_reason = "-";
            bg_state = BG_STATE_INIT;
        elseif (eventPop(C.EVT_RESET)) then
            err_reason = "-";
            bg_state = BG_STATE_NO_FILE;
        elseif (eventPop(C.EVT_ALT_FILE)) then
            err_reason = "-";
            local err;
            st, err = widget.serialize.load(alternatesettingsfilename);
            widget.logging.log("loading err: %s", err);
            if (err) then
                err_reason = err;
            end
            if (st ~= nil) then
                bg_state = BG_STATE_HAS_FILE;
            end
        end
    end
    if (oldstate ~= bg_state) then
        stateCounter = 0;
        widget.logging.log("state %d %s %d", oldstate, "->", bg_state);        
    end
end

function widget.refresh(event, touchState)
    widget.background();
    if (eventPop(C.EVT_WIDGET_CHANGE)) then
        if ((bg_state == BG_STATE_RUN) or (bg_state == BG_STATE_SAVE)) then
            if (lvgl.isFullScreen() or lvgl.isAppMode()) then
                if (widget.activePage > 0) then
                    widget.switchPage(widget.activePage, true);
                else                    
                    widget.switchPage(C.PAGE_CONTROL, true);
                end
            else
                widget.activePage = 0;
                widget.widgetPage();
            end
        elseif (bg_state == BG_STATE_ERROR_STOP) then
            if (lvgl.isFullScreen() or lvgl.isAppMode()) then
                widget.activePage = 0;
                widget.errorPageFull();            
            else
                widget.activePage = 0;
                widget.errorPage();            
            end
        else
            widget.activePage = 0;
            widget.loadingPage();
        end
    end
end

return widget;
