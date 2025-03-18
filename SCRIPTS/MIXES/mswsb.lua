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
-- sbus-range: [172,1812], sbus-delta: 1640
-- scaling: 1024 / 1620 (to reach [172, 1196], delta: 1024)
-- on receiver side: rshift of 4 

local function encode(address, switch, on)
    local state = 0;
    if (on) then 
        state = 1;
    end
    local c = bit32.bor(bit32.lshift(address, 4), bit32.lshift((switch - 1), 1), bit32.band(state, 0x01));
    local v5 = bit32.lshift(c, 5);
    sbusEncodedValue = ((v5 + (2048 / 64) / 2) * 1024) / 1640 - 1024 + 0.5;
    print("encode", c, v5, sbusEncodedValue, state);
end

local function checkChanges(values)
    for i, v in ipairs(values) do
        local diff = bit32.band(bit32.bxor(v, lastInputs[i]), 0xff);
        if (diff ~= 0) then
            local address  = bit32.rshift(v, 8);
            local switches = bit32.band(v, 0xff);
            local mask = 1;
            for b = 1, 8 do
                if (bit32.band(diff, mask) > 0) then
                    print("changed", i, address, switches, b);
                    local onMask = bit32.band(switches, mask);
                    encode(address, b, (onMask > 0)); 
                    lastInputs[i] = bit32.bor(bit32.band(lastInputs[i], bit32.bnot(mask)), onMask);
                    return true;
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

