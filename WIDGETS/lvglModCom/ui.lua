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

local zone, options, name, dir, proto = ...
local widget = {}
widget.options = options;
widget.zone = zone;
widget.name = name;
widget.dir = dir;
widget.proto = proto;

widget.ui = nil;

local version = 1;
local versionString = "[" .. version .. "]";

function widget.askClose(save)
    lvgl.confirm({title="Exit", message="Really exit?", confirm=(function() 
        lvgl.exitFullScreen();
    end) })
end
function widget.widgetPage()
    lvgl.clear();
    widget.ui = lvgl.build({
        {type = "box", flexFlow = lvgl.FLOW_COLUMN, children = {
            {type = "label", text = widget.name, w = widget.zone.x, align = CENTER},
            {type = "label", text = "V: " .. versionString, w = widget.zone.x, align = CENTER, font = SMLSIZE},
            }}
        });
end
function widget.mainPage()
    lvgl.clear();
    local col = LCD_W / 4 - 1;
    local page = lvgl.page({
        title = widget.name,
        subtitle = "Control",
        back = (function() widget.askClose(); end),
    });
    local top = {type = "box", flexFlow = lvgl.FLOW_ROW, children = {
                    {type = "button", text = "Calibrate", name = "bcal", press = (function() proto.startCalibrate(); end)},
                    {type = "button", text = "Show", name = "bshow", press = (function() proto.stopCalibrate(); end)},
                    {type = "label",  w = col/4, text = ""},
                    {type = "button", text = "Save & Run", press = (function() proto.startNormal(); end), textColor = COLOR_THEME_WARNING}
                }};
    local items = {top};
    items[#items+1] = {type = "box", flexFlow = lvgl.FLOW_ROW, children = {
                        {type = "label", w = col, text = (function() 
                                return "Packages: " .. proto.data.packages;
                        end)},
                        {type = "label", w = col, text = (function() 
                            return "Status: " .. proto.data.status;
                        end)},
                        {type = "label", w = col, text = (function() 
                                return "Switches: " .. proto.data.switches;
                        end)},
                    }};
    for i = 1, 8 do
       items[#items+1] = {type = "box", flexFlow = lvgl.FLOW_ROW, children = {
            {type = "label", w = col / 2, text = "In " .. i .. ":"},
            {type = "label", w = col, text = (function() 
                if (proto.data.maxs[i]) then
                    return "Max: " .. proto.data.maxs[i];
                else
                    return "Max: -";
                end
            end)},
            {type = "label", w = col, text = (function() 
                if (proto.data.mins[i]) then
                    return "Min: " .. proto.data.mins[i];
                else
                    return "Min: -";
                end
            end)},
            {type = "label", w = col, text = (function() 
                if (proto.data.values[i]) then
                    return "Value: " .. proto.data.values[i];
                else
                    return "Value: -";
                end
            end)},
        }};
    end

    local uit = {
        {type = "box", flexFlow = lvgl.FLOW_COLUMN, children = items}
    };
    widget.ui = page:build(uit);        
end
function widget.update()
    if (lvgl.isFullScreen() or lvgl.isAppMode()) then
        setSerialBaudrate(115200);
        widget.mainPage();
    else
        widget.widgetPage();
    end
end
function widget.background()
    proto.tick();
    if (proto.data.status == 2) then
        local bcal = widget.ui["bcal"];
        if (bcal) then
            bcal:set({checked = true});
        end
        local bshow = widget.ui["bshow"];
        if (bshow) then
            bshow:set({checked = false});
        end
    elseif (proto.data.status == 1) then
        local bcal = widget.ui["bcal"];
        if (bcal) then
            bcal:set({checked = false});
        end
        local bshow = widget.ui["bshow"];
        if (bshow) then
            bshow:set({checked = true});
        end
    end
end
function widget.refresh(event, touchState)
    widget.background();
end

return widget;
