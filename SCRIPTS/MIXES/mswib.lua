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

local inputs = {
	{"ShmV1", VALUE, 0, 16, 0},
	{"ShmV2", VALUE, 0, 16, 0},
	{"ShmV3", VALUE, 0, 16, 0},
	{"ShmV4", VALUE, 0, 16, 0},
}
local output = {
    "Enc",
};
local lastTime = getTime();
local timeout = 10; -- 100ms
local sbusEncodedValue = -1024;
local lastInputs = {0, 0, 0, 0};

-- Encoding:
-- 2 bits: address
-- 3 bits: output
-- 1 bit:  state
-- in total 6 bits (64 values)
-- the value-range [-1024, 1024]: 11-bits
-- we need a left-shift of 5 to use full-range
-- step size: 2048/64
-- offset (half-step): (step size) / 2
-- ibus-range: [988,2011], ibus-delta: 1024
-- on receiver side: rshift of 4 

local function encode(address, switch, on)
    local state = 0;
    if (on) then 
        state = 1;
    end
    local c = bit32.bor(bit32.lshift(address, 4), bit32.lshift((switch - 1), 1), bit32.band(state, 0x01));
    local v5 = bit32.lshift(c, 5);
    sbusEncodedValue = (v5 + (2048 / 64) / 2) - 1024 + 0.5;
    print("encode", c, v5, sbusEncodedValue, state, address, switch, on);
end

local function checkChanges(values)
    for i, v in ipairs(values) do
        local diff = bit32.band(bit32.bxor(v, lastInputs[i]), 0x3ff); -- in total 10 bits
        if (diff ~= 0) then
            local address  = bit32.rshift(v, 8);
            local switches = bit32.band(v, 0xff);
            local mask = 1;
            for sw = 1, 8 do
                if (bit32.band(diff, mask) > 0) then
                    print("changed", i, address, switches, sw);
                    local onMask = bit32.band(switches, mask);
                    encode(address, sw, (onMask > 0)); 
                    lastInputs[i] = bit32.bor(bit32.band(lastInputs[i], bit32.bnot(mask)), onMask);
                    return true; -- send one at a time
                end
                mask = bit32.lshift(mask, 1);
            end
        end
    end
    return false;
end

local function setNext()
end

local function run(n1, n2, n3, n4)
    local t = getTime();
    if ((t - lastTime) > timeout) then
        lastTime = t;
        local v1 = getShmVar(n1);
        local v2 = getShmVar(n2);
        local v3 = getShmVar(n3);
        local v4 = getShmVar(n4);
        if (not checkChanges({v1, v2, v3, v4})) then 
            setNext();
        end
    end
    return sbusEncodedValue;
end

return {input = inputs, run = run, output = output}; 

