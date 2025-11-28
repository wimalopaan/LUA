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

local state, widget = ... 

local function createSettingsDetails(i, edit_width) 
    widget.activePage = widget.C.PAGE_SETTINGS_D;
    local filter =  lvgl.SW_SWITCH | lvgl.SW_TRIM | lvgl.SW_LOGICAL_SWITCH | lvgl.SW_CLEAR;
    local setsw_filter = lvgl.SW_LOGICAL_SWITCH | lvgl.SW_CLEAR;
    local setsw_text = " Set LS:"
    if (widget.hasVirtualInputs) then
        filter = filter | lvgl.SW_VIRTUAL;
        setsw_filter = setsw_filter | lvgl.SW_VIRTUAL;
        setsw_text = " Set LS/VS:"
    end
    local column_width = widget.zone.w / 2 - 10;
    local box_width = column_width / 2;

    lvgl.clear();
    local page = lvgl.page({
        title = widget.titleString(),
        subtitle = "Output " .. i .. " details",
        back = (function() widget.switchPage(widget.C.PAGE_SETTINGS); end),
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
                            active = (function() if ((widget.settings.buttons[i].type == widget.C.TYPE_SLIDER) or (widget.settings.buttons[i].type == widget.C.TYPE_MOMENTARY)) then return false; else return true; end; end), 
                            get = (function() return widget.settings.buttons[i].switch; end), set = (function(s) widget.settings.buttons[i].switch = s; end) },
                        { type = "label", text = " Switch2:", 
                            active = (function() if (widget.settings.buttons[i].type == widget.C.TYPE_3POS) then return true; else return false; end; end) },
                        { type = "switch", filter = filter, 
                            active = (function() if (widget.settings.buttons[i].type == widget.C.TYPE_3POS) then return true; else return false; end; end),
                            get = (function() return widget.settings.buttons[i].switch2; end), set = (function(s) widget.settings.buttons[i].switch2 = s; end) },
                        { type = "label", text = " Source:" },
                        { type = "source", active = (function() if (widget.settings.buttons[i].type ~= widget.C.TYPE_SLIDER) then return false; else return true; end; end), 
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
                                                                              set = (function(v) widget.settings.buttons[i].address = v; widget.updateAddressButtonLookup(); end) }, 
                            {type = "label", text = "Output:"},
                            {type = "numberEdit", min = 1, max = 8, w = 40, get = (function() return widget.settings.buttons[i].output; end), 
                                                                              set = (function(v) widget.settings.buttons[i].output = v; widget.updateAddressButtonLookup(); end) }, 
                    }},
                    { type = "box", flexFlow = lvgl.FLOW_ROW, children = {
                            {type = "label", text = "Virtual-Input:"},
                            {type = "numberEdit", min = 0, max = 16, w = 60, get = (function() return widget.settings.buttons[i].setVirtualInput; end), 
                                                                             set = (function(v) 
                                                                                widget.settings.buttons[i].setVirtualInput = v; 
                                                                                widget.updateVirtualInputButtons();
                                                                                widget.virtualInputAutoMutexGroup(i);
                                                                             end),
                                                                             active = (function() return widget.hasVirtualInputs; end)}, 
                            {type = "label", text = "Value:"},
                            {type = "numberEdit", min = -100, max = 100, w = 40, get = (function() return widget.settings.buttons[i].setVirtualValue; end), 
                                                                                 set = (function(v) widget.settings.buttons[i].setVirtualValue = v; end),
                                                                                 active = (function() return (widget.settings.buttons[i].setVirtualInput > 0) and widget.hasVirtualInputs; end) }, 
                            {type = "label", text = "Auto Mutex-Grp:"},
                            {type = "toggle", get = (function() return widget.settings.buttons[i].virtualAutoMutexGroup; end), 
                                      set = (function(v) widget.settings.buttons[i].virtualAutoMutexGroup = v; end) }
                    }},
                    { type = "box", flexFlow = lvgl.FLOW_ROW, children = {
                        { type = "label", text = " Color:" },
                        { type = "color", get = (function() return widget.settings.buttons[i].color; end),
                                            set = (function(v) widget.settings.buttons[i].color = v; widget.fsm.sendEvent(2); end) },
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
                                active = (function() return (widget.settings.buttons[i].type == widget.C.TYPE_BUTTON) or (widget.settings.buttons[i].type == widget.C.TYPE_MOMENTARY) end)
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
            {type = "button", text = "Control", press = (function() widget.switchPage(widget.C.PAGE_CONTROL); end)},
            {type = "button", text = "Settings", press = (function() widget.switchPage(widget.C.PAGE_SETTINGS); end)},
            {type = "button", text = "Global", press = (function() widget.switchPage(widget.C.PAGE_GLOBALS); end)},
            {type = "button", text = "Telemetry", press = (function() widget.switchPage(widget.C.PAGE_TELEMETRY); end)}
            }
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
        title = widget.titleString(),
        subtitle = "Function-Settings",
        icon = widget.dir .. "Logo_30_inv.png",
        back = (function() widget.askClose(true); end),
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
            {type = "image", file = widget.dir .. "Logo_small_64_t.png", w = 32, h = 32},
            {type = "box", w = 40},
            {type = "button", text = "Control", press = (function() widget.switchPage(widget.C.PAGE_CONTROL); end)},
            {type = "button", text = "Global", press = (function() widget.switchPage(widget.C.PAGE_GLOBALS); end)},
            {type = "button", text = "Telemetry", press = (function() widget.switchPage(widget.C.PAGE_TELEMETRY); end)}, 
            {type = "button", text = "Virtuals", press = (function() widget.switchPage(widget.C.PAGE_VIRTUALS); end),
                                                 active = (function() return widget.hasVirtualInputs; end)} 
        }
        };
    uit[#uit + 1] = widget.saveIndicator();
    widget.ui = page:build(uit);
end
