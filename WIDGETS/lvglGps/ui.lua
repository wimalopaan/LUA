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
-- save positions / edit names

local zone, options, name, dir = ...
local widget = {}
widget.options = options;
widget.zone = zone;
widget.name = name;
widget.ui = nil;

local crsf = loadScript(dir .. "crsf.lua", "btd")(dir);
local serialize = loadScript(dir .. "tableser.lua", "btd")(dir);

local gps_radio = {};
local gps_model = {
    sats = 0,
    fix = 0,
    lon = 0,
    lat = 0,
    speed = 0,
    pitch = 0,
    roll = 0,
    yaw = 0,
    hdg = 0,
    raw = {
        lon = 0,
        lat = 0,
    }
};
local nav = {
    distance = 0;
    course = 0;
    raw = {
        distance = 0;
        course = 0;
    }
};
local resolution = {
    selected = 1;
    titles = {"Normal Resolution", "Full Resolution"};
};
local positionStore = {
    titles = {"Radio", "Pos 1", "Pos 2", "Pos 3"};
    selected = 1;
    target = 1;
    positions = {
        {lon = 0, lat = 0},
        {lon = 0, lat = 0},
        {lon = 0, lat = 0},
        {lon = 0, lat = 0},
    };
};
local settingsFilename = dir .. model.getInfo().name .. ".lua";
local function saveSettings() 
    if (settingsFilename ~= nil) then
        serialize.save(positionStore, settingsFilename);        
    end
end

local degToRad = (math.pi / 180);

local function distanceCourse(lat1_deg, lon1_deg, lat2_deg, lon2_deg)
    if (lat1_deg == nil) then
        return 0, 0;
    end
    local R = 6371000; -- earth radius in meter 
    local lat1 = lat1_deg * degToRad;
    local lat2 = lat2_deg * degToRad;
    local lon1 = lon1_deg * degToRad;
    local lon2 = lon2_deg * degToRad;
    local dlat = lat2 - lat1;
    local dlon = lon2 - lon1;
    local sin_dlat2 = math.sin(dlat / 2);
    local sin_dlon2 = math.sin(dlon / 2);
    local cos_lat1 = math.cos(lat1);
    local cos_lat2 = math.cos(lat2);
    local a = sin_dlat2 * sin_dlat2 + cos_lat1 * cos_lat2 * sin_dlon2 * sin_dlon2;
    local c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    local dist = R * c;
    local x = cos_lat1 * math.sin(lat2) - math.sin(lat1) * cos_lat2 * math.cos(dlon);
    local y = math.sin(dlon) * cos_lat2;
    local course = math.atan2(y, x);
    return dist, course;
end

local function distanceCourseNear(factor, lat1_deg, lon1_deg, lat2_deg, lon2_deg)
    if (lat1_deg == nil) then
        return 0, 0;
    end
    local R = 6371000;
    local scale = 1.0 / factor;

    local lat_mean_rad = (lat1_deg + lat1_deg) * degToRad * scale / 2;
    local cos_lat_mean = math.cos(lat_mean_rad);

    local dlat = (lat2_deg - lat1_deg);
    local dlon = math.floor((lon2_deg - lon1_deg) * cos_lat_mean);
    local d_deg = math.sqrt(dlat * dlat + dlon * dlon); 

    local dist = (d_deg * degToRad * R) / factor;
    local course = math.atan2(dlon, dlat);
    return dist, course;
end

function widget.controlPage()
    lvgl.clear();
    local page = lvgl.page({
        title = "GPS",
--        subtitle = "Model steering (red) to radio (blue)"
    });
end

