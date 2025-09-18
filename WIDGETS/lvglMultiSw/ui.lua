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

--  requires
--- EdgeTx 2.11.1
--- Edgetx 2.11.2 momentary bug in EdgeTx, fix: PR 6460 

-- bugs
 
-- todo
--- implement 4-state switches(e.g. Led4x4) 
--- remove switch picker workaround (special case if switch name is nil)
--- S.Port queue for multiple addresses / do WM like ACW
--- Set64 protocol
--- images on non-buttons
--- text placing if images are used
--- split UI in different files (control, settings, global)
--- fsm.config() instead of different functions
--- autoconf fsm
--- global page: nicer (rectangle for line heigth and column width, columns)

-- done
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

local zone, options, name, dir = ...
local widget = {}
widget.options = options;
widget.zone = zone;
widget.name = name;

local PAGE_CONTROL  = 1;
local PAGE_SETTINGS = 2;
local PAGE_GLOBALS  = 3;

widget.ui = nil;
widget.activePage = PAGE_CONTROL;

local TYPE_BUTTON    = 1;
local TYPE_TOGGLE    = 2;
local TYPE_3POS      = 3;
local TYPE_MOMENTARY = 4;
local TYPE_SLIDER    = 5;

widget.settings = {};
local state = {};

local serialize = loadScript(dir .. "tableser.lua", "btd")();
local util      = loadScript(dir .. "util.lua", "btd")();
local crsf      = loadScript(dir .. "crsf.lua", "btd")(state, widget, dir, util);
local sport     = loadScript(dir .. "sport.lua", "btd")(state, widget, dir, util);
local fsm       = loadScript(dir .. "fsm.lua", "btd")(crsf, sport, widget, util);
local shm       = loadScript(dir .. "shm.lua", "btd")(widget, state, util);

local hasVirtualInputs = (getVirtualSwitch ~= nil);

local version = 16;
local settingsVersion = 21;
local versionString = "[" .. version .. "." .. settingsVersion .. "]";

local settingsFilename = nil;

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

local function titleString() 
    return widget.name .. "@" .. addressString() .. " : " .. widget.settings.name .. "  " .. versionString;
end

local function saveSettings() 
    if (settingsFilename ~= nil) then
        serialize.save(widget.settings, settingsFilename);        
    end
end
local function resetState() 
    for i = 1, (widget.settings.rows * widget.settings.columns) do
        state.buttons[i] = { value = 0 };
    end
