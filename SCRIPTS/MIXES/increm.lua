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
   {"Input", SOURCE},
   {"Reset", SOURCE},
   {"Speed", VALUE, 0, 200, 10}
};

local output = { "Incremental" }

local value = 0;

local function run(source, reset, d)
   if (reset > 0) then
      value = 0;
   else
      local i = (source * d) / 10240;

      value = value + i;
      value = math.min(value, 1024);
      value = math.max(value, -1024);
   end
   return value;
end

return {input=input, output=output, run=run}