local function drawCompass(page, cx, cy, r_circle)
    local r_model = r_circle * 2 / 3;;
    local r_course = r_circle * 4 / 5;;

    page:circle({x = cx, y = cy, radius = r_circle, thickness = 3 });
    page:circle({x = cx, y = cy, radius = 8, filled = true, color = BLACK });

    local r1 = r_circle * 0.9;
    local r2 = r_circle * 1.1;

    for i = 0, 11 do
        local phi = (2 * math.pi * i) / 12;
        local tx1 = cx + r1 * math.cos(phi);
        local ty1 = cy + r1 * math.sin(phi);
        local tx2 = cx + r2 * math.cos(phi);
        local ty2 = cy + r2 * math.sin(phi);
        page:line{pts = {{tx1, ty1}, {tx2, ty2}}, thickness = 1};
    end

    local x_offset = 6;
    local y_offset = 10;
    page:label({x = cx - x_offset, y = cy - r2 - 2 * y_offset, text = "N"});
    page:label({x = cx - x_offset, y = cy + r2, text = "S"});
    page:label({x = cx + r2 + x_offset, y = cy - y_offset, text = "E"});
    page:label({x = cx - r2 - 3 * x_offset, y = cy - y_offset, text = "W"});

    page:line({thickness = 1, color = CYAN, pts = (function()
                local v = getValue(widget.options.Help) * math.pi / 1024;
                local x = r_circle * math.cos(v) + cx;
                local y = r_circle * math.sin(v) + cy;
                return { { cx, cy }, { x, y } };
    end)});
    page:line({thickness = 4, color = RED, pts = (function() 
                    local yaw = gps_model.yaw + widget.options.Yaw_Offset * math.pi / 2 + widget.options.Mag_Offset * math.pi / 180;
                    local x = r_model * math.cos(yaw) + cx;
                    local y = r_model * math.sin(yaw) + cy;
                    return {{cx, cy}, {x, y}};
    end)});
    page:line({thickness = 2, color = BLUE, pts = (function() 
        -- select normal or full reso
                    local course = nav.raw.course - (math.pi / 2) -- reverse the direction (model -> pilot) (-PI) and correct for naval to math angle (+PI/2)
                    if (nav.raw.course < 0) then
                        course = nav.raw.course + math.pi;
                    end
                    local x = r_course * math.cos(course) + cx;
                    local y = r_course * math.sin(course) + cy;
                    return {{cx, cy}, {x, y}};
    end)});
end
local function drawPitchIndicator(page, x, y)
    local max_pitch = widget.options.MaxPitch * degToRad;
    local lineLength = 30;
    page:label({text = "Pitch", x = x, y = y - 32, font = SMLSIZE, align = CENTER});
    local offset = 3;
    page:line({thickness = 1, color = GREEN, pts = {{x - lineLength, y + offset}, {x + lineLength, y + offset}}});
    page:line({thickness = 3, color = RED, pts = (function()
        local pitch = gps_model.pitch;
        if (widget.options.InvPitch > 0) then
            pitch = pitch * -1;
        end
        if (pitch > max_pitch) then
            pitch = max_pitch;
        elseif (pitch < -max_pitch) then
            pitch = -max_pitch;
        end
        local dx = lineLength * math.cos(pitch); 
        local dy = lineLength * math.sin(pitch); 
        return {{x - dx, y + dy}, {x + dx, y - dy}};
    end)});
end
local function drawRollIndicator(page, x, y)
    local r_roll = 50;
    local max_roll = widget.options.MaxRoll * degToRad;
    page:label({text = "Roll", x = x, y = y - r_roll - 16, font = SMLSIZE, align = CENTER});
    page:circle({x = x, y = y, radius = 4, filled = true, color = GREEN });
    page:arc({x = x, y = y, radius = r_roll, color = GREEN, startAngle = (270 - max_roll / degToRad), endAngle = (270 + max_roll / degToRad)});
    page:line({thickness = 1, color = RED, pts = (function()
        local roll = gps_model.roll;
        if (widget.options.InvRoll > 0) then
            roll = roll * -1;
        end
        if (roll > max_roll) then
            roll = max_roll;
        elseif (roll < -max_roll) then
            roll = -max_roll;
        end
        roll = roll + math.pi / 2;
        local dx = r_roll * math.cos(roll); 
        local dy = r_roll * math.sin(roll); 
        return {{x, y}, {x + dx, y - dy}};
    end)});
