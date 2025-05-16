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

-- FrSky SPort Protocoll:
-- sending a write-command (0x31) to a sensor (physicalID / addID) disables this sensor 
-- to be further querying by the receiver
-- Maybe:
-- sending 0x31 (write) should be done only in disabled state of the sensor
-- this is normally done by sending 0x21 (0x20 activates the sensor) 

local state, widget, dir = ... 

-- todo: 
-- allow up to 8 different addresses
--- send upto 8 packages in sequence?

-- move to util.lua
local function computeState4()
    local s = 0;
    for i = 1, 8 do
        s = s * 4;
        if (state.buttons[8 - i + 1] ~= nil) then
          if (state.buttons[8 - i + 1].value == 1) then
            s = s + 1;
          elseif (state.buttons[8 - i + 1].value == 2) then
            s = s + 2;
          end      
        end
    end
    return s;
end

local function send()
    local value = computeState4();
    local physicalId = widget.options.SPortPhy;
    local primId = 0x31; -- write command without read
    local dataId = (widget.options.SPortApp * 256) + widget.options.Address;
    print("sport send", physicalId, primId, dataId, value);
    return sportTelemetryPush(physicalId, primId, dataId, value);
end

return {send = send};