-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 Wilhelm Meier

local M = {}

function M.new()
    local simulator = false
    if type(getVersion) == "function" then
        local _, radio = getVersion()
        simulator = type(radio) == "string" and string.sub(radio, -5) == "-simu"
    end
    return {
        groups = {}, props = {}, groupMap = {}, propMap = {}, bindings = {},
        groupCursor = 1, propCursor = 1, colorCursor = 1, lane = 1,
        off = {}, offIndex = 1, epoch = 0, colorEpoch = 0, pendingColors = 0,
        simulator = simulator,
        notice = simulator and "Simulator: serial CRSF (delivery unconfirmed)" or nil,
    }
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

local function indexed(list, lookup, key)
    local item = lookup[key]
    if item then return item end
    item = {key = key, value = 0, dirty = true, last = -100000, colors = {}, props = {},
            epoch = -1, colorEpoch = -1}
    list[#list + 1], lookup[key] = item, item
    return item
end

function M.header(sender, header)
    sender.destination, sender.interval = header.destination, header.interval
    sender.sendColors = header.sendColors == 1
end

function M.addControl(sender, control, address, value)
    local group = indexed(sender.groups, sender.groupMap, address)
    group.colors[#group.colors + 1] = control
    group.colorDirty = true
    local binding = {group = group, shift = 1 << (2 * (control.output - 1)), code = 0}
    if control.type == 5 then
        local prop = indexed(sender.props, sender.propMap, address * 8 + control.output - 1)
        prop.address, prop.output = address, control.output - 1
        binding.prop = prop
        group.props[#group.props + 1] = prop
    end
    sender.bindings[control.id] = binding
    M.set(sender, control.id, value)
end

function M.retireGroup(sender, previous, group)
    if previous.destination ~= sender.destination or not sender.groupMap[group.key] then
        sender.off[#sender.off + 1] = {previous.destination, 0xea, 0xa1, 0x07, group.key, 0, 0}
    end
end

function M.retireProp(sender, previous, prop)
    if previous.destination ~= sender.destination or not sender.propMap[prop.key] then
        sender.off[#sender.off + 1] = {previous.destination, 0xea, 0xa1, 0x02, prop.address, prop.output, 0}
    end
end

function M.set(sender, id, value)
    local binding = sender.bindings[id]
    if not binding then return end
    local code = value
    if binding.prop then
        code = value > 0 and 1 or 0
        if binding.prop.value ~= value then
            binding.prop.value, binding.prop.dirty = value, true
        end
    end
    if code ~= binding.code then
        local group = binding.group
        group.value = group.value + (code - binding.code) * binding.shift
        group.dirty = true
        binding.code = code
    end
end

function M.colors(sender, once)
    sender.colorEpoch = sender.colorEpoch + 1
    if once or sender.pendingColors > 0 then sender.pendingColors = #sender.groups end
end

function M.invalidate(sender)
    sender.epoch = sender.epoch + 1
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

local function push(sender, payload)
    local queued
    if sender.simulator then
        serialPush(payload)
        queued = true
    else
        -- EdgeTX appends both CRCs. A full transmit FIFO must not lose state.
        queued = crossfireTelemetryPush(0x32, payload)
    end
    if queued == nil then sender.error = "CRSF inactive: select a CRSF/ELRS RF module"
    elseif not queued then sender.error = "CRSF transmit queue busy"
    else sender.error = nil end
    return queued
end
function M.tick(sender, now)
    if sender.simulator and type(serialWrite) ~= "function" then
        sender.error = "Simulator serialWrite API unavailable"
        return
    elseif not sender.simulator and type(crossfireTelemetryPush) ~= "function" then
        sender.error = "CRSF API unavailable"
        return
    end
    local off = sender.off[sender.offIndex]
    if off then
        if push(sender, off) then
            sender.offIndex = sender.offIndex + 1
            if sender.offIndex > #sender.off then sender.off, sender.offIndex = {}, 1 end
        end
        return
    end
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
