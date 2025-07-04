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

local input = {
   {"A1", SOURCE},
   {"B1", SOURCE},
   {"A2", SOURCE},
   {"B2", SOURCE},
   {"DeadBand", VALUE, 1, 100, 10}, -- absolute value
   {"TimeOut", VALUE, 1, 300, 100} -- milli secs
};
local output = {
   "Pow1",
   "Dir1",
   "Pow2",
   "Dir2",
   "State1",
   "State2"
};
local lastDirs = {
   {0, 0},
   {0, 0}
};
local nextRunTime = 0;
local function saveLastDir(index, value, timeout)
   if (getTime() > nextRunTime) then
      nextRunTime = getTime() + timeout;
      lastDirs[index][1] = lastDirs[index][2];
      lastDirs[index][2] = value;
   end
end
local function run(a1, b1, a2, b2, deadband, to)
   if (a1) and (a2) and (b1) and (b2) then
      local state1 = 0;
      local state2 = 0;
      local timeout = to / 10;
      local SchottelPow1 = math.sqrt(a1 * a1 + b1 * b1);
      local SchottelDir1 = 0;
      local min1 = math.min(math.abs(a1), math.abs(b1));
      local max1 = math.sqrt(min1 * min1 + 1024 * 1024) / 1024;
      local min2 = math.min(math.abs(a2), math.abs(b2));
      local max2 = math.sqrt(min2 * min2 + 1024 * 1024) / 1024;
      if (SchottelPow1 > deadband) then
         SchottelDir1 = math.atan2(b1, a1) * 1024 / math.pi;
         saveLastDir(1, SchottelDir1, timeout);
         state1 = 1;
      else
         SchottelDir1 = lastDirs[1][1];
         state1 = 0;
      end
      local SchottelPow2 = math.sqrt(a2 * a2 + b2 * b2);
      local SchottelDir2 = 0;
      if (SchottelPow2 > deadband) then
         SchottelDir2 = math.atan2(b2, a2) * 1024 / math.pi;
         saveLastDir(2, SchottelDir2, timeout);
         state2 = 1;
      else
         SchottelDir2 = lastDirs[2][1];
         state2 = 0;
      end
      return (SchottelPow1 / max1), SchottelDir1, (SchottelPow2 / max2), SchottelDir2, state1, state2;
   else
      return 0, 0, 0, 0, 0, 0;
   end
end
return {
   input = input,
   run = run,
   output = output
}
