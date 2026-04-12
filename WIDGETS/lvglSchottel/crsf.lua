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
local appCombTelem   = 0x00;
local appDevInfo     = 0x01;
local appSimpleTelem = 0x02;

local frameCounter = 0;

local _, rv = getVersion()
if string.sub(rv, -5) == "-simu" then 
  local c = loadScript(dir .. "crsfserial.lua");
  if (c ~= nil) then
    local t = c();
    crossfireTelemetryPush = t.crossfireTelemetryPush;
    crossfireTelemetryPopCB  = t.crossfireTelemetryPopCB;
  end
end

local function reset()
    frameCounter = 0;
end

local function toSigned8Bit(v)
    if (v >= 128) then
        return v - 256;
    end
    return v;
end

local function decode(command, data, callbacks)
    local app_id = 0;
    if (((command == 0x80) or (command == 0x7F)) and data ~= nil) then
        if #data >= 10 then 
            local dest = data[1]; 
            local src = data[2];
            app_id = bit32.lshift(data[3], 8) + data[4];
            local ftype = data[5]; -- type: 0x00, 0x01, 0x02
            if (app_id == appid) then
                frameCounter = frameCounter + 1;
                if (ftype == appSimpleTelem) then
                    local p1 = {};
                    p1.steer  = bit32.lshift(data[6], 8) + data[7];
                    p1.power  = bit32.lshift(data[8], 8) + data[9];
                    p1.actual = bit32.lshift(data[10], 8) + data[11];
                    p1.curr   = 0;                    
                    p1.rpm    = 0;
                    local p2 = {};
                    p2.steer  = bit32.lshift(data[12], 8) + data[13];                    
                    p2.power  = bit32.lshift(data[14], 8) + data[15];
                    p2.actual = bit32.lshift(data[16], 8) + data[17];                    
                    p2.curr   = 0;
                    p2.rpm    = 0;                    
                    p1.turns  = toSigned8Bit(data[18]); 
                    p2.turns  = toSigned8Bit(data[19]);
                    local flags   = data[20];                        
                    callbacks.updateGauge1(p1);
                    callbacks.updateGauge2(p2);
                    callbacks.updateFlags(flags, frameCounter);
                elseif (ftype == appCombTelem) then
                    local p1 = {};
                    p1.steer  = bit32.lshift(data[6], 8) + data[7];
                    p1.power  = bit32.lshift(data[8], 8) + data[9];
                    p1.actual = bit32.lshift(data[10], 8) + data[11];
                    p1.curr   = bit32.lshift(data[12], 8) + data[13] * 0.01;                    
                    p1.rpm    = bit32.lshift(data[14], 8) + data[15];
                    local p2 = {};
                    p2.steer  = bit32.lshift(data[16], 8) + data[17];                    
                    p2.power  = bit32.lshift(data[18], 8) + data[19];
                    p2.actual = bit32.lshift(data[20], 8) + data[21];                    
                    p2.curr   = bit32.lshift(data[22], 8) + data[23] * 0.01;
                    p2.rpm    = bit32.lshift(data[24], 8) + data[25];                    
                    p1.turns  = toSigned8Bit(data[26]); 
                    p2.turns  = toSigned8Bit(data[27]);
                    local flags   = data[28];                        
                    callbacks.updateGauge1(p1);
                    callbacks.updateGauge2(p2);
                    callbacks.updateFlags(flags, frameCounter);
                elseif (ftype == appDevInfo) then
                    local s1 = {srv = {fw = {}, hw = {}}, esc = {fw = {}, hw = {}}};
                    local s2 = {srv = {fw = {}, hw = {}}, esc = {fw = {}, hw = {}}};
                    s1.srv.fw.maj = data[6];
                    s1.srv.fw.min = data[7];
                    s1.srv.hw.maj = data[8];
                    s1.srv.hw.min = data[9];
                    s2.srv.fw.maj = data[10];
                    s2.srv.fw.min = data[11];
                    s2.srv.hw.maj = data[12];
                    s2.srv.hw.min = data[13];
    
                    s1.esc.fw.maj = data[14];
                    s1.esc.fw.min = data[15];
                    s1.esc.hw.maj = data[16];
                    s1.esc.hw.min = data[17];
                    s2.esc.fw.maj = data[18];
                    s2.esc.fw.min = data[19];
                    s2.esc.hw.maj = data[20];
                    s2.esc.hw.min = data[21];
    
                    local remote = {};
                    remote.sw = data[22];
                    remote.hw = data[23];

                    callbacks.updateInfo(s1, s2, remote);
                end
            end
        end
        return true;
    end
    return false;

        -- local alarm1 = false;
    -- local alarm2 = false;
    -- local alarm3 = false;
    -- if (bit32.band(flags, 0x01) ~= 0x00) then
    --     alarm1 = true;
    -- end
    -- if (bit32.band(flags, 0x02) ~= 0x00) then
    --     alarm2 = true;
    -- end
    -- if (bit32.band(flags, 0x04) ~= 0x00) then
    --     alarm3 = true;
    --     playTone(440, 500, 100);
    -- end

end

local function getSimu(callbacks)
    crossfireTelemetryPopCB(function(command, data) decode(command, data, callbacks) end);
end

local function get(callbacks)
    local command, data = crossfireTelemetryPop();
    while(decode(command, data, callbacks)) do
        command, data = crossfireTelemetryPop();
    end
end

local function getLast(callbacks)
    local command, data = crossfireTelemetryPopLast();
    decode(command, data, callbacks);
end

return {
    get = (function() 
        if (crossfireTelemetryPopCB) then 
            return getSimu; 
        else 
            if (crossfireTelemetryPopLast) then
                return getLast; 
        else
                return get; 
            end
        end; 
    end)(),
    reset = reset;
};