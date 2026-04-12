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

-- ToDo:
--- Drain CRSF-queue until empty, then pass last message to parser


-- Done:
--- protocol version for sending only position/throttle data


local zone, options, name, dir = ...
local widget = {}
widget.options = options;
widget.zone = zone;
widget.name = name;
widget.ui = {};

local serialize = loadScript(dir .. "tableser.lua", "btd")();
local fsm       = loadScript(dir .. "fsm.lua", "btd")();
local crsf      = loadScript(dir .. "crsf.lua", "btd")(dir);

local version = 1;
local settings = {};
local settingsFilename = dir .. model.getInfo().name .. ".lua";
local settingsVersion = 2;

local function resetSettings() 
    settings.gauge = {
        arrow = {
            thickness = 12,
            rfactor = 0.9
        },
        line = {
            thickness = 4,
        },
        ticks = {
            thickness = 3,
            rfactor1 = 0.95,
            rfactor2 = 0.9
        },
        center = {
            radius = 5,
            color = COLOR_THEME_PRIMARY3
        },
        outer = {
            thickness = 2,
            color1 = COLOR_THEME_PRIMARY1,
            color2 = COLOR_THEME_SECONDARY1
        }
    };
end

local function saveSettings() 
    serialize.save(settings, settingsFilename);
end

local function askClose()
    lvgl.confirm({title = "Exit", message = "Really exit?", confirm = (function() saveSettings(); lvgl.exitFullScreen(); end) })
end
local function versionString() 
    return "[" .. version .. "." .. settingsVersion .."]";
end
local function updateGauge(g, center, radius, params)
--    print("update", g, center, radius, params);
    local offset = widget.options.Offset;
    local steer = params.steer;
    local actual = params.actual;
    local throttle = params.power;

    local r3 = radius / settings.gauge.arrow.rfactor;
    local r4 = radius * settings.gauge.arrow.rfactor;

    local offset_phi = offset * (math.pi / 2);
    -- negative phi, disply is upside-down
    local steer_phi  = -math.pi * steer / 2048 + offset_phi;
    local actual_phi = -math.pi * actual / 2048 + offset_phi;
    local thr_norm = math.min(1, throttle / 820);
    local thr_r = radius * (1 - thr_norm);

    local cos_steer_phi = math.cos(steer_phi);
    local sin_steer_phi = math.sin(steer_phi);

    local steer_xe = center.x - radius * cos_steer_phi;
    local steer_ye = center.y - radius * sin_steer_phi;

    local r5 = math.min(r4, thr_r);
    local ix = center.x - r5 * cos_steer_phi;
    local iy = center.y - r5 * sin_steer_phi;
    local d = settings.gauge.arrow.thickness;
    local dx = d * sin_steer_phi;
    local dy = d * cos_steer_phi;
    local steer_x2 = ix - dx;
    local steer_y2 = iy + dy;
    local steer_x3 = ix + dx;
    local steer_y3 = iy - dy;
    g.tr1:set({pts = {{steer_xe, steer_ye}, {steer_x2, steer_y2}, {steer_x3, steer_y3}}, color = COLOR_THEME_WARNING});

    local cos_actual_phi = math.cos(actual_phi);
    local sin_actual_phi = math.sin(actual_phi);
    local actual_x1 = center.x - radius * cos_actual_phi;
    local actual_y1 = center.y - radius * sin_actual_phi;
    ix = center.x - r3 * cos_actual_phi;
    iy = center.y - r3 * sin_actual_phi;
    dx = d * sin_actual_phi;
    dy = d * cos_actual_phi;
    local actual_x2 = ix - dx;
    local actual_y2 = iy + dy;
    local actual_x3 = ix + dx;
    local actual_y3 = iy - dy;
    g.tr2:set({pts = {{actual_x1, actual_y1}, {actual_x2, actual_y2}, {actual_x3, actual_y3}}, color = COLOR_THEME_EDIT});

    g.line:set({pts = {{center.x, center.y}, {steer_xe, steer_ye}}});

end

local function createGauge(page, center, radius)
    page:circle({x = center.x, y = center.y, radius = settings.gauge.center.radius, filled = true, color = settings.gauge.center.color});
    page:circle({x = center.x, y = center.y, radius = radius, thickness = settings.gauge.outer.thickness});

    for i = 0, 11 do
        local phi = (2 * math.pi * i) / 12;
        local r1 = radius * settings.gauge.ticks.rfactor1;
        local r2 = radius / settings.gauge.ticks.rfactor1;
        local color = settings.gauge.outer.color1;
        if ((i % 3) == 0) then
            r1 = radius * settings.gauge.ticks.rfactor2;
            r2 = radius / settings.gauge.ticks.rfactor2;
            color = settings.gauge.outer.color2;
        end
        local tx1 = center.x + r1 * math.cos(phi);
        local ty1 = center.y + r1 * math.sin(phi);
        local tx2 = center.x + r2 * math.cos(phi);
        local ty2 = center.y + r2 * math.sin(phi);
        page:line{pts = {{tx1, ty1}, {tx2, ty2}}, thickness = settings.gauge.ticks.thickness, color = color};
    end

    local tr1 = page:triangle({color = COLOR_THEME_WARNING});
    local tr2 = page:triangle({color = COLOR_THEME_EDIT});

    local line = page:line({pts = {{center.x, center.y}, {center.x, center.y}}, thickness = settings.gauge.line.thickness, color = COLOR_THEME_WARNING});

    local updateCallback = (function(params)
        updateGauge({tr1 = tr1, tr2 = tr2, line = line}, center, radius, params);
    end);

    return updateCallback;
end 

local function updateInfo(s1, s2, remote)
end

local function updateFlags(flags, frameCounter)
end
local function currentString(curr)
    return "Curr: " .. curr;
