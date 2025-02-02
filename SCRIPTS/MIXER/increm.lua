--
-- WM OTXE - OpenTX Extensions 
-- Copyright (C) 2020 Wilhelm Meier <wilhelm.wm.meier@googlemail.com>
--
-- This work is licensed under the Creative Commons Attribution-NonCommercial-NoDerivatives 4.0 International License. 
-- To view a copy of this license, visit http://creativecommons.org/licenses/by-nc-nd/4.0/ 
-- or send a letter to Creative Commons, PO Box 1866, Mountain View, CA 94042, USA.

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

