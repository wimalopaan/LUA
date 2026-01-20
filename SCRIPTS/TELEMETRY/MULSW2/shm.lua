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

local uilib, env = ... 

local function encode()
    if (widget.options.ShmEncoding > 0) then
        local e = bit32.lshift(widget.options.Address, 8);
        for i, b in ipairs(state.buttons) do
            if (b.value > 0) then
                e = bit32.bor(e, bit32.lshift(1, (i - 1)));
            end
        end
        setShmVar(widget.options.ShmVar, e);
    end 
end

return {encode = encode}


