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

-- INFO: One-Time-Script not possible / feasable: must run in the background when powering up to expansion-module 

-- TODO:
--- remove top-level box layout and use page directly (maybe need Edge PR 6841)
--- de/activate button: activate sending heartbeat (and using the serial interface)

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
    local page = lvgl.page({
        title = widget.name,
        subtitle = "Control",
        back = (function() widget.askClose(); end),
    });
    local top = {type = "box", flexFlow = lvgl.FLOW_ROW, children = {
                    {type = "label", x = 0, text = (function() return "LinkStat Tunnel Pkgs: " .. proto.linkcounter; end)},
                    {type = "label", x = LCD_W/2, text = (function() return "Telemetry Tunnel Pkgs: " .. proto.telemcounter; end)},
                }};
    local items = {top};
    local uit = {
        {type = "box", flexFlow = lvgl.FLOW_COLUMN, children = items}
    };
    widget.ui = page:build(uit);        
end
function widget.update()
    if (lvgl.isFullScreen() or lvgl.isAppMode()) then
        widget.mainPage();
    else
        widget.widgetPage();
    end
end
function widget.background()
    proto.tick();
end
function widget.refresh(event, touchState)
    widget.background();
end

return widget;
