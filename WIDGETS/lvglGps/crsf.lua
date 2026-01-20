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

local dir = ... 

local appid = 6000;
local appCombTelem = 0x00;
local appDevInfo   = 0x01;
local appExtGPS    = 0x02;

local frameCounter = 0;

local _, rv = getVersion()
if string.sub(rv, -5) == "-simu" then 
  local script = loadScript(dir .. "crsfserial.lua");
  if (script ~= nil) then
    print("load crsf serial")
    local t = script();
    crossfireTelemetryPush = t.crossfireTelemetryPush;
    crossfireTelemetryPop  = t.crossfireTelemetryPop;
  end
end

local function reset()
    frameCounter = 0;
end
local function get(callbacks)
    local command, data = crossfireTelemetryPop();
    local app_id = 0;
    if (command == 0x80 or command == 0x7F) and data ~= nil then
        if #data >= 20 then 
            local dest = data[1]; 
            local adr = data[2];
            app_id = bit32.lshift(data[3], 8) + data[4];
            local ftype = data[5]; -- type: 0x01, 0x02
            if (app_id == appid) then
                frameCounter = frameCounter + 1;
                if (ftype == appExtGPS) then
                    local gps = {};
                    gps.lat = bit32.lshift(data[6], 8) + data[7];
                    gps.lon = bit32.lshift(data[8], 8) + data[9];
                    gps.lat_raw = bit32.lshift(data[6], 8) + data[7];
                    gps.lon_raw = bit32.lshift(data[8], 8) + data[9];
                    gps.sats = bit32.lshift(data[8], 8) + data[9];
                    gps.hdop = bit32.lshift(data[8], 8) + data[9];
                    callbacks.updateGps(gps);
                end
            end
        end
    end
end

return {
    get = get;
    reset = reset;
};