local appid = 6010;
local appid_h = bit32.rshift(appid, 8);
local appid_l = bit32.band(appid, 0xff);

local options = {
    {"Length", VALUE, 0, 0, 255};
    {"Type", VALUE, 128, 0, 255};
    {"Dest", VALUE, 0, 0, 255};
    {"Src", VALUE, 0, 0, 255};
    {"P0", VALUE, appid_h, 0, 255};
    {"P1", VALUE, appid_l, 0, 255};
    {"P2", VALUE, 0, 0, 255};
    {"P3", VALUE, 0, 0, 255};
}

local function updateFilter(id, options)
    crossfireTelemetryRemovePrivateQueue(id); -- remove the own queue (if any)
    local filter = {options.Length, options.Type, options.Dest, options.Src, options.P0, options.P1, options.P2, options.P3};
    local r = crossfireTelemetryCreatePrivateQueue(id, filter); -- install new
    print("updateFilter: slot:", r);
    if (r == -1) then
        print("equal filter exists, remove ...");
    elseif (r == -2) then
        print("no more filters posssible");
    end
    return r;
end

local function create(zone, options, widget_id)
    local slot = updateFilter(widget_id, options);
    return {
        zone = zone,
        options = options,
        id = widget_id,
        slot = slot
    };
end

local function update(widget, options)
    widget.options = options;
    widget.slot = updateFilter(widget.id, widget.options);
end

local packetCounter = 0;
local function refresh(widget, event, touch)
    local command, data = crossfireTelemetryPopPrivate(widget.id);
    if (command ~= nil) then
        packetCounter = packetCounter + 1;
    else
        command = 0;
    end
    local dataLength = 0;
    if (data ~= nil) then
        dataLength = #data;
    end
    local y = widget.zone.y;
    lcd.drawText(widget.zone.x, y, "WidgetID: " .. widget.id .. " Slot: " .. widget.slot, LEFT + SMLSIZE);
    y = y + 16;
    lcd.drawText(widget.zone.x, y, "Command: " .. command .. " Counter: " .. packetCounter, LEFT + SMLSIZE);
    y = y + 16;
    lcd.drawText(widget.zone.x, y, "Bytes: " .. dataLength, LEFT + SMLSIZE);
end

return {
    name = "CrsfQueue",
    create = create,
    update = update,
    refresh = refresh,
    options = options
};
