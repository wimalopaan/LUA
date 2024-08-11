local zone, options, config = ...
local widget                = {}
widget.options              = options;

local WIDTH                 = 90
local HEIGHT                = 16
local COL1                  = 20
local MID                   = 480 / 2
local COL3                  = MID + COL1
local TOP                   = 32
local ROW                   = (272 - 4 * TOP) / 4

local libGUI                = loadGUI()
local gui                   = libGUI.newGUI()

local packagesTotal         = 0;
local bytesTotal            = 0;
local packagesCounter       = {[0] = 0, 0, 0, 0, 0, 0, 0, 0};
local packagesCounterProp   = {[0] = 0, 0, 0, 0, 0, 0, 0, 0};
local lastSwitches          = {[0] = 0, 0, 0, 0, 0, 0, 0, 0};
local lsStart               = {};
local ShmStart              = {};
local buttons               = {};

-- todo
local function callback()
end

local function create()
    setSerialBaudrate(115200);

    local name = "";
    local col = COL1;
    local row = 0;
    for row = 0, 3 do
        name = "SW " .. row;
        buttons[#buttons + 1] = gui.toggleButton(col, 4 * TOP + row * ROW, WIDTH, HEIGHT, name, false, callback);
        row = row + 1;
    end
    col = COL3;
    for row = 0, 3 do
        name = "SW " .. (row + 4);
        buttons[#buttons + 1] = gui.toggleButton(col, 4 * TOP + row * ROW, WIDTH, HEIGHT, name, false, callback);
        row = row + 1;
    end
end

-- Draw in widget mode
local function widgetRefresh()
    lcd.drawText(zone.w / 2, zone.h / 2, "HW Ext @ " .. widget.options.Show,
        DBLSIZE + CENTER + VCENTER + libGUI.colors.primary3);
end

local function fullScreenRefresh(event, touchState)
    lcd.drawText(MID, TOP / 2, "Hardware Extension @ " .. widget.options.Show, CENTER + VCENTER + libGUI.colors.primary3);
    lcd.drawText(COL1, TOP + TOP / 2, "Packages: " .. packagesCounter[widget.options.Show], VCENTER + libGUI.colors.primary3);
    lcd.drawText(COL3, TOP + TOP / 2, "SW: " .. lastSwitches[widget.options.Show], VCENTER + libGUI.colors.primary3);
    lcd.drawText(COL1, 2 * TOP + TOP / 2, "Packages (total): " .. packagesTotal, VCENTER + libGUI.colors.primary3);
    lcd.drawText(COL3, 2 * TOP + TOP / 2, "Bytes: " .. bytesTotal, VCENTER + libGUI.colors.primary3);
    gui.run(event, touchState)
end

local function setSwitches(switches, controller) 
    packagesCounter[controller] = packagesCounter[controller] + 1;
    local diff = bit32.bxor(lastSwitches[controller], switches);
    local mask = 1;
    local ls = lsStart[controller];
    if (ls ~= nil) then
        for i = 1, 8 do
            local b = buttons[i];
            if (bit32.band(diff, mask) > 0) then
                if (bit32.band(switches, mask) > 0) then
                    if (setStickySwitch(ls + i - 1, true) == false) then
                        lastSwitches[controller] = bit32.bor(lastSwitches[controller], mask);
                        if (controller == widget.options.Show) then
                            if (b ~= nil) then
                                b.value = true;
                            end                                    
                        end
                    end
                else
                    if (setStickySwitch(ls + i - 1, false) == false) then
                        lastSwitches[controller] = bit32.band(lastSwitches[controller], bit32.bnot(mask));
                        if (controller == widget.options.Show) then
                            if (b ~= nil) then
                                b.value = false;
                            end
                        end
                    end
                end
            end
            mask = 2 * mask;     -- left shift
        end
    end
end

local function setPropValues(payload, msgcontroller)
    packagesCounterProp = packagesCounterProp + 1;
end

local msgcontroller = -1;
local type = -1;
local payload = {};

local function parseCallback()
    packagesTotal = packagesTotal + 1;
    if (type == 0x00) then
        if (#payload == 1) then
            setSwitches(payload[1], msgcontroller);
        end
    elseif (type == 0x01) then
        if (#payload == 8) then
            setPropValues(payload, msgcontroller);
        end
    end
end

-- make a real byte-parser, because it is not guaranteed to receive full messages
local state = 0;
local length = -1;
local payloadsum = 0;

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
            parseCallback();
        end
        state = 0;
    end
end 

function widget.background()
    local data = serialRead();

    for i = 1, #data do
        parse(string.byte(data, i));
    end
end

function widget.refresh(event, touchState)
    widget.background();
    if (event) then
        fullScreenRefresh(event, touchState)
    else
        widgetRefresh();
    end
end

function widget.update()
    lsStart[0] = widget.options.C0LS1 - 1;
    lsStart[1] = widget.options.C1LS1 - 1;
    lsStart[2] = widget.options.C2LS1 - 1;
    lsStart[3] = widget.options.C3LS1 - 1;
    lsStart[4] = widget.options.C4LS1 - 1;
    lsStart[5] = widget.options.C5LS1 - 1;
    lsStart[6] = widget.options.C6LS1 - 1;
    lsStart[7] = widget.options.C7LS1 - 1;
    ShmStart[0] = widget.options.C1ShmV;
end

create();
widget.update();

return widget
