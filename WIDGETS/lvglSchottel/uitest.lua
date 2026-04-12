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

local zone, options, name, dir = ...
local widget = {}
widget.options = options;
widget.zone = zone;
widget.name = name;
widget.ui = nil;

local tr1;
function widget.controlPage()
    lvgl.clear();
    local page = lvgl.page({
        title = widget.name,
    });
--    page:line{pts = {{0, 0}, {100, 100}}, thickness = 1};
    tr1 = page:triangle({color = COLOR_THEME_WARNING});
end

function widget.widgetPage()
    lvgl.clear();
    widget.ui = lvgl.build({
        { type = "box", flexFlow = lvgl.FLOW_COLUMN, children = {
            { type = "label", text = widget.name, w = widget.zone.x, align = CENTER}}
        }
    });
end
function widget.update()
    widget.controlPage();
end
function widget.background()
    if (tr1 ~= nil) then
        tr1:set({pts = {{10, 10}, {100, 10}, {50, 50}}, color = COLOR_THEME_WARNING});        
    end
end
function widget.refresh(event, touchState)
    if lvgl == nil then
        lcd.drawText(widget.zone.x, widget.zone.y, "Lvgl support required", COLOR_THEME_WARNING)
    end
    -- widget.background();
end

return widget;
