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

local widget, state = ... 

local function encode()
    if (widget.options.ShmEncoding > 0) then
        local sn = 0;
        for adr, buttons in pairs(state.addresses) do
            local e = bit32.lshift(adr, 8); -- [0;3] -> 2bits (in total 10 bits )
            for _, btn in ipairs(buttons) do
                if (state.buttons[btn].value > 0) then
                    e = bit32.bor(e, bit32.lshift(1, (btn - 1)));
                end
            end
            setShmVar(widget.options.ShmVarStart + sn, e);
            sn = sn + 1;
        end
    end
end

return {encode = encode}


