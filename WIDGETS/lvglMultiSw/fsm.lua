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

local crsf, sport, widget, util = ... 

local state = 0;    
local actual_item = 0;
local full_timeout = 100;
local timeout_counter = 0;
local item_retries = 10;
local item_try = 0;
local items = 8;
local event = 0;

local EVT_UPDATE = 1;

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
    if (crsf.send() == true) then
      lastTimeSend = getTime();     
      setShmVar(widget.options.ShmSync, 0); -- better decrement
      print("crsf OK");
    else
      lastTimeSend = 0; -- reset next cycle
      print("crsf NOK");
    end   
  end  
  if (widget.options.SPort == 1) then
    if (sport.send() == true) then
      lastTimeSend = getTime();
    else
      print("sport not send");
    end    
  end
end
local function onTimeout(f)
    local t = getTime();
    if ((t - lastTimeSend) > sendTimeout) then
      sport.invalidate();
      update();
    end
end

local function tick(configCallback) 
--  local oldstate = state;
  onTimeout(update);

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
  -- if (oldstate ~= state) then
  --   print("state:", state, "item:", actual_item);    
  -- end
end

return {tick = tick, 
        update = update,
        intervall = intervall,
        autoconf = autoconf,
       };
