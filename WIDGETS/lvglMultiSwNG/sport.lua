-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 Wilhelm Meier

local app = ...
local t = app.t
local outputs = app.outputs
local M = {invalidate = outputs.invalidate}
local REQUEST_ERROR = t("S.Port packet not accepted: check RF module, queue and sensor conflict")

function M.new()
    local sender = outputs.new()
    sender.protocol, sender.variant = 1, 1
    sender.failedCount = 0
    return sender
end

function M.header(sender, header)
    sender.variant = header.protocol >= 2 and header.protocol or 1
    sender.interval = header.interval
    if sender.variant == 1 then
        sender.physicalId, sender.appId = header.sportPhysicalId, header.sportAppId
    else
        sender.physicalId, sender.dataId = 0x1b, sender.variant == 2 and 0xac00 or 0xfa07
    end
end

function M.addControl(sender, control, address, value)
    if sender.variant == 1 then return outputs.addControl(sender, control, address, value) end
    local key = address * 8 + control.output - 1
    local prop = {
        key = key, prefix = control.sportType * 0x1000000 + control.sportOptions * 0x10000 + (key + 1) * 256,
        pwm = control.sportPwmOn, value = 0, dirty = true, last = -100000, epoch = -1,
        delivery = {active = false},
    }
    sender.props[#sender.props + 1], sender.propMap[key] = prop, prop
    sender.bindings[control.id] = {prop = prop, code = 0}
    M.set(sender, control.id, value)
end

function M.set(sender, id, value)
    if sender.variant == 1 then return outputs.set(sender, id, value) end
    local binding = sender.bindings[id]
    if not binding then return end
    local prop = binding.prop
    binding.code = value > 0 and 1 or 0
    local pwm = binding.code == 1 and prop.pwm or 0
    if prop.value ~= pwm then prop.value, prop.dirty = pwm, true end
end

local function available(sender)
    sender.apiError = type(sportTelemetryPush) ~= "function" and t("S.Port API unavailable") or nil
    return sender.apiError == nil
end

local function push(sender, payload)
    if not available(sender) then sender.error = sender.apiError; return end
    local queued = sportTelemetryPush(payload[1], payload[2], payload[3], payload[4])
    if queued == true then sender.error = nil
    else sender.error = REQUEST_ERROR end
    return queued == true
end

function M.retireGroup(sender, previous, group)
    if previous.protocol ~= sender.protocol or previous.variant ~= sender.variant
        or previous.physicalId ~= sender.physicalId
        or previous.appId ~= sender.appId or not sender.groupMap[group.key] then
        outputs.retire(sender, previous, push,
                       {previous.physicalId, 0x31, previous.appId * 256 + group.key, 0}, group.delivery)
    end
end

function M.retireProp(sender, previous, prop)
    local current = sender.propMap[prop.key]
    if previous.protocol ~= sender.protocol or previous.variant ~= sender.variant
        or not current or prop.prefix ~= current.prefix then
        outputs.retire(sender, previous, push, {previous.physicalId, 0x10, previous.dataId, prop.prefix}, prop.delivery)
    end
end

function M.tick(sender, now)
    local ready = available(sender)
    sender.error = sender.apiError or (sender.failedCount > 0 and REQUEST_ERROR or nil)
    if outputs.tickOff(sender) or not ready then return end
    local acw = sender.variant >= 2
    local list = acw and sender.props or sender.groups
    local count = #list
    local scanned = math.min(8, count)
    for offset = 0, scanned - 1 do
        local index = (sender.groupCursor + offset - 1) % count + 1
        local group = list[index]
        if group.dirty or group.epoch ~= sender.epoch or now < group.last or now - group.last >= sender.interval then
            local payload
            if acw then payload = {sender.physicalId, 0x10, sender.dataId, group.prefix + group.value}
            else payload = {sender.physicalId, 0x31, sender.appId * 256 + group.key, group.value} end
            local queued = push(sender, payload)
            sender.groupCursor = index % count + 1
            if queued then
                group.last, group.dirty, group.epoch = now, false, sender.epoch
                group.delivery.active = group.value ~= 0
                if group.failed then
                    group.failed = nil
                    sender.failedCount = sender.failedCount - 1
                end
            elseif not group.failed then
                group.failed = true
                sender.failedCount = sender.failedCount + 1
            end
            sender.error = sender.apiError or (sender.failedCount > 0 and REQUEST_ERROR or nil)
            return
        end
    end
    sender.groupCursor = count > 0 and (sender.groupCursor + scanned - 1) % count + 1 or 1
end

return M