end
local function drawRadio(page, x, y)
    local dy = 30;
    page:label({x = x, y = y, text = "Radio", font = BOLD, color = BLUE});
    y = y + dy;
    page:label({x = x, y = y, text = (function() return "Lat: " .. gps_radio.lat; end)});
    y = y + dy;
    page:label({x = x, y = y, text = (function() return "Lon: " .. gps_radio.lon; end)});            
    if (gps_radio.latraw ~= nil) then
        y = y + dy;
        page:label({x = x, y = y, text = (function() return "Lat raw: " .. gps_radio.latraw; end)});
        y = y + dy;
        page:label({x = x, y = y, text = (function() return "Lon raw: " .. gps_radio.lonraw; end)});        
    end
    y = y + dy;
    page:label({x = x, y = y, text = (function() return "Sats: " .. gps_radio.numsat; end)});
    y = y + dy;
    page:label({x = x, y = y, text = (function() return "Dist: " .. nav.distance; end)});
    y = y + dy;
    page:label({x = x, y = y, text = (function() return "Dist/R: " .. nav.raw.distance; end)});
    y = y + dy;
    return y;
end

local function drawModel(page, x, y)
    local dy = 30;
    page:label({x = x, y = y, text = "Model", font = BOLD, color = RED});
    y = y + dy;
    page:label({x = x, y = y, text = (function() return "Lat: " .. gps_model.lat; end)});
    y = y + dy;
    page:label({x = x, y = y, text = (function() return "Lon: " .. gps_model.lon; end)});
    y = y + dy;
    page:label({x = x, y = y, text = (function() return "Lat raw: " .. gps_model.raw.lat; end)});
    y = y + dy;
    page:label({x = x, y = y, text = (function() return "Lon raw: " .. gps_model.raw.lon; end)});
    y = y + dy;
    page:label({x = x, y = y, text = (function() return "Sats: " .. gps_model.sats; end)});
    y = y + dy;
    page:label({x = x, y = y, text = (function() return "Hdg: " .. gps_model.hdg; end)});
    y = y + dy;
    page:label({x = x, y = y, text = (function() return "Pitch: " .. gps_model.pitch; end)});
    y = y + dy;
    page:label({x = x, y = y, text = (function() return "Roll: " .. gps_model.roll; end)});
    y = y + dy;
    page:label({x = x, y = y, text = (function() return "Yaw: " .. gps_model.yaw; end)});
    y = y + dy;
    page:label({x = x, y = y, text = (function() return "Speed: " .. gps_model.speed; end)});
    y = y + dy;
    return y;
end

local function drawButtons(page, y)
    local b = page:box({x = 0, y = y, w = LCD_W, flexFlow = lvgl.FLOW_COLUMN});
    b:hline({w = LCD_W, h = 2});
    local buttonBox = b:box({flexFlow = lvgl.FLOW_ROW});
    buttonBox:button({text = "Save model pos", active = (function() return positionStore.selected ~= 1; end), 
                                            press = (function() 
                                                positionStore.positions[positionStore.selected] = {lon = gps_model.lon, lat = gps_model.lat}; 
                                                saveSettings();
                                            end)});
    buttonBox:choice({title = "Select Position", values = positionStore.titles, get = (function() return positionStore.selected ; end), set = (function(v) positionStore.selected = v; if (v == 1) then positionStore.target = 1; end end)});
    buttonBox:button({text = "Recall pos", active = (function() return positionStore.selected ~= 1; end), press = (function() positionStore.target = positionStore.selected; end)});

    buttonBox:choice({title = "Select Resolution", values = resolution.titles, 
                                    get = (function() return resolution.selected ; end), 
                                    set = (function(v) resolution.selected = v; end)});
end

local function drawInfo(page, x, y)
    page:label({x = x, y = y, text = (function() return "Target: " .. positionStore.titles[positionStore.target]; end), font = SMLSIZE});
end

local function drawResolution(page, x, y)
    page:label({x = x, y = y, text = (function() return resolution.titles[resolution.selected]; end), font = SMLSIZE});
end

