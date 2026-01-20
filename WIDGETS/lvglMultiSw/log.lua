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

local widget, params = ... 

local logging = {}

logging.filename = widget.dir .. params.file;

function logging.log(fmt, ...)
    if (params.enabled) then
        local file = io.open(logging.filename, "a");

        local s = string.format("%d\t" .. fmt .. '\n', getTime(), ...);
        io.write(file, s);
        -- io.write(file, getTime(), "ms\t");
        -- for k, s in pairs({...}) do
        --     io.write(file, s, '\t');        
        -- end
--        io.write(file, '\n');        
        io.close(file)       
    end
    if (params.console) then
        print(string.format(fmt, ...));
    end
end

return logging;