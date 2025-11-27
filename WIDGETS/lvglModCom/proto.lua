local zone, options, dir = ...

local proto = {};

local State = {
    Undefined = 0;
    GotStart = 1;
    GotLength = 2;
    CalibStatus = 3;
    CalibSize = 4;
    CalibValueMaxLow = 5;
    CalibValueMaxHigh = 6;
    CalibValueMinLow = 7;
    CalibValueMinHigh = 8;
    ValueActualLow = 9;
    ValueActualHigh = 10;
    Switches = 11;
    Checksum = 12;
};
local Type = {
    CalibData = 0x01;
};
local calibdata = {
    packages = 0;
    mins = {};
    maxs = {};
    values = {};
    switches = 0;
    status = 0;
};

local state = State.Undefined;
local bytesTotal = 0;
local packages = 0;
local csum = 0;
local paylength = 0;
local calibsize = 0;
local calibvalue = 0;
local calibmins = {};
local calibmaxs = {};
local actualvalues = {};
local switches = 0;
local status = 0;

local ccount = 0;
local function parse(b)
    bytesTotal = bytesTotal + 1;
    if (state == State.Undefined) then
        if (b == 0xaa) then 
            state = State.GotStart;
        end
    elseif (state == State.GotStart) then
        paylength = b;
        state = State.GotLength;
    elseif (state == State.GotLength) then
        csum = b;
        if (b == Type.CalibData) then
            state = State.CalibStatus;
        else
            state = State.Undefined;
        end
    elseif (state == State.CalibStatus) then
        csum = csum + b;
        status = b;
        state = State.CalibSize;
    elseif (state == State.CalibSize) then
        csum = csum + b;
        calibsize = b;
        if (calibsize <= 16) then
            state = State.CalibValueMaxLow;
            calibvalue = 0;
            calibmins = {};
            calibmaxs = {};
            actualvalues = {};
            ccount = calibsize;
        else
            state = State.Undefined;
        end
    elseif (state == State.CalibValueMaxLow) then
        csum = csum + b;
        calibvalue = b;
        state = State.CalibValueMaxHigh;
    elseif (state == State.CalibValueMaxHigh) then
        csum = csum + b;
        calibvalue = bit32.lshift(b, 8) + calibvalue;
        calibmaxs[#calibmaxs+1] = calibvalue;
        calibvalue = 0;
        state = State.CalibValueMinLow;
    elseif (state == State.CalibValueMinLow) then
        csum = csum + b;
        calibvalue = b;
        state = State.CalibValueMinHigh;
    elseif (state == State.CalibValueMinHigh) then
        csum = csum + b;
        calibvalue = bit32.lshift(b, 8) + calibvalue;
        calibmins[#calibmins+1] = calibvalue;
        calibvalue = 0;
        ccount = ccount - 1;
        if (ccount == 0) then
            state = State.ValueActualLow;
            ccount = calibsize;
        else
            state = State.CalibValueMaxLow;
        end
    elseif (state == State.ValueActualLow) then
        csum = csum + b;
        calibvalue = b;
        state = State.ValueActualHigh;
    elseif (state == State.ValueActualHigh) then
        csum = csum + b;
        calibvalue = bit32.lshift(b, 8) + calibvalue;
        actualvalues[#actualvalues+1] = calibvalue;
        ccount = ccount - 1;
        if (ccount == 0) then
            state = State.Switches;
        else
            state = State.ValueActualLow;
        end
    elseif (state == State.Switches) then
        csum = csum + b;
        switches = b;
        state = State.Checksum;
    elseif (state == State.Checksum) then
        if (b == bit32.band(csum, 0xff)) then
            packages = packages + 1;
            print("OK", packages);
            calibdata.packages = packages;
            calibdata.mins = calibmins;
            calibdata.maxs = calibmaxs;
            calibdata.values = actualvalues;
            calibdata.switches = switches;
            calibdata.status = status;
        end
        state = State.Undefined;
    end
end

local lastTimeSend = getTime();
local sendTimeout = 10;

local function onTimeout(f)
    local t = getTime();
    if ((t - lastTimeSend) > sendTimeout) then
        if (f()) then
            lastTimeSend = getTime();
        end
    end
end

local function checksum(frame)
    local csum = 0;
    for i = 3, (#frame - 1) do
        csum = csum + frame[i];
    end
    return bit32.band(csum, 0xff);
end

local function sendHeartbeat()
--    print("sendHB");
    local frame = {0xaa, 0x00, 0x02, 0x01, 0x00};
    frame[#frame] = checksum(frame);
    frame[2] = #frame - 2;
    local s = string.char(table.unpack(frame));
    serialWrite(s);
    return true;
end

function proto.startCalibrate()
    print("startCal");
    local frame = {0xaa, 0x00, 0x02, 0x02, 0x00};
    frame[#frame] = checksum(frame);
    frame[2] = #frame - 2;
    local s = string.char(table.unpack(frame));
    serialWrite(s);
    return true;
end
function proto.stopCalibrate()
    print("stopCal");
    local frame = {0xaa, 0x00, 0x02, 0x03, 0x00};
    frame[#frame] = checksum(frame);
    frame[2] = #frame - 2;
    local s = string.char(table.unpack(frame));
    serialWrite(s);
    return true;
end
function proto.startNormal()
    print("startNormal");
    local frame = {0xaa, 0x00, 0x02, 0x04, 0x00};
    frame[#frame] = checksum(frame);
    frame[2] = #frame - 2;
    local s = string.char(table.unpack(frame));
    serialWrite(s);
    return true;
end

proto.data = calibdata;

function proto.tick() 
    local data = serialRead(64);
    for i = 1, #data do
        parse(string.byte(data, i));
    end
    onTimeout(sendHeartbeat);
end

return proto;
