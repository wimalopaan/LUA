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

local uilib, env = ... 

local crsf      = loadScript(env.dir .. "crsf.lua", "btd")(uilib, env);
local sport     = loadScript(env.dir .. "sport.lua", "btd")(uilib, env);

local sendTimeout = 100;
local lastTimeSend = 0;
local function intervall(i)
  sendTimeout = i;
end
local function update()
--  print("update")
  if (uilib.global.settings.rflink == uilib.global.RF.CRSF) then
    if (crsf.send() == true) then
      lastTimeSend = getTime();     
    end    
  elseif (uilib.global.settings.rflink == uilib.global.RF.SPORT) then
    if (sport.send() == true) then
      lastTimeSend = getTime();
    end    
  end
end
local function onTimeout(f)
    local t = getTime();
    if ((t - lastTimeSend) > sendTimeout) then
      update();
    end
end
local function tick(configCallback) 
  onTimeout(update);
end
return {tick = tick, 
        update = update,
        intervall = intervall,
       };
