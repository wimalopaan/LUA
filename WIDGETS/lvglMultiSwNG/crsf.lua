-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 Wilhelm Meier

local app = ...
local t = app.t
local outputs = app.outputs
local M = {addControl = outputs.addControl, set = outputs.set, invalidate = outputs.invalidate}
local push
local SERIAL_UNAVAILABLE = t("Simulator serialWrite API unavailable")
local CRSF_UNAVAILABLE = t("CRSF API unavailable")

function M.new()
    local simulator = false
    if type(getVersion) == "function" then
        local _, radio = getVersion()
        simulator = type(radio) == "string" and string.sub(radio, -5) == "-simu"
    end
    local sender = outputs.new()
    sender.protocol, sender.simulator = 0, simulator
    sender.notice = simulator and t("Simulator: serial CRSF (delivery unconfirmed)") or nil
    return sender
end

local function crc8(crc, byte, polynomial)
    crc = crc ~ byte
    for _ = 1, 8 do
        local high = crc & 0x80
        crc = (crc << 1) & 0xff
        if high ~= 0 then crc = crc ~ polynomial end
    end
    return crc
end

local function serialPush(payload)
    local frame = {0xc8, #payload + 3, 0x32}
    local commandCRC, frameCRC = crc8(0, 0x32, 0xba), crc8(0, 0x32, 0xd5)
    for _, byte in ipairs(payload) do
        frame[#frame + 1] = byte
        commandCRC = crc8(commandCRC, byte, 0xba)
        frameCRC = crc8(frameCRC, byte, 0xd5)
    end
    frame[#frame + 1] = commandCRC
    frame[#frame + 1] = crc8(frameCRC, commandCRC, 0xd5)
    -- serialWrite has no acknowledgement or queue-status return value.
    serialWrite(string.char(table.unpack(frame)))
end

function M.header(sender, header)
    sender.destination, sender.interval = header.destination, header.interval
    sender.sendColors = header.sendColors == 1
end

function M.retireGroup(sender, previous, group)
    if previous.protocol ~= sender.protocol or previous.destination ~= sender.destination
        or not sender.groupMap[group.key] then
        outputs.retire(sender, previous, push,
                       {previous.destination, 0xea, 0xa1, 0x07, group.key, 0, 0}, group.delivery)
    end
end

function M.retireProp(sender, previous, prop)
    if previous.protocol ~= sender.protocol or previous.destination ~= sender.destination
        or not sender.propMap[prop.key] then
        outputs.retire(sender, previous, push,
                       {previous.destination, 0xea, 0xa1, 0x02, prop.address, prop.output, 0}, prop.delivery)
    end
end

function M.colors(sender, once)
    sender.colorEpoch = sender.colorEpoch + 1
    if once or sender.pendingColors > 0 then sender.pendingColors = #sender.groups end
end

local function due(sender, item, now)
    return item.dirty or item.epoch ~= sender.epoch or now < item.last or now - item.last >= sender.interval
end

local function rgb(control)
    local color = control.color
    if (color & 0x8000) == 0 then color = lcd.getColor(color) end
    local rgb565 = (color >> 16) & 0xffff
    return (control.output - 1) * 16 + ((rgb565 >> 12) & 15),
           ((rgb565 >> 7) & 15) * 16 + ((rgb565 >> 1) & 15)
end

local function groupPacket(sender, now)
    local selected, count = {}, #sender.groups
    local scanned = math.min(18, count)
    for offset = 0, scanned - 1 do
        local index = (sender.groupCursor + offset - 1) % count + 1
        local group = sender.groups[index]
        if due(sender, group, now) then
            selected[#selected + 1] = {item = group, index = index}
            if #selected == 18 then break end
        end
    end
    local nextCursor = count > 0 and (sender.groupCursor + scanned - 1) % count + 1 or 1
    if #selected == 0 then sender.groupCursor = nextCursor; return end
    local payload = {sender.destination, 0xea, 0xa1, #selected == 1 and 0x07 or 0x09}
    if #selected > 1 then payload[5] = #selected end
    for _, selection in ipairs(selected) do
        local group = selection.item
        payload[#payload + 1] = group.key
        payload[#payload + 1] = math.floor(group.value / 256)
        payload[#payload + 1] = group.value % 256
    end
    return payload, function()
        for _, selection in ipairs(selected) do
            local group = selection.item
            group.last, group.dirty, group.epoch = now, false, sender.epoch
            group.delivery.active = group.value ~= 0
            -- Each address has at most eight associated proportional outputs.
            for _, prop in ipairs(group.props) do prop.dirty = true end
        end
        sender.groupCursor = nextCursor
    end
end

local function propPacket(sender, now)
    local count = #sender.props
    local scanned = math.min(8, count)
    for offset = 0, scanned - 1 do
        local index = (sender.propCursor + offset - 1) % count + 1
        local prop = sender.props[index]
        if due(sender, prop, now) then
            return {sender.destination, 0xea, 0xa1, 0x02, prop.address, prop.output, prop.value}, function()
                prop.last, prop.dirty, prop.epoch = now, false, sender.epoch
                prop.delivery.active = prop.value ~= 0
                sender.propCursor = index % count + 1
            end
        end
    end
    sender.propCursor = count > 0 and (sender.propCursor + scanned - 1) % count + 1 or 1
end

local function colorPacket(sender)
    if not sender.sendColors and sender.pendingColors == 0 then return end
    local count = #sender.groups
    if count > 0 then
        local index = (sender.colorCursor - 1) % count + 1
        local group = sender.groups[index]
        local nextCursor = index % count + 1
        if group.colorDirty or group.colorEpoch ~= sender.colorEpoch then
            local payload = {sender.destination, 0xea, 0xa1, 0x0a, group.key, #group.colors}
            for _, control in ipairs(group.colors) do
                local red, gb = rgb(control)
                payload[#payload + 1], payload[#payload + 2] = red, gb
            end
            return payload, function()
                group.colorDirty, group.colorEpoch = false, sender.colorEpoch
                sender.colorCursor = nextCursor
                if sender.pendingColors > 0 then sender.pendingColors = sender.pendingColors - 1 end
            end
        end
        sender.colorCursor = nextCursor
    end
end

local function available(sender)
    local error
    if sender.simulator and type(serialWrite) ~= "function" then
        error = SERIAL_UNAVAILABLE
    elseif not sender.simulator and type(crossfireTelemetryPush) ~= "function" then
        error = CRSF_UNAVAILABLE
    end
    if error then sender.error = error; return end
    if sender.error == SERIAL_UNAVAILABLE or sender.error == CRSF_UNAVAILABLE then
        sender.error = nil
    end
    return true
end

push = function(sender, payload)
    if not available(sender) then return end
    local queued
    if sender.simulator then
        serialPush(payload)
        queued = true
    else
        -- EdgeTX appends both CRCs. A full transmit FIFO must not lose state.
        queued = crossfireTelemetryPush(0x32, payload)
    end
    if queued == nil then sender.error = t("CRSF inactive: select a CRSF/ELRS RF module")
    elseif not queued then sender.error = t("CRSF transmit queue busy")
    else sender.error = nil end
    return queued
end
function M.tick(sender, now)
    local ready = available(sender)
    if outputs.tickOff(sender) or not ready then return end
    local lanes = {groupPacket, propPacket, colorPacket}
    for offset = 0, 2 do
        local lane = (sender.lane + offset - 1) % 3 + 1
        local payload, sent = lanes[lane](sender, now)
        if payload then
            if push(sender, payload) then
                sent()
                sender.lane = lane % 3 + 1
            end
            return
        end
    end
end

return M