end
local function rpmString(rpm)
    return "RpM: " .. rpm;
end
local function turnsString(t)
    return "T: " .. t;
end

function widget.clearUI()
    widget.ui.update1 = (function() 
    end);
    widget.ui.update2 = (function() 
    end);
    widget.ui.updateInfo = (function() 
    end);
    widget.ui.updateFlags = (function() 
    end);
    lvgl.clear();
end

function widget.controlPage()
    widget.clearUI();
    local page = lvgl.page({
        title = widget.name .. " " .. versionString(),
        subtitle = "Controls",
        back = askClose,
    });
    local radius = math.min(widget.zone.h / 2, widget.zone.w / 4) * 0.75;
    local center1 = {x = 1 * widget.zone.w / 4, y = widget.zone.h / 2.3};
    local center2 = {x = 3 * widget.zone.w / 4, y = widget.zone.h / 2.3};

    local srv1 = page:label({x = widget.zone.x + 10,  y = 0, text = "Srv: -"});
    local esc1 = page:label({x = widget.zone.x + 100, y = 0, text = "Esc: -"});

    local srv2 = page:label({x = widget.zone.x + widget.zone.w - 100, y = 0, text = "Srv: -"});
    local esc2 = page:label({x = widget.zone.x + widget.zone.w - 190, y = 0, text = "Esc: -"});

    page:hline({x = 0, y = 25, w = widget.zone.w, h = 1});
    page:hline({x = 0, y = widget.zone.h * 0.8, w = widget.zone.w, h = 1});

    page:vline({x = widget.zone.w / 2, y = 0, w = 1, h = widget.zone.h * 0.8 + 25});

    local turns_x_off = 15;
    local turns_y_off = 5;
    local curr1 = page:label({x = widget.zone.x + 10,  y = widget.zone.h * 0.8, text = "Curr: -"});
    local rpm1  = page:label({x = widget.zone.x + 100, y = widget.zone.h * 0.8, text = "RpM: -"});
    local turns1= page:label({x = center1.x - turns_x_off, y = center1.y + settings.gauge.center.radius + turns_y_off, text = "T: 0"});

    local curr2 = page:label({x = widget.zone.x + widget.zone.w - 100, y = widget.zone.h * 0.8, text = "Curr: -"});
    local rpm2 =  page:label({x = widget.zone.x + widget.zone.w - 190, y = widget.zone.h * 0.8, text = "RpM: -"});
    local turns2= page:label({x = center2.x - turns_x_off, y = center2.y + settings.gauge.center.radius + turns_y_off, text = "T: 0"});

    local uf1 = createGauge(page, center1, radius);
    local uf2 = createGauge(page, center2, radius);

    page:hline({x = 0, y = widget.zone.h * 0.8 + 30, w = widget.zone.w, h = 1});
    local bb = page:box({x = widget.zone.x, y = widget.zone.h * 0.8 + 30, w = widget.zone.w, flexFlow = lvgl.FLOW_ROW, flexPad = lvgl.PAD_LARGE});
    bb:button({text = "Reset", y = 10});
    local flabel = bb:label({text = "Counter", y = 20});
    local slabel = bb:label({text = "Set", y = 20});

    widget.ui.update1 = (function(params) 
        slabel:set({text = "steer: " .. params.steer});
        uf1(params);
        curr1:set({text = currentString(params.curr)});
        rpm1:set({text  = rpmString(params.rpm)});
        turns1:set({text  = turnsString(params.turns)});
    end);
    widget.ui.update2 = (function(params) 
        uf2(params);
        curr2:set({text = currentString(params.curr)});
        rpm2:set({text  = rpmString(params.rpm)});
        turns2:set({text  = turnsString(params.turns)});
    end);
    widget.ui.updateFlags = (function(flags, fcounter)
        flabel:set({text = "Telemetry: " .. fcounter});
    end);
end

function widget.globalsPage() 
    widget.clearUI();
    local page = lvgl.page({
        title = widget.name .. " " .. versionString(),
        subtitle = "Global",
        back = askClose,
    });
    local uit = {
        {type = "box", flexFlow = lvgl.FLOW_COLUMN, w = widget.zone.w, children = {}
    }};
    page:build(uit);
end

function widget.widgetPage()
    widget.clearUI();
    local page = lvgl.build({
        { type = "box", flexFlow = lvgl.FLOW_COLUMN, children = {
            { type = "label", text = widget.name, w = widget.zone.x, align = CENTER},
            { type = "label", text = versionString(), w = widget.zone.x, align = CENTER},
        }
        }
    });
end
local function isValidSettingsTable(t) 
    if (t.version ~= nil) then
        if (t.version == settingsVersion) then
            return true;
        end
    end
    return false;
end

local initialized = false;
function widget.update()
    if (not initialized) then
        local st = serialize.load(settingsFilename);
        if (st ~= nil) then
            if (isValidSettingsTable(st)) then
                settings = st;
            else
                resetSettings();
            end
        else
            resetSettings();
        end
        initialized = true;
    end
    if lvgl.isFullScreen() then
        widget.controlPage();
    else
        widget.widgetPage();
    end
    saveSettings();
end
function widget.background()
    crsf.get({
        updateGauge1 = widget.ui.update1,
        updateGauge2 = widget.ui.update2,
        updateInfo   = widget.ui.updateInfo,
        updateFlags  = widget.ui.updateFlags
    });
end
local function fullScreenRefresh()
end
function widget.refresh(event, touchState)
    if lvgl == nil then
        lcd.drawText(widget.zone.x, widget.zone.y, "Lvgl support required", COLOR_THEME_WARNING)
    end
    if (lvgl.isFullScreen()) then
        fullScreenRefresh();
    end
    widget.background();
end

widget.clearUI();

return widget;
