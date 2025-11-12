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
local ibusEncodedValue = -1024;
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
    ibusEncodedValue = (v5 + (2048 / 64) / 2) - 1024 + 0.5;
--    print("encode", c, v5, ibusEncodedValue, state, address, switch, on);
end

local rrCounter = 0;
local vCounter = 1;
local function onChange(values, callback)
--    print("onchange", vCounter);
    local i = vCounter;
    local v = values[i];
    if (v == nil) then return false; end;
    vCounter = vCounter + 1;
    if (vCounter > #values) then
        vCounter = 1;
        rrCounter = rrCounter + 1;
        if (rrCounter == 8) then
            rrCounter = 0;
        end
    end
    local diff = bit32.band(bit32.bxor(v, lastInputs[i]), 0x3ff); -- in total 10 bits
    local address  = bit32.rshift(v, 8);
    local switches = bit32.band(v, 0xff);
    local adrMask  = bit32.band(v, 0x300);
    if (diff ~= 0) then
        local mask = 1;
        for sw = 1, 8 do
            if (bit32.band(diff, mask) > 0) then
--                print("changed", i, address, switches, sw);
                local onMask = bit32.band(switches, mask);
                callback(address, sw, (onMask > 0)); 
                lastInputs[i] = bit32.bor(adrMask, bit32.band(0xff, lastInputs[i], bit32.bnot(mask)), onMask);
                return true; -- send one at a time
            end
            mask = bit32.lshift(mask, 1);
        end
        lastInputs[i] = v;
    else
        local mask = bit32.lshift(1, rrCounter);
--        print("rr", #values, i, vCounter, rrCounter, address, switches, mask);
        local onMask = bit32.band(switches, mask);
        local sw = rrCounter + 1;
        callback(address, sw, (onMask > 0)); 
        lastInputs[i] = v;
        return true;
    end
    return false;
end

local function onTimeout(callback)
    local t = getTime();
    if ((t - lastTime) > timeout) then
        if (callback()) then
            lastTime = t;
        end
    end
end

local function run(n1, n2, n3, n4)
    onTimeout((function() 
        local vt = {};
        for _, nv in ipairs({n1, n2, n3, n4}) do
            if (nv > 0) then
                vt[#vt + 1] = getShmVar(nv);
            end
        end
        return onChange(vt, encode);
    end));
    return ibusEncodedValue;
end

return {input = inputs, run = run, output = output}; 