end
local function updateAddressButtonLookup()
    print("updateAddressButtonLookup", #widget.settings.buttons);
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
        count = count + 1; -- need to count because #-op does count only contiguos tables 
    end
    -- print("count:", count);
    if (count > 1) then -- use SET4M protocol
        crsf.switchProtocol(2);
    else
        crsf.switchProtocol(1);
    end
end
local function resetButtons()
    widget.settings.buttons = {};
    state.buttons = {};
    for i = 1, (widget.settings.rows * widget.settings.columns) do
        widget.settings.buttons[i] = { name = "Output " .. i, type = TYPE_BUTTON, switch = 0, switch2 = 0, source = 0, visible = 1,
                                exclusive_group = 0,
                                activation_switch = 0, external_switch = 0, image = "",
                                output = ((i - 1) % 8) + 1, address = widget.options.Address + ((i - 1) // 8),
                                sport = {pwm_on = 0xff, options = 0x00, type = 0x01},
                                color = COLOR_THEME_SECONDARY3, textColor = COLOR_THEME_PRIMARY3, font = 0 };
    end
    updateAddressButtonLookup();
    resetState();    
    saveSettings();
end
local function resetSettings() 
    widget.settings.version = settingsVersion;
    widget.settings.imagesdir = "/IMAGES/";
    widget.settings.name = "Beleuchtung";
    widget.settings.line_height = 45;
    widget.settings.momentaryButton_radius = 20;
    widget.settings.show_physical = 1;
    widget.settings.activate_vswitches = 0;
    widget.settings.activate_color_proto = 0;
    widget.settings.rows = 4;
    widget.settings.columns = 2;
    resetButtons();
end
resetSettings();
local function isValidSettingsTable(t) 
    if (t.version ~= nil) then
        if (t.version == settingsVersion) then
            return true;
        end
    end
    return false;
end
local function updateFilename()
    local fname = dir .. model.getInfo().name .. "_" .. widget.options.Address .. ".lua";
    if (fname ~= settingsFilename) then
        settingsFilename = fname;
        return true;
    end
    return false;
end
updateFilename();

local function activateVirtualSwitches() 
    print("activateVirtualSwitches");
    if (widget.settings.activate_vswitches > 0) then
        if (hasVirtualInputs) then
            for i = 1, 64 do
                -- print("activate vsw:", i);
                activateVirtualSwitch(i, true);        
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
        fsm.update();
        return true;
    end
    return false;
end

local function checkButton(i, v)
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
        if (btn.type == TYPE_SLIDER) then
            if (btn.source > 0) then
             local v = getSourceValue(btn.source) / 10.24;
                if (v ~= nil) then
                    btnstate.value = v;
                end
            end
        else
            if (btn.switch > 0) then
                local v  = (btn.switch > 0 ) and getSwitchValue(btn.switch);
                local v2 = (btn.switch2 > 0) and getSwitchValue(btn.switch2);
                if (setButton(btnstate, v, v2)) then
                    checkButton(i, v);
                end
            end
        end      
    end
end

function widget.switchPage(id)
    --print("switchPage", id);
    fsm.sendEvent(2);
    lvgl.clear()
    if (id == PAGE_CONTROL) then
        widget.controlPage()
    elseif (id == PAGE_SETTINGS) then
        widget.settingsPage()
    elseif (id == PAGE_GLOBALS) then
        widget.globalsPage()
    else
        --print("unknown id:", id)
    end
    widget.activePage = id
    saveSettings();
end

local function invert(v) 
    if (v == 0) then
        return 1;
    else
        return 0;
    end    
end

local function setLSorVs(sw, on)
    if (sw > 0) then
        local swname = getSwitchName(sw);
        local swtype = string.sub(swname, 1, 1);
        if (swtype == "L") then
            local lsnumber = string.sub(swname, 2, 3);
            local lsn = tonumber(lsnumber) - 1;
            --print("LS: ", lsnumber, lsn, on);
            setStickySwitch(lsn, on);
        elseif (swtype == "V") then
            if (hasVirtualInputs) then
                local vsnumber = string.sub(swname, 3, 4);
                --print("VS: ", swname, vsnumber, on);
                setVirtualSwitch(vsnumber, on);
            end
        end
    end
end

local function processButtonGroup(bnum) 
    local egr = widget.settings.buttons[bnum].exclusive_group;
    if ((state.buttons[bnum].value > 0) and (egr > 0)) then
        for i, btn in ipairs(widget.settings.buttons) do
            if ((i ~= bnum) and (egr == btn.exclusive_group)) then
                if (state.buttons[i].value > 0) then
                    state.buttons[i].value = 0;
                    checkButton(i, false);
                    setLSorVs(widget.settings.buttons[i].external_switch, false);
                end
            end            
        end
    end
end

local function updateButton(i)
    processButtonGroup(i);
    fsm.update();
    setLSorVs(widget.settings.buttons[i].external_switch, (state.buttons[i].value > 0));
end

local function isSwitchActive(i)
    local possible_active = (widget.settings.buttons[i].activation_switch == 0) or getSwitchValue(widget.settings.buttons[i].activation_switch);
    if (possible_active) then
        if (widget.settings.buttons[i].switch > 0) then 
            return false; 
        else 
            return true; 
        end; 
    else
        return false;
    end
end

local function createButton(i, width)
    --print("createButton");
    if (widget.settings.buttons[i].visible == 0) then
        return;
    end
    local ichild = {};
    if (widget.settings.buttons[i].image ~= "") then
        ichild = {{ type = "image", file = widget.settings.imagesdir .. widget.settings.buttons[i].image, x = 0, y = -5, 
                                                                                    w = widget.settings.line_height, 
                                                                                    h = widget.settings.line_height}};        
    end
    if (widget.settings.buttons[i].type == TYPE_BUTTON) then
        return { type = "button", name = "b" .. i, text = (function() 
                    local sw = widget.settings.buttons[i].switch * widget.settings.show_physical;
                    if (sw ~= 0) then
                        local swname = getSwitchName(sw);
                        if (swname ~= nil) then
                            return widget.settings.buttons[i].name .. " (" .. getSwitchName(sw) .. ")";
                        else                            
                            return widget.settings.buttons[i].name .. " (?)";
                        end
                    else
                        return widget.settings.buttons[i].name;
                    end
                 end)(), 
                 w = width, h = widget.settings.line_height, 
                 color = widget.settings.buttons[i].color, textColor = widget.settings.buttons[i].textColor, font = widget.settings.buttons[i].font,
                 press = (function() state.buttons[i].value = invert(state.buttons[i].value); updateButton(i); return state.buttons[i].value; end),
                 active = (function() return isSwitchActive(i); end),
                 checked = (state.buttons[i].value ~= 0),
                 children = ichild
            };
    elseif (widget.settings.buttons[i].type == TYPE_MOMENTARY) then
        return { type = "momentaryButton", text = widget.settings.buttons[i].name, 
        w = width, h = widget.settings.line_height, cornerRadius = widget.settings.momentaryButton_radius,
        color = widget.settings.buttons[i].color, textColor = widget.settings.buttons[i].textColor, font = widget.settings.buttons[i].font,
        press = (function() state.buttons[i].value = 1; updateButton(i); end),
        release = (function() state.buttons[i].value = 0; updateButton(i); end),
        active = (function() return isSwitchActive(i); end),
        children = ichild
    };
    elseif (widget.settings.buttons[i].type == TYPE_3POS) then
        return {type = "box", flexFlow = lvgl.FLOW_ROW, children = {
            { type = "label", text = (function() 
                local sw = widget.settings.buttons[i].switch * widget.settings.show_physical;
                local sw2 = widget.settings.buttons[i].switch2;
                if (sw > 0) then
                    return widget.settings.buttons[i].name .. " (" .. getSwitchName(sw) .. "|" .. getSwitchName(sw2) .. ")";
                else
                    return widget.settings.buttons[i].name;
                end
             end)(), 
              w = width / 2, font = widget.settings.buttons[i].font},
            { type = "slider", min = -1, max = 1, 
                                get = (function() local v = state.buttons[i].value; if (v <= 1) then return v; else return -1; end; end), 
                                set = (function(v) if (v == -1) then state.buttons[i].value = 2; else state.buttons[i].value = v; end; updateButton(i); end), 
                                active = (function() return isSwitchActive(i); end),
                                w = width / 2, color = widget.settings.buttons[i].color, 
                            }
        }};
    elseif (widget.settings.buttons[i].type == TYPE_TOGGLE) then
        return {type = "box", flexFlow = lvgl.FLOW_ROW, x = 0, w = width, children = {
            { type = "label", text = (function() 
                local sw = widget.settings.buttons[i].switch * widget.settings.show_physical;
                if (sw > 0) then
                    return widget.settings.buttons[i].name .. " (" .. getSwitchName(sw) .. ")";
                else
                    return widget.settings.buttons[i].name;
                end
             end)(), 
              w = width / 2, x = 0, font = widget.settings.buttons[i].font, 
            },
            { type = "toggle", get = (function() if (state.buttons[i].value ~= 0) then return 1; else return 0; end; end), 
                               set = (function(v) state.buttons[i].value = v; updateButton(i); end), w = width / 2 ,
                               active = (function() return isSwitchActive(i); end),
                               color = widget.settings.buttons[i].color }
        }};
    elseif (widget.settings.buttons[i].type == TYPE_SLIDER) then
        return {type = "box", flexFlow = lvgl.FLOW_ROW, children = {
            { type = "label", text = (function() 
                local so = widget.settings.buttons[i].source * widget.settings.show_physical;
                if (so > 0) then
                    return widget.settings.buttons[i].name .. " (" .. getSourceName(so) .. ")";
                else
                    return widget.settings.buttons[i].name;
                end
             end)(), 
              w = width / 3, font = widget.settings.buttons[i].font},
            { type = "slider", min = -100, max = 100, get = (function() return state.buttons[i].value; end),
                                                      set = (function(v) state.buttons[i].value = v; crsf.sendProp(i, v); end), w = (2 * width) / 3,
                                                      active = (function() if (widget.settings.buttons[i].source > 0) then return false; else return true; end; end),
                                                      color = widget.settings.buttons[i].color
                                                    }
        }};
    end
end

local function askClose()
    lvgl.confirm({title="Exit", message="Really exit?", confirm=(function() lvgl.exitFullScreen(); end) })
end
  
local function sendColors()
    fsm.sendColors();
end

function widget.globalsPage() 
    lvgl.clear();
    local page = lvgl.page({
        title = titleString(),
        subtitle = "Global-Settings",
        back = (function() askClose(); end),
    });
    local vswitch_box = {type = "box", flexFlow = lvgl.FLOW_ROW, flexPad = lvgl.PAD_LARGE, children = {}};
    if (hasVirtualInputs) then
        vswitch_box.children = {
                    {type = "label", text = "Activate virtual switches: "},
                    {type = "toggle", get = (function() return widget.settings.activate_vswitches; end), 
                                      set = (function(v) 
                                        widget.settings.activate_vswitches = v;
                                        if (v > 0) then
                                            activateVirtualSwitches();
                                        end
                                    end) }
                };        
    end

    local uit = {{
            type = "box",
            w = widget.zone.w, 
            flexFlow = lvgl.FLOW_COLUMN,
            children = {
                {type = "box", flexFlow = lvgl.FLOW_ROW, flexPad = lvgl.PAD_LARGE, children = {
                    {type = "label", text = "Widget-Name: "},
                    {type = "textEdit", value = widget.settings.name, w = 150, maxLen = 16, set = (function(s) widget.settings.name = s; end) } 
                }},
                {type = "box", flexFlow = lvgl.FLOW_ROW, flexPad = lvgl.PAD_LARGE, children = {
                    {type = "label", text = "Line Height: "},
                    {type = "numberEdit", min = 30, max = 60, w = 40, get = (function() return widget.settings.line_height; end), set = (function(v) widget.settings.line_height = v; end) }, 
                    {type = "label", text = "Radius momentary Button: "},
                    {type = "numberEdit", min = 10, max = 30, w = 40, get = (function() return widget.settings.momentaryButton_radius; end), set = (function(v) widget.settings.momentaryButton_radius = v; end) } 
                }},
                {type = "box", flexFlow = lvgl.FLOW_ROW, flexPad = lvgl.PAD_LARGE, children = {
                    {type = "label", text = "Show physical names: "},
                    {type = "toggle", get = (function() return widget.settings.show_physical; end), 
                                      set = (function(v) widget.settings.show_physical = v; end) }
                }},
                vswitch_box,
                {type = "box", flexFlow = lvgl.FLOW_ROW, flexPad = lvgl.PAD_LARGE, children = {
                    {type = "label", text = "Rows: "},
                    {type = "numberEdit", min = 1, max = 16, w = 40, get = (function() return widget.settings.rows; end), 
                     set = (function(v) 
                        lvgl.confirm({title="Exit", message="Confirm resets all settings!", confirm = (function() 
                            widget.settings.rows = v; 
                            resetButtons();
                        end) })
                    end)}, 
                    {type = "label", text = "Columns: "},
                    {type = "numberEdit", min = 1, max = 4, w = 40, get = (function() return widget.settings.columns; end), 
                     set = (function(v) 
                        lvgl.confirm({title="Exit", message="Confirm resets all settings!", confirm = (function() 
                            widget.settings.columns = v; 
                            resetButtons();
                        end) })
                    end) } 
                }},
                {type = "button", text = "Reset all Settings", press = (function() resetSettings() end)},
                {type = "box", flexFlow = lvgl.FLOW_ROW, flexPad = lvgl.PAD_LARGE, children = {
                    {type = "button", text = "Send Colors", press = (function() sendColors() end)},
                    {type = "toggle", get = (function() return widget.settings.activate_color_proto; end), 
                                      set = (function(v) widget.settings.activate_color_proto = v; end) }
                    }
                },
                {type = "hline", w = widget.zone.w / 2, h = 1 },
                {type = "box", flexFlow = lvgl.FLOW_ROW, children = {
                        {type = "button", text = "Settings", press = (function() widget.switchPage(PAGE_SETTINGS); end)},
                        {type = "button", text = "Control", press = (function() widget.switchPage(PAGE_CONTROL); end)} 
                    }
                }                        
            }}};
    widget.ui = page:build(uit);
end

function widget.controlPage()
    --print("controlPage", widget);
    lvgl.clear();
    local page = lvgl.page({
        title = titleString(),
        subtitle = "Control",
        back = (function() askClose(); end),
    });

    local column_width = widget.zone.w / widget.settings.columns - 10;
    local button_width = widget.zone.w / widget.settings.columns - 40;

    local columns = {};
    for c = 1, widget.settings.columns do
        columns[c] = {};
        for r = 1, widget.settings.rows do
            local b = createButton(r + (c - 1) * widget.settings.rows, button_width);
            if (b) then
                columns[c][#columns[c]+1] = b;
            end
        end
    end

    local uit = {{ type = "box", flexFlow = lvgl.FLOW_COLUMN, children = {
        { type = "box",
            flexFlow = lvgl.FLOW_ROW,
            children = (function() 
                local cols = {};
                for c = 1, widget.settings.columns do
                    cols[c] = {type = "box", w = column_width, flexFlow = lvgl.FLOW_COLUMN, flexPad = lvgl.PAD_LARGE, children = columns[c],};
                end
                return cols;
            end)(),
        },
        { type = "hline", w = widget.zone.w / 2, h = 1 },
        { type = "box", flexFlow = lvgl.FLOW_ROW, children = {
                {type = "button", text = "Settings", press = (function() widget.switchPage(PAGE_SETTINGS); end)},
                {type = "button", text = "Global", press = (function() widget.switchPage(PAGE_GLOBALS); end)} }
        }
    }}};
    if (page ~= nil) then
        widget.ui = page:build(uit);        
    end
end

local function createSettingsDetails(i, edit_width) 
    --print("createDetails", i);
    local filter =  lvgl.SW_SWITCH | lvgl.SW_TRIM | lvgl.SW_LOGICAL_SWITCH | lvgl.SW_CLEAR;
    local setsw_filter = lvgl.SW_LOGICAL_SWITCH | lvgl.SW_CLEAR;
    local setsw_text = " Set LS:"
    if (hasVirtualInputs) then
        filter = filter | lvgl.SW_VIRTUAL;
        setsw_filter = setsw_filter | lvgl.SW_VIRTUAL;
        setsw_text = " Set LS/VS:"
    end
    local column_width = widget.zone.w / 2 - 10;
    local box_width = column_width / 2;

    lvgl.clear();
    local page = lvgl.page({
        title = titleString(),
        subtitle = "Output " .. i .. " details",
        back = (function() widget.switchPage(PAGE_SETTINGS); end),
    });
    local uit = {{type = "box", flexFlow = lvgl.FLOW_COLUMN, w = widget.zone.w, children = {
                    { type = "box", flexFlow = lvgl.FLOW_ROW, children = {
                        { type = "label", text = " Visible:" },
                        { type = "toggle", get = (function() return widget.settings.buttons[i].visible; end),
                                           set = (function(v) widget.settings.buttons[i].visible = v; end) },
                        { type = "label", text = " Activation:"},
                        { type = "switch", filter = filter, 
                            get = (function() return widget.settings.buttons[i].activation_switch; end), set = (function(s) widget.settings.buttons[i].activation_switch = s; end) },
                        { type = "label", text = setsw_text},
                        { type = "switch", filter = setsw_filter, 
                            active = (function() return (widget.settings.buttons[i].switch == 0); end),
                            get = (function() return widget.settings.buttons[i].external_switch; end), set = (function(s) widget.settings.buttons[i].external_switch = s; end) },
                        }},
                    { type = "box", flexFlow = lvgl.FLOW_ROW, children = {
                        { type = "label", text = " Switch:"},
                        { type = "switch", filter = filter, 
                            active = (function() if ((widget.settings.buttons[i].type == TYPE_SLIDER) or (widget.settings.buttons[i].type == TYPE_MOMENTARY)) then return false; else return true; end; end), 
                            get = (function() return widget.settings.buttons[i].switch; end), set = (function(s) widget.settings.buttons[i].switch = s; end) },
                        { type = "label", text = " Switch2:", 
                            active = (function() if (widget.settings.buttons[i].type == TYPE_3POS) then return true; else return false; end; end) },
                        { type = "switch", filter = filter, 
                            active = (function() if (widget.settings.buttons[i].type == TYPE_3POS) then return true; else return false; end; end),
                            get = (function() return widget.settings.buttons[i].switch2; end), set = (function(s) widget.settings.buttons[i].switch2 = s; end) },
                        { type = "label", text = " Source:" },
                        { type = "source", active = (function() if (widget.settings.buttons[i].type ~= TYPE_SLIDER) then return false; else return true; end; end), 
                                            get = (function() return widget.settings.buttons[i].source; end), 
                                            set = (function(s) widget.settings.buttons[i].source = s; end) },
                        {type = "label", text = "Mutex-Group:" },
                        {type = "numberEdit", min = 0, max = (widget.settings.rows * widget.settings.columns) / 2, w = 60, 
                            active = (function() if (widget.settings.buttons[i].switch == 0) then return true; else return false; end; end),
                            get = (function() return widget.settings.buttons[i].exclusive_group; end), 
                            set = (function(v) widget.settings.buttons[i].exclusive_group = v; end) }, 

                    }},
                    { type = "box", flexFlow = lvgl.FLOW_ROW, children = {
                            {type = "label", text = "Address:", color = (function() if (widget.settings.buttons[i].address ~= widget.options.Address) then return COLOR_THEME_WARNING; else return COLOR_THEME_SECONDARY1; end; end)},
                            {type = "numberEdit", min = 0, max = 255, w = 60, get = (function() return widget.settings.buttons[i].address; end), 
                                                                              set = (function(v) widget.settings.buttons[i].address = v; updateAddressButtonLookup(); end) }, 
                            {type = "label", text = "Output:"},
                            {type = "numberEdit", min = 1, max = 8, w = 40, get = (function() return widget.settings.buttons[i].output; end), 
                                                                              set = (function(v) widget.settings.buttons[i].output = v; updateAddressButtonLookup(); end) }, 
                    }},
                    { type = "box", flexFlow = lvgl.FLOW_ROW, children = {
                        { type = "label", text = " Color:" },
                        { type = "color", get = (function() return widget.settings.buttons[i].color; end),
                                            set = (function(v) widget.settings.buttons[i].color = v; fsm.sendEvent(2); end) },
                        { type = "label", text = " TextColor:" },
                        { type = "color", get = (function() return widget.settings.buttons[i].textColor; end),
                                            set = (function(v) widget.settings.buttons[i].textColor = v; end) },                                     
                        { type = "label", text = " Font:" },
                        { type = "font", get = (function() return widget.settings.buttons[i].font; end),
                                        set = (function(v) widget.settings.buttons[i].font = v; end), w = 2 * edit_width / 3 },                                     
                    }},
                    { type = "box", flexFlow = lvgl.FLOW_ROW, children = {
                        { type = "label", text = " Image:" },
                        { type = "file", title = "Image", folder = "/IMAGES",
                                get = (function() return widget.settings.buttons[i].image; end),
                                set = (function(v) widget.settings.buttons[i].image = v; end), 
                                active = (function() return (widget.settings.buttons[i].type == TYPE_BUTTON) or (widget.settings.buttons[i].type == TYPE_MOMENTARY) end)
                        },
                    }},
                    { type = "box", flexFlow = lvgl.FLOW_ROW, children = (function() 
                        if (widget.options.SPortProto == 2) then
                            return {
                                {type = "label", text = "SPort(ACW) pwm:"},
                                {type = "numberEdit", min = 0, max = 255, w = 60, get = (function() return widget.settings.buttons[i].sport.pwm_on; end), 
                                                                                  set = (function(v) widget.settings.buttons[i].sport.pwm_on = v; end)},};
                        else
                            return {};
                        end
                        end)()
                    }}
                }};
    uit[1].children[#uit[1].children + 1] = { type = "hline", w = widget.zone.w / 2, h = 1 };
    uit[1].children[#uit[1].children + 1] = { type = "box", flexFlow = lvgl.FLOW_ROW, children = {
            {type = "button", text = "Control", press = (function() widget.switchPage(PAGE_CONTROL); end)},
            {type = "button", text = "Settings", press = (function() widget.switchPage(PAGE_SETTINGS); end)},
            {type = "button", text = "Global", press = (function() widget.switchPage(PAGE_GLOBALS); end)} }
        };
    page:build(uit);
end

local function createSettingsRow(i, edit_width, maxLen)
    local filter =  lvgl.SW_SWITCH | lvgl.SW_TRIM | lvgl.SW_LOGICAL_SWITCH | lvgl.SW_CLEAR;
    if (lvgl.SW_VIRTUAL ~= nil) then
        filter = filter | lvgl.SW_VIRTUAL;
    end
    return {
        type = "box",
        flexFlow = lvgl.FLOW_ROW,
        children = {
            {type = "label", text = "Output " .. i, font = BOLD },
            {type = "label", text = " Name:"},
            {type = "textEdit", value = widget.settings.buttons[i].name, w = edit_width, maxLen = maxLen, set = (function(s) widget.settings.buttons[i].name = s; end) },
            {type = "label", text = " Type:" },
            {type = "choice", title = "Type", values = {"Button", "Toggle", "3Pos", "Momentary", "Slider"}, w = edit_width,
                               get = (function() return widget.settings.buttons[i].type; end), set = (function(t) widget.settings.buttons[i].type = t; end) }, 
            {type = "button", text = "Details", textColor = (function() if (widget.settings.buttons[i].address ~= widget.options.Address) then return COLOR_THEME_WARNING; else return COLOR_THEME_SECONDARY1; end; end), 
                press = (function() createSettingsDetails(i, edit_width); end)},
        }
    };
end

local function createSettingsRows(edit_width, maxLen)
    local children = {};
    for i = 1, (widget.settings.rows * widget.settings.columns) do
        children[i] = createSettingsRow(i, edit_width, maxLen);
    end
    return children;
end

function widget.settingsPage()
    lvgl.clear();
    local page = lvgl.page({
        title = titleString(),
        subtitle = "Function-Settings",
        back = (function() askClose(); end),
    });
    local edit_width = widget.zone.w / 6;
    local maxLen = 16;
    local uit = { {
            type = "box",
            flexFlow = lvgl.FLOW_COLUMN,
            flexPad = lvgl.PAD_LARGE,
            w = widget.zone.w,
            children = createSettingsRows(edit_width, maxLen);
         }
    };
    uit[1].children[#uit[1].children + 1] = { type = "hline", w = widget.zone.w / 2, h = 1 };
    uit[1].children[#uit[1].children + 1] = { type = "box", flexFlow = lvgl.FLOW_ROW, children = {
            {type = "button", text = "Control", press = (function() widget.switchPage(PAGE_CONTROL); end)},
            {type = "button", text = "Global", press = (function() widget.switchPage(PAGE_GLOBALS); end)} }
        };
    widget.ui = page:build(uit);
end

local oldSettings = nil;
function widget.widgetPage()
    lvgl.clear();
    widget.ui = lvgl.build({
        { type = "box", flexFlow = lvgl.FLOW_COLUMN, children = {
            { type = "label", text = widget.name, w = widget.zone.x, align = CENTER},
            { type = "label", text = (function() 
                if (oldSettings ~= nil) then
                    return widget.settings.name .. "@" .. addressString() .. " (CV)";
                else
                    return widget.settings.name .. "@" .. addressString();
                end
                end), 
                w = widget.zone.x, align = CENTER }, }
        }
    });
end
local function convertSettings(t)
    if (t.version ~= nil) then
        resetSettings();
        for k, v in pairs(t) do
--            print("cv:", k, v);
            if (k ~= "buttons") then
                widget.settings[k] = v;
            else
                for bi, b in ipairs(t.buttons) do
                    for kk, vv in pairs(b) do
--                        print("cv button:", bi, kk, vv);
                        widget.settings.buttons[bi][kk] = vv;                    
                    end
                end
            end
        end
        widget.settings.version = settingsVersion;
        return true;
    end
    return false;
end

local initialized = false;
function widget.update()
    --print("widget.update");
    if (oldSettings ~= nil) then
        serialize.save(oldSettings, settingsFilename .. "." .. oldSettings.version); -- save old file with new name
        oldSettings = nil;
    end
    local changed = updateFilename();
    fsm.intervall(widget.options.Intervall + (widget.options.Address % 15)); -- dither timeout a little bit
    fsm.autoconf(widget.options.Autoconf);
    if ((not initialized) or changed) then
        local st = serialize.load(settingsFilename);
        if (st ~= nil) then
            if (isValidSettingsTable(st)) then
                widget.settings = st;
                resetState();
            else
                if (not convertSettings(st)) then
                    resetSettings();
                else
                    oldSettings = st;
                end
                changed = true;
            end
        else -- no file
            resetSettings();
            changed = true;
        end
        initialized = true;
    end
    updateAddressButtonLookup();
    activateVirtualSwitches();
    if (lvgl.isFullScreen() or lvgl.isAppMode()) then
        widget.switchPage(PAGE_CONTROL);
    else
        widget.widgetPage();
    end
    if (changed) then
        saveSettings();
    end
end

local function configItemCallback(item)
    --print("configItemCallback:", item);
end 

local lastTlm = 0;
local function isConnected()
    local tlm = getValue("RQly");
    local r = false;
    if (lastTlm == 0) and (tlm > 0) then
        r = true;
    end
    lastTlm = tlm;
    return r;
end

function widget.background()
    if (isConnected()) then
        fsm.sendEvent(2);
    end
    fsm.tick(configItemCallback);
    readPhysical();
    shm.encode();
end

local function fullScreenRefresh()
end

function widget.refresh(event, touchState)
    --    print("refresh", widget.zone.x, widget.zone.y);
    if lvgl == nil then
        lcd.drawText(widget.zone.x, widget.zone.y, "Lvgl support required", COLOR_THEME_WARNING)
    end
    if (lvgl.isFullScreen()) then
        fullScreenRefresh();
    end
    widget.background();
end

return widget;
