local crsf = ... 

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

local function sendEvent(e)
    event = e;
end
local function update()
    crsf.send();
    lastTimeSend = getTime();
end
local function timeout()
    local t = getTime();
    if ((t - lastTimeSend) > sendTimeout) then
        lastTimeSend = t;
        return true;
    end
    return false;
end

local function tick(configCallback) 
  local oldstate = state;
  if (timeout()) then
    crsf.send();
    return;
  end
  if (state == 0) then
    crsf.requestConfigItem(actual_item);
    state = 1;
    item_try = 0;
  elseif (state == 1) then
    local item = crsf.readItem(); 
    if (item == nil) then
      item_try = item_try + 1;
      if (item_try >= item_retries) then
        state = 0;
      end
    else
      print("Got:", item.item, item.str);
      configCallback(item);
      state = 2;
    end
  elseif (state == 2) then
    actual_item = actual_item + 1;
    if (actual_item >= items) then
      state = 3;
      timeout_counter = 0;
    else
      state = 0;
    end
  elseif (state == 3) then
    timeout_counter = timeout_counter + 1;    
    if (timeout_counter >= full_timeout) then
      actual_item = 0;
      state = 0;
    end
  end
  if (oldstate ~= state) then
    print("state:", state, "item:", actual_item);    
  end
end

return {tick = tick, 
        update = update,
       };
