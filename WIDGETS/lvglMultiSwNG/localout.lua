-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 Wilhelm Meier

local app = ...
local t = app.t
local M = {}
local delivered, errors, cursor, retry = {}, {}, 1, nil
local virtualIndices = {}
local managed, activationErrors = {}, {}

function M.hasVirtual()
    return type(setVirtualSwitch) == "function" and type(getSwitchIndex) == "function"
        and type(getSwitchName) == "function"
end

function M.canActivateVirtual()
    return M.hasVirtual() and type(activateVirtualSwitch) == "function"
end

function M.validateHeader(header)
    if string.find(header.virtualSwitches, "1", 1, true) and not M.canActivateVirtual() then
        return nil, t("Virtual switch activation API unavailable")
    end
    return true
end

function M.name(target)
    return string.format(target > 64 and "VS%02d" or "L%02d", (target - 1) % 64 + 1)
end

local function virtualIndex(target)
    local index = virtualIndices[target]
    if not index then
        -- EdgeTX uses VS1, not the widget's padded display label VS01.
        index = getSwitchIndex(string.format("VS%d", target - 64))
        if type(index) ~= "number" or index <= 0 then
            return nil, t("Cannot resolve local switch: %s", M.name(target))
        end
        virtualIndices[target] = index
    end
    return index
end

function M.available(target, header)
    if target > 64 then
        if not M.hasVirtual() then return nil, t("Virtual switch API unavailable") end
        local index, err = virtualIndex(target)
        if not index then return nil, err end
        -- getVirtualSwitch returns the on/off state, not whether the switch is enabled.
        if getSwitchName(index) == nil and not (header and app.config.virtualEnabled(header, target - 64)) then
            return nil, t("Virtual switch is not activated: %s", M.name(target))
        end
    else
        if type(setStickySwitch) ~= "function" or not model
            or type(model.getLogicalSwitch) ~= "function" or LS_FUNC_STICKY == nil then
            return nil, t("Sticky switch API unavailable")
        end
        local switch = model.getLogicalSwitch(target - 1)
        if not switch or switch.func ~= LS_FUNC_STICKY then
            return nil, t("Configure %s as Sticky", M.name(target))
        end
    end
    return true
end

function M.validate(control, header, previousHeader)
    local target = control.localSwitch
    if target == 0 then return true end
    if target > 64 and previousHeader and app.config.virtualEnabled(previousHeader, target - 64)
        and not app.config.virtualEnabled(header, target - 64) then
        return nil, t("Remove the assignment before deactivating %s", M.name(target))
    end
    local ok, err = M.available(target, header)
    if not ok then return nil, err end
    local index
    if target > 64 then index = virtualIndex(target)
    elseif type(getSwitchIndex) == "function" then index = getSwitchIndex(M.name(target)) end
    if type(index) ~= "number" or index <= 0 then
        return nil, t("Cannot resolve local switch: %s", M.name(target))
    end
    if math.abs(control.switch) == index or control.type == 3 and math.abs(control.switch2) == index
        or math.abs(control.activation) == index then
        return nil, t("Local switch feeds its own input: %s", control.name)
    end
    return true
end

local function activation(number)
    local desired = app.config.virtualEnabled(app.data.header, number)
    if not desired and not managed[number] then return end
    local target = number + 64
    if not M.canActivateVirtual() then
        activationErrors[target] = t("Virtual switch activation API unavailable")
        return
    end
    if desired then
        if not managed[number] or not M.available(target) then
            activateVirtualSwitch(number, true)
            managed[number], delivered[target] = true, nil
        end
        local ok, err = M.available(target)
        if not ok then
            activationErrors[target] = t("Cannot activate %s: %s", M.name(target), err)
            return
        end
    else
        setVirtualSwitch(number, false)
        activateVirtualSwitch(number, false)
        local index, err = virtualIndex(target)
        if not index then activationErrors[target] = err; return end
        if getSwitchName(index) ~= nil then
            activationErrors[target] = t("Cannot deactivate %s", M.name(target))
            return
        end
        managed[number], delivered[target], errors[target] = nil, nil, nil
    end
    activationErrors[target] = nil
end

local function update(target)
    if retry == target then retry = nil end
    if target > 64 then activation(target - 64) end
    local id = app.localTargets[target]
    local value = id ~= nil and app.values[id] > 0
    local previous = delivered[target]
    if not id and previous ~= true then errors[target] = nil; return end
    local ok, err = M.available(target)
    if not ok then errors[target] = err; return end
    if previous ~= value then
        if target > 64 then
            setVirtualSwitch(target - 64, value)
        else
            if retry then return end
            -- EdgeTX returns true when its eight-slot buffer is full, false on success.
            local full = setStickySwitch(target - 1, value)
            if full ~= false then
                if full == true then retry = target end
                errors[target] = full == true and t("Sticky switch queue busy")
                    or t("Unexpected Sticky switch API result")
                return
            end
        end
        delivered[target] = value
    end
    errors[target] = nil
end

function M.changed(id)
    local target = app.controls[id].localSwitch
    if target > 0 then update(target) end
end

function M.tick()
    -- Reconcile new/removed assignments and retry blocked writes without touching drafts.
    local scans = 8
    if retry then update(retry); scans = 7 end
    for _ = 1, scans do
        update(cursor)
        cursor = cursor % 128 + 1
    end
end

function M.status()
    local target, err = next(activationErrors)
    if not target then target, err = next(errors) end
    if target then return t("Local switch %s: %s", M.name(target), err) end
end

return M
