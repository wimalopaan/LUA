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

local state, widget = ... 

local function statusRow(r)
    local sw_filter = lvgl.SW_LOGICAL_SWITCH | lvgl.SW_CLEAR;
    if (lvgl.SW_VIRTUAL ~= nil) then
        sw_filter = sw_filter | lvgl.SW_VIRTUAL;
    end
    return {
        type = "box",
        flexFlow = lvgl.FLOW_ROW,
        children = {
            {type = "label", text = "In " .. r},
            {type = "textEdit", value = widget.settings.telemActions[r].name, 
                    w = 50, maxLen = 16, set = (function(s) widget.settings.telemActions[r].name = s; end) },
            {type = "label", text = " Bit:" },
            {type = "numberEdit", min = 1, max = 8, w = 30, get = (function() return widget.settings.telemActions[r].input; end), 
                                                            set = (function(v) widget.settings.telemActions[r].input = v; end)},
            {type = "label", text = " Adr:" },
            {type = "numberEdit", min = 0, max = 255, w = 30, get = (function() return widget.settings.telemActions[r].address; end), 
                                                              set = (function(v) widget.settings.telemActions[r].address = v; end)},
            {type = "label", text = " Sw:" },
            {type = "switch", filter = sw_filter, w = 50,
                            get = (function() return widget.settings.telemActions[r].switch; end), 
                            set = (function(s) widget.settings.telemActions[r].switch = s; end) },
            {type = "label", text = " On:" },
            {type = "color", get = (function() return widget.settings.telemActions[r].colorOn; end),
                                            set = (function(v) widget.settings.telemActions[r].colorOn = v; end) },
            {type = "label", text = " Off:" },
            {type = "color", get = (function() return widget.settings.telemActions[r].colorOff; end),
                                            set = (function(v) widget.settings.telemActions[r].colorOff = v; end) },
        }
    };
end
local function statusRows()
    return {{
        type = "box",
        flexFlow = lvgl.FLOW_COLUMN,
        children = (function()
            local col = {};
            for r = 1, 8 do
                col[#col+1] = statusRow(r);
            end
            return col;
        end)()
    }
    };
end
function widget.telemetryPage()
    lvgl.clear();
    local page = lvgl.page({
        title = widget.titleString(),
        subtitle = "Telemetry-Settings",
        icon = widget.dir .. "Logo_30_inv.png",
        back = (function() widget.askClose(true); end),
    });
    local uit = {{
            type = "box",
            flexFlow = lvgl.FLOW_COLUMN,
            flexPad = lvgl.PAD_LARGE,
            w = widget.zone.w,
            children = statusRows()
         }};
    uit[1].children[#uit[1].children + 1] = { type = "hline", w = widget.zone.w / 2, h = 1 };
    uit[1].children[#uit[1].children + 1] = { type = "box", flexFlow = lvgl.FLOW_ROW, children = {
            {type = "image", file = widget.dir .. "Logo_small_64_t.png", w = 32, h = 32},
            {type = "box", w = 40},
            {type = "button", text = "Control", press = (function() widget.switchPage(widget.C.PAGE_CONTROL); end)},
            {type = "button", text = "Global", press = (function() widget.switchPage(widget.C.PAGE_GLOBALS); end)},
            {type = "button", text = "Settings", press = (function() widget.switchPage(widget.C.PAGE_SETTINGS); end)} 
        }
        };
    widget.ui = page:build(uit);
end