local function drawTarget(page, x, y)
    local dy = 30;
    page:label({x = x, y = y, text = "Target", font = BOLD, color = BLUE});
    y = y + dy;
    page:label({x = x, y = y, text = (function() 
        if (positionStore.target == 1) then
            return "Lat: " .. gps_radio.lat; 
        else
            return "Lat: " .. positionStore.positions[positionStore.target].lat;                 
        end
    end)});
    y = y + dy;
    page:label({x = x, y = y, text = (function() 
        if (positionStore.target == 1) then
            return "Lon: " .. gps_radio.lon; 
        else
            return "Lon: " .. positionStore.positions[positionStore.target].lon;                 
        end
    end)});            
    y = y + dy;
    return y;
end

function widget.compassPage()
    lvgl.clear();
    local page = lvgl.page({
        title = "GPS",
        subtitle = "Model steering (red) to target (blue)"
    });
    local w = LCD_W;
    local h = LCD_H - 60;
    local cx = w / 2;
    local cy = h / 2 + 30;
    local r_circle = h / 2;
    drawCompass(page, cx, cy, r_circle);
    drawInfo(page, cx - 30, cy - r_circle / 2);
    drawResolution(page, cx - 50, cy + r_circle / 2);

    local x_roll = cx + r_circle + w / 20;
    local y_roll = cy - r_circle / 2;
    drawRollIndicator(page, x_roll, y_roll);

    local x_pitch = cx + r_circle + w / 20;
    local y_pitch = cy + 2 * r_circle / 3;
    drawPitchIndicator(page, x_pitch, y_pitch);

    local x_text = 5;
    local y_text = 20;
    local y_next = drawTarget(page, x_text, y_text);

    local x_text = 5;
    local y_text = y_next;
    local y_bottom1 = drawRadio(page, x_text, y_text);

    local x_text = LCD_W - 50;
    local y_text = 20;
    local y_bottom2 = drawModel(page, x_text, y_text);

    local y_buttons = y_bottom1;
    if (y_bottom2 > y_buttons) then
        y_buttons = y_bottom2;
    end
    drawButtons(page, y_buttons + 20);
end
function widget.widgetPage()
    lvgl.clear();
    local b = lvgl.box({w = widget.zone.w, h = widget.zone.h});
    b:label({text = widget.name, w = widget.zone.w, align = CENTER});
    local cx = widget.zone.x + widget.zone.w / 2;
    local cy = widget.zone.y + widget.zone.h / 2 + 8;
    local r = widget.zone.h * 0.3;
    drawCompass(b, cx, cy, r);
end

local initialized = false;
function widget.update()
    if (not initialized) then
        local st = serialize.load(settingsFilename);
        if (st ~= nil) then
            positionStore = st;
        end
    end
    if lvgl.isFullScreen() then
        widget.compassPage();
    else
        widget.widgetPage();
    end
end
function widget.background()
    gps_radio = getTxGPS();
    local gps_t_m = getValue("GPS");
    if (type(gps_t_m) == "table") then
        gps_model.lat = gps_t_m.lat; 
        gps_model.lon = gps_t_m.lon; 
    end
    gps_model.raw.lat = getValue("LatR"); 
    gps_model.raw.lon = getValue("LonR");
    gps_model.sats    = getValue("Sats");
    gps_model.speed   = getValue("GSpd");
    gps_model.pitch   = getValue("Ptch");
    gps_model.roll    = getValue("Roll"); 
    gps_model.yaw     = getValue("Yaw"); 
    gps_model.hdg     = getValue("Hdg"); 

    nav.distance, nav.course = distanceCourse(gps_radio.lat, gps_radio.lon, gps_model.lat, gps_model.lon);
    nav.raw.distance, nav.raw.course = distanceCourseNear(10000000, gps_radio.latraw, gps_radio.lonraw, gps_model.raw.lat, gps_model.raw.lon);
end
function widget.refresh(event, touchState)
    if lvgl == nil then
        lcd.drawText(widget.zone.x, widget.zone.y, "Lvgl support required", COLOR_THEME_WARNING)
    end
    widget.background();
end

return widget;
