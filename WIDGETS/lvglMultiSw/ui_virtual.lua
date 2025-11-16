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

local function virtualsRow(r)
    return {
        type = "box",
        flexFlow = lvgl.FLOW_ROW,
        children = {
            {type = "label", text = "Virtual Input: " .. r},
            {type = "label", text = " Off Value: "},
            {type = "numberEdit", min = -100, max = 100, w = 60, 
                            active = (function() return state.virtuals[r] ~= nil; end),
                            get = (function() return widget.settings.virtualInputs[r].off; end), 
                            set = (function(v) widget.settings.virtualInputs[r].off = v; end)},
        }
    };
end
local function virtualsRows()
    return {{
        type = "box",
        flexFlow = lvgl.FLOW_COLUMN,
        children = (function()
            local col = {};
            for r = 1, 16 do
                col[#col+1] = virtualsRow(r);
            end
            return col;
        end)()
    }
    };
end
function widget.virtualInputsPage()
    lvgl.clear();
    local page = lvgl.page({
        title = widget.titleString(),
        subtitle = "Virtual-Inputs-Settings",
        back = (function() widget.askClose(true); end),
    });
    local uit = {{
            type = "box",
            flexFlow = lvgl.FLOW_COLUMN,
            flexPad = lvgl.PAD_LARGE,
            w = widget.zone.w,
            children = virtualsRows()
         }};
    uit[1].children[#uit[1].children + 1] = { type = "hline", w = widget.zone.w / 2, h = 1 };
    uit[1].children[#uit[1].children + 1] = { type = "box", flexFlow = lvgl.FLOW_ROW, children = {
            {type = "button", text = "Control", press = (function() widget.switchPage(widget.C.PAGE_CONTROL); end)},
            {type = "button", text = "Global", press = (function() widget.switchPage(widget.C.PAGE_GLOBALS); end)},
            {type = "button", text = "Settings", press = (function() widget.switchPage(widget.C.PAGE_SETTINGS); end)} 
        }
        };
    widget.ui = page:build(uit);
end

