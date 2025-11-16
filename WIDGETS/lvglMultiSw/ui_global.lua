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

function widget.globalsPage() 
    lvgl.clear();
    local page = lvgl.page({
        title = widget.titleString(),
        subtitle = "Global-Settings",
        back = (function() widget.askClose(true); end),
    });
    local vswitch_box = {type = "box", flexFlow = lvgl.FLOW_ROW, flexPad = lvgl.PAD_LARGE, children = {}};
    if (widget.hasVirtualInputs) then
        vswitch_box.children = {
                    {type = "label", text = "Activate virtual switches: "},
                    {type = "toggle", get = (function() return widget.settings.activate_vswitches; end), 
                                      set = (function(v) 
                                        widget.settings.activate_vswitches = v;
                                        if (v > 0) then
                                            widget.activateVirtualSwitches();
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
                    {type = "numberEdit", min = 30, max = 80, w = 40, get = (function() return widget.settings.line_height; end), set = (function(v) widget.settings.line_height = v; end) }, 
                    {type = "label", text = "Radius momentary Button: "},
                    {type = "numberEdit", min = 10, max = 30, w = 40, get = (function() return widget.settings.momentaryButton_radius; end), set = (function(v) widget.settings.momentaryButton_radius = v; end) } 
                }},
                {type = "box", flexFlow = lvgl.FLOW_ROW, flexPad = lvgl.PAD_LARGE, children = {
                    {type = "label", text = "Show physical names: "},
                    {type = "toggle", get = (function() return widget.settings.show_physical; end), 
                                      set = (function(v) widget.settings.show_physical = v; end) }
                }},
                {type = "box", flexFlow = lvgl.FLOW_ROW, flexPad = lvgl.PAD_LARGE, children = {
                    {type = "label", text = "Show telemetry status: "},
                    {type = "toggle", get = (function() return widget.settings.statusPassthru; end), 
                                      set = (function(v) widget.settings.statusPassthru = v; end) }
                }},
                vswitch_box,
                {type = "box", flexFlow = lvgl.FLOW_ROW, flexPad = lvgl.PAD_LARGE, children = {
                    {type = "label", text = "Command broadcast address: "},
                    {type = "numberEdit", min = 0, max = 0xcf, w = 50, 
                                    get = (function() return widget.settings.commandBroadcastAddress; end), 
                                    set = (function(v) widget.settings.commandBroadcastAddress = v; end) } 
                }},
                {type = "box", flexFlow = lvgl.FLOW_ROW, flexPad = lvgl.PAD_LARGE, children = {
                    {type = "label", text = "Rows: "},
                    {type = "numberEdit", min = 1, max = 16, w = 40, get = (function() return widget.settings.rows; end), 
                     set = (function(v) 
                        lvgl.confirm({title="Exit", message="Confirm resets all settings!", confirm = (function() 
                            widget.settings.rows = v; 
                            widget.resetButtons();
                        end) })
                    end)}, 
                    {type = "label", text = "Columns: "},
                    {type = "numberEdit", min = 1, max = 4, w = 40, get = (function() return widget.settings.columns; end), 
                     set = (function(v) 
                        lvgl.confirm({title="Exit", message="Confirm resets all settings!", confirm = (function() 
                            widget.settings.columns = v; 
                            widget.resetButtons();
                        end) })
                    end) } 
                }},
                {type = "button", text = "Reset all Settings", press = (function() widget.resetSettings() end)},
                {type = "box", flexFlow = lvgl.FLOW_ROW, flexPad = lvgl.PAD_LARGE, children = {
                    {type = "button", text = "Send Colors", press = (function() widget.sendColors() end)},
                    {type = "toggle", get = (function() return widget.settings.activate_color_proto; end), 
                                      set = (function(v) widget.settings.activate_color_proto = v; end) }
                    }
                },
                {type = "hline", w = widget.zone.w / 2, h = 1 },
                {type = "box", flexFlow = lvgl.FLOW_ROW, children = {
                        {type = "button", text = "Settings", press = (function() widget.switchPage(widget.C.PAGE_SETTINGS); end)},
                        {type = "button", text = "Control", press = (function() widget.switchPage(widget.C.PAGE_CONTROL); end)}, 
                        {type = "button", text = "Telemetry", press = (function() widget.switchPage(widget.C.PAGE_TELEMETRY); end)} 
                    }
                }                        
            }}};
    uit[#uit + 1] = widget.saveIndicator();
    widget.ui = page:build(uit);
end

