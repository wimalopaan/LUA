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

local state, widget, dir, util = ... 

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

local lastState = {buttons = {}};

local function checkState(callback)
  for i = 1, (widget.settings.rows * widget.settings.columns) do
    if (state.buttons[i] ~= nil) then
      if (lastState.buttons[i] == nil) then
        lastState.buttons[i] = {value = 0};
        return callback(i);
      end
      if (state.buttons[i].value ~= lastState.buttons[i].value) then
        lastState.buttons[i].value = state.buttons[i].value;
        return callback(i);
      end
    end      
  end
end

local function send()
  if (widget.options.SPortProto <= 1) then
    local value = computeState4();
    local physicalId = widget.options.SPortPhy;
    local primId = 0x31; -- write command without read
    local dataId = (widget.options.SPortApp * 256) + widget.options.Address;
    print("sport send WM", physicalId, primId, dataId, value);
    return sportTelemetryPush(physicalId, primId, dataId, value);    
  elseif (widget.options.SPortProto == 2) then -- protocol version 1.5
    return checkState((function(i) 
      local physicalId = 0x1b;
      local primId = 0x10; -- data
      local dataId = 0xac00;
      local type = widget.settings.buttons[i].sport.type; 
      local option = widget.settings.buttons[i].sport.options;
      local switch = widget.settings.buttons[i].output + (widget.settings.buttons[i].address * 8);
      local pwm = 0x00;
      if (state.buttons[i].value > 0) then
        pwm = widget.settings.buttons[i].sport.pwm_on;
      end
      local value = bit32.lshift(type, 24) + bit32.lshift(option, 16) + bit32.lshift(switch, 8) + pwm; 
      print("sport send ACW", physicalId, primId, dataId, value);
      return sportTelemetryPush(physicalId, primId, dataId, value);    
    end));
  elseif (widget.options.SPortProto == 3) then -- protocol version 1.4
    return checkState((function(i) 
      local physicalId = 0x1b;
      local primId = 0x10; -- data
      local dataId = 0xfa07;
      local type = widget.settings.buttons[i].sport.type; 
      local option = widget.settings.buttons[i].sport.options;
      local switch = widget.settings.buttons[i].output + (widget.settings.buttons[i].address * 8);
      local pwm = 0x00;
      if (state.buttons[i].value > 0) then
        pwm = widget.settings.buttons[i].sport.pwm_on;
      end
      local value = bit32.lshift(type, 24) + bit32.lshift(option, 16) + bit32.lshift(switch, 8) + pwm; 
      print("sport send ACW", physicalId, primId, dataId, value);
      return sportTelemetryPush(physicalId, primId, dataId, value);    
    end));
  end
  return true;
end

return {send = send};