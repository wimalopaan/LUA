-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 Wilhelm Meier

local M = {}

function M.new()
    return {
        groups = {}, props = {}, groupMap = {}, propMap = {}, bindings = {},
        groupCursor = 1, propCursor = 1, colorCursor = 1, lane = 1,
        off = {[0] = {}, [1] = {}}, offIndex = {[0] = 1, [1] = 1}, offErrors = {},
        epoch = 0, colorEpoch = 0, pendingColors = 0,
    }
end

local function indexed(list, lookup, key)
    local item = lookup[key]
    if item then return item end
    item = {key = key, value = 0, dirty = true, last = -100000, colors = {}, props = {},
            epoch = -1, colorEpoch = -1}
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

function M.retire(sender, previous, push, payload)
    local queue = sender.off[previous.protocol]
    queue[#queue + 1] = {
        protocol = previous.protocol, simulator = previous.simulator, push = push, payload = payload,
    }
end

function M.tickOff(sender)
    local protocol = sender.protocol
    if not sender.off[protocol][sender.offIndex[protocol]] then
        protocol = 1 - protocol
        if not sender.off[protocol][sender.offIndex[protocol]] then return false end
        -- An unavailable old protocol must not starve the newly selected transport.
        if sender.offTurn then sender.offTurn = false; return false end
        sender.offTurn = true
    end
    local queue = sender.off[protocol]
    for _ = 1, 8 do
        local off = queue[sender.offIndex[protocol]]
        if not off then break end
        -- A queued entry may already have been sent by the old runtime during preparation.
        if off.done then sender.offIndex[protocol] = sender.offIndex[protocol] + 1
        else
            if off.push(off, off.payload) then
                off.done = true
                sender.offIndex[protocol] = sender.offIndex[protocol] + 1
                sender.offErrors[protocol] = nil
                if protocol ~= sender.protocol then M.invalidate(sender) end
            else sender.offErrors[protocol] = "Retired output pending: " .. off.error end
            break
        end
    end
    if not queue[sender.offIndex[protocol]] then
        sender.off[protocol], sender.offIndex[protocol], sender.offErrors[protocol] = {}, 1, nil
    end
    sender.offError = sender.offErrors[sender.protocol] or sender.offErrors[1 - sender.protocol]
    return true
end

return M
