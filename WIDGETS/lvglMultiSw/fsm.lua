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

local widget, uistate = ... 

local state = 0;    
local actual_item = 0;
local full_timeout = 100;
local timeout_counter = 0;
local item_retries = 10;
local item_try = 0;
local items = 8;
local event = 0;

local sendTimeout = 100;
local lastTimeSend = 0;

local useAutoconf = 0;

local function intervall(i)
  sendTimeout = i;
end
local function autoconf(a)
  useAutoconf = a;
end
local function sendEvent(e)
    event = e;
end
local function update()
  if (widget.options.CRSF == 1) then
    if (widget.options.ShmSync > 0) then
      setShmVar(widget.options.ShmSync, 1); -- stop crsfsh.lua from sending, better increment
    end
    if (widget.crsf.send() == true) then
      lastTimeSend = getTime();     
      setShmVar(widget.options.ShmSync, 0); -- better decrement
      --print("crsf OK");
    else
      lastTimeSend = 0; -- reset next cycle
      --print("crsf NOK");
    end   
  end  
  if (widget.options.SPort == 1) then
    if (widget.sport.send() == true) then
      lastTimeSend = getTime();
    else
      --print("sport not send");
    end    
  end
end
local lastBits = 0;
local rptp = 0;
local function readStatusBits()
  if (widget.settings.statusPassthru > 0) then
    local address, bits = widget.crsf.readPassThru();
    while (bits ~= nil) do
      rptp = rptp + 1;
      local changedBits = bit32.bxor(bits, lastBits);
      lastBits = bits;
      local mask = 1;
      for i = 1, 8 do
        local b = bit32.band(bits, mask);
        local changed = bit32.band(changedBits, mask);
        for a = 1, 8 do
          if ((widget.settings.telemActions[a].input == i) and (widget.settings.telemActions[a].address == address)) then
            if (changed > 0) then
              widget.setLSorVs(widget.settings.telemActions[a].switch, (b > 0));
              if (b > 0) then
                uistate.remoteStatus[a] = 1;
              else 
                uistate.remoteStatus[a] = 0;
              end            
            end
          end
        end
        mask = mask * 2;
      end     
      address, bits = widget.crsf.readPassThru();
    end
  end
end
local receivingStatus = false;
local function onTimeout(f)
    local t = getTime();
    if ((t - lastTimeSend) > sendTimeout) then
      widget.sport.invalidate();
      update();
      if (rptp > 0) then
        receivingStatus = true;
        rptp = 0;
      else
        receivingStatus = false;
      end
    end
    readStatusBits();
end
local function getStatusOk()
  return receivingStatus;
end
local function getEvent()
  local e = event;
  event = 0;
  return e;
end
local stateCounter = 0;
local function tick(configCallback) 
  local oldstate = state;
  stateCounter = stateCounter + 1;
  local e = getEvent();
  if (state == 0) then -- normal
    if (widget.settings.activate_color_proto > 0) then
      if (e == 1) or (e == 2) then
        state = 1;
      end    
    end
    onTimeout(update);
  elseif (state == 1) then -- send color
    if (stateCounter > 3) then
      state = 0;
    end
    if (widget.crsf.sendNextColor()) then
      state = 0;
    end
  end

  -- if (state == 0) then
  --   crsf.requestConfigItem(actual_item);
  --   state = 1;
  --   item_try = 0;
  -- elseif (state == 1) then
  --   local item = crsf.readItem(); 
  --   if (item == nil) then
  --     item_try = item_try + 1;
  --     if (item_try >= item_retries) then
  --       state = 0;
  --     end
  --   else
  --     print("Got:", item.item, item.str);
  --     configCallback(item);
  --     state = 2;
  --   end
  -- elseif (state == 2) then
  --   actual_item = actual_item + 1;
  --   if (actual_item >= items) then
  --     state = 3;
  --     timeout_counter = 0;
  --   else
  --     state = 0;
  --   end
  -- elseif (state == 3) then
  --   timeout_counter = timeout_counter + 1;    
  --   if (timeout_counter >= full_timeout) then
  --     actual_item = 0;
  --     state = 0;
  --   end
  -- end
  if (oldstate ~= state) then
    stateCounter = 0;
  end
end
local function sendColors()
  sendEvent(1);
end
return {tick = tick, 
        update = update,
        intervall = intervall,
        autoconf = autoconf,
        sendColors = sendColors,
        sendEvent = sendEvent,
        getStatusOk = getStatusOk 
       };
