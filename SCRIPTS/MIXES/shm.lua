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
    {"Start", VALUE, 1, 11, 1}
};
local output = {
    "S1",
    "S2",
    "S3",
    "S4",
    "S5",
    "S6",
};
local function run(start)
    local s1 = getShmVar(start);
    local s2 = getShmVar(start + 1);
    local s3 = getShmVar(start + 2);
    local s4 = getShmVar(start + 3);
    local s5 = getShmVar(start + 4);
    local s6 = getShmVar(start + 5);
    return s1, s2, s3, s4, s5, s6;
end
return {
    input = input,
    run = run,
    output = output
};
