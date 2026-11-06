-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 Wilhelm Meier

local M = {}

function M.new()
    return {
        groups = {}, props = {}, groupMap = {}, propMap = {}, bindings = {},
        groupCursor = 1, propCursor = 1, colorCursor = 1, lane = 1,
        off = {[0] = {}, [1] = {}, [2] = {}, [3] = {}},
        offIndex = {[0] = 1, [1] = 1, [2] = 1, [3] = 1}, offErrors = {}, offProtocol = 0,
        epoch = 0, colorEpoch = 0, pendingColors = 0,
    }
end

local function indexed(list, lookup, key)
    local item = lookup[key]
    if item then return item end
    item = {key = key, value = 0, dirty = true, last = -100000, colors = {}, props = {},
            epoch = -1, colorEpoch = -1, delivery = {active = false}}
    list[#list + 1], lookup[key] = item, item
    return item
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

function M.invalidate(sender)
    sender.epoch = sender.epoch + 1
end

function M.inherit(sender, previous, id)
    if sender.protocol ~= previous.protocol or sender.variant ~= previous.variant
        or sender.destination ~= previous.destination or sender.physicalId ~= previous.physicalId
        or sender.appId ~= previous.appId then return end
    local binding = sender.bindings[id]
    -- Missing history from an older runtime is treated as potentially active.
    if binding.group then
        local old = previous.groupMap[binding.group.key]
        if old then binding.group.delivery = old.delivery or {active = true} end
    end
    if binding.prop then
        local old = previous.propMap[binding.prop.key]
        if old and old.prefix == binding.prop.prefix then
            binding.prop.delivery = old.delivery or {active = true}
        end
    end
end

local function mode(sender)
    return sender.variant or sender.protocol
end

function M.retire(sender, previous, push, payload, delivery)
    local protocol = mode(previous)
    local queue = sender.off[protocol]
    queue[#queue + 1] = {
        protocol = protocol, simulator = previous.simulator, push = push, payload = payload, delivery = delivery,
    }
end

function M.tickOff(sender)
    local own = mode(sender)
    local protocol = own
    if not sender.off[protocol][sender.offIndex[protocol]] then
        -- An unavailable old protocol must not starve the newly selected transport.
        if sender.offTurn then sender.offTurn = false; return false end
        for offset = 0, 3 do
            local candidate = (sender.offProtocol + offset) % 4
            if candidate ~= own and sender.off[candidate][sender.offIndex[candidate]] then
                protocol, sender.offProtocol = candidate, (candidate + 1) % 4
                break
            end
        end
        if protocol == own then return false end
        sender.offTurn = true
    end
    local queue = sender.off[protocol]
    for _ = 1, 8 do
        local off = queue[sender.offIndex[protocol]]
        if not off then break end
        -- A queued entry may already have been sent by the old runtime during preparation.
        -- Evaluate activity only after activation: the old sender can still transmit during preparation.
        if off.done or off.delivery and off.delivery.active == false then
            off.done = true
            sender.offIndex[protocol] = sender.offIndex[protocol] + 1
        else
            if off.push(off, off.payload) then
                off.done = true
                if off.delivery then off.delivery.active = false end
                sender.offIndex[protocol] = sender.offIndex[protocol] + 1
                sender.offErrors[protocol] = nil
                if protocol ~= own then M.invalidate(sender) end
            else sender.offErrors[protocol] = "Retired output pending: " .. off.error end
            break
        end
    end
    if not queue[sender.offIndex[protocol]] then
        sender.off[protocol], sender.offIndex[protocol], sender.offErrors[protocol] = {}, 1, nil
    end
    sender.offError = sender.offErrors[own]
    for candidate = 0, 3 do
        sender.offError = sender.offError or sender.offErrors[candidate]
    end
    return true
end

return M
