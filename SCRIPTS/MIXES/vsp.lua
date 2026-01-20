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

local function clamp(value)
  return math.max(math.min(value, 1024), -1024);
end

local input = {
   {"Inp1", SOURCE},
   {"Inp2", SOURCE},
   {"W 1->2", VALUE, -100, 100, 0},
   {"W 2->1", VALUE, -100, 100, 0},
-- {"VSP", VALUE, 1, 2, 1}
};
local output = {
 "S1",
 "S2"
};
local function run(a, b, wa, wb)
   local ab = math.abs(a);
   local bb = math.abs(b);
   local as = a + ((bb * wb) / 100);
   local asb = math.abs(as);
   local bs = b + ((ab * wa) / 100);
   local bsb = math.abs(bs);
   local rmax = 0;
   local Amax = 1024;
   local Bmax = 1024;
   if (as >= 0) then
      if (bs >= 0) then
  if (asb >= bsb) then
     if (wb > 0) then
        Amax = 1024 + (1024 * wb) / 100;
     end
     Bmax = (bsb * Amax) / asb;
  else
     if (wa > 0) then
        Bmax = 1024 + (1024 * wa) / 100;
     end
     Amax = (asb * Bmax) / bsb;
  end
      else
  if (asb >= bsb) then
     if (wb > 0) then
        Amax = 1024 + (1024 * wb) / 100;
     end
     Bmax = (bsb * Amax) / asb;
  else
     if (wa < 0) then
        Bmax = 1024 + (-1024 * wa) / 100;
     end
     Amax = (asb * Bmax) / bsb;
  end
      end
   else
      if (bs >= 0) then
  if (asb >= bsb) then
     if (wb < 0) then
        Amax = 1024 + (-1024 * wb) / 100;
     end
     Bmax = (bsb * Amax) / asb;
  else
     if (wa > 0) then
        Bmax = 1024 + (1024 * wa) / 100;
     end
     Amax = (asb * Bmax) / bsb;
  end
      else
  if (asb >= bsb) then
     if (wb < 0) then
        Amax = 1024 + (-1024 * wb) / 100;
     end
     Bmax = (bsb * Amax) / asb;
  else
     if (wa < 0) then
        Bmax = 1024 + (-1024 * wa) / 100;
     end
     Amax = (asb * Bmax) / bsb;
  end
      end
   end
   rmax = math.sqrt(Amax * Amax + Bmax * Bmax);
   local Vsp1 = (as * 1024) / rmax;
   local Vsp2 = (bs * 1024) / rmax;
   return Vsp1, Vsp2;
end
return {
 input = input,
 run = run,
 output = output
};
