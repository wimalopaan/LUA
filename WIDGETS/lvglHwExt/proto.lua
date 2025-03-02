local switchCb, propCb = ...;

local state = 0;
local length = -1;
local payloadsum = 0;
local msgcontroller = 0;
local bytesTotal = 0;
local payload = {};

local vstate = {};

local function decode(controller, type, payload)
--    print("HwExt:decode:", controller, type, payload);
    if (vstate[controller] == nil) then
        vstate[controller] = {};
        vstate[controller][type] = {};
    end
    local lastPayload = vstate[controller][type];
    if (type == 0x00) then
        for i = 1, #payload do
            if (lastPayload[i] == nil) then
                lastPayload[i] = 0;
            end
            local diff = bit32.bxor(payload[i], lastPayload[i]);
            local m = 1;
            for b = 1, 8 do
                if (bit32.band(diff, m) > 0) then
                    local switch = (i - 1) * 8 + b;
                    local swstate = bit32.band(payload[i], m);
                    switchCb(controller, switch, (swstate > 0));
                end
                m = m * 2;
            end
            lastPayload[i] = payload[i];
        end
    elseif (type == 0x01) then

    end
end

local function parse(byte)
    bytesTotal = bytesTotal + 1;
    if (state == 0) then -- state: undefined
        if (byte == 0xaa) then
            state = 1; 
            msgcontroller = -1;
            type = -1;
            length = -1
            payload = {};
            payloadsum = 0;
        end
    elseif (state == 1) then -- state: got start 
        if (byte <= 0x07) then
            msgcontroller = byte;
            state = 2;
        else 
            state = 0;
        end
    elseif (state == 2) then -- state: got controller
        if (byte <= 0x01) then
            type = byte;
            state = 3;
        else 
            state = 0;
        end
    elseif (state == 3) then -- state: got type
        if (byte < 16) then
            length = byte;
            state = 4;
        else
            state = 0;            
        end
    elseif (state == 4) then -- state: got length
        if (length > 0) then
            payload[#payload + 1] = byte;
            payloadsum = payloadsum + byte;
            payloadsum = bit32.band(payloadsum, 0xff);
            length = length - 1;
            if (length == 0) then
                state = 5;
            end
        else
            state = 5;
        end
    elseif (state == 5) then -- state: got payload
        if (byte == payloadsum) then
            decode(msgcontroller, type, payload);                
        end
        state = 0;
    end
end 

local function process()
    local data = serialRead(64);
    for i = 1, #data do
        parse(string.byte(data, i));
    end
end

return {process = process};