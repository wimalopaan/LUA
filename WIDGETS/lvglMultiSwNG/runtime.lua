-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 Wilhelm Meier

local app = ...
local M = {}

function M.begin(source, previous, change)
    local builder = app.config.builder()
    local header = change and change.kind == "config" and change.record or source.header
    local backend = app.protocol(header)
    return {
        source = source, previous = previous, change = change,
        phase = "header", index = 1, steps = 0, builder = builder, preserve = {},
        state = {
            data = builder.config, tabs = {}, controls = {}, addresses = {},
            tabOrder = {}, tabControls = {}, visibleControls = {},
            values = {}, physical = {}, winners = {}, groupCounts = {}, masks = {}, usedAddresses = {},
            inputErrors = {}, inputErrorCount = 0,
            maxTabId = 0, maxControlId = 0, backend = backend, sender = backend.new(),
        },
    }
end

local function append(job, record)
    local ok, err = app.config.append(job.builder, record)
    if not ok then job.done, job.error = true, err; return end
    local state = job.state
    if record.kind == "config" then
        state.backend.header(state.sender, state.data.header)
    elseif record.kind == "tab" then
        state.tabs[record.id] = record
        state.tabOrder[record.id] = #state.data.tabs
        state.tabControls[record.id], state.visibleControls[record.id] = {}, {}
        state.usedAddresses[record.address] = true
        state.maxTabId = math.max(state.maxTabId, record.id)
    else
        local id = record.id
        local address = app.config.address(record, state.tabs[record.tab])
        state.controls[id], state.addresses[id] = record, address
        local list = state.tabControls[record.tab]
        list[#list + 1] = record
        if record.visible == 1 then
            list = state.visibleControls[record.tab]
            list[#list + 1] = record
        end
        state.masks[address] = (state.masks[address] or 0) | (1 << (record.output - 1))
        state.usedAddresses[address] = true
        state.maxControlId = math.max(state.maxControlId, id)
        local previous = job.previous
        local old = previous and previous.controls[id]
        if old and previous.addresses[id] == address and old.output == record.output
            and old.type == record.type and old.switch == record.switch
            and old.switch2 == record.switch2 and old.source == record.source
            and old.group == record.group and old.activation == record.activation
            and not (record.type == 4 and record.switch == 0) then
            job.preserve[id] = true
            state.values[id] = previous.values[id] or 0
            state.physical[id] = previous.physical[id]
            if previous.inputErrors[id] then
                state.inputErrors[id] = true
                state.inputErrorCount = state.inputErrorCount + 1
                state.inputErrorId = id
            end
        else state.values[id] = 0 end
        if record.type ~= 5 and record.group > 0 then
            state.groupCounts[record.group] = (state.groupCounts[record.group] or 0) + 1
            if state.values[id] > 0 then state.winners[record.group] = id end
        end
    end
end

local function nextPhase(job, phase)
    job.phase, job.index = phase, 1
end

local function sourceRecord(job, record)
    local change = job.change
    if not change then return record end
    if change.kind == "tab" and change.remove and record.kind == "control" and record.tab == change.record.id then
        return
    end
    if record.kind == change.kind and record.id == change.record.id then
        job.found = true
        if not change.remove then return change.record end
        return
    end
    return record
end

function M.step(job)
    if job.done then return end
    job.steps = job.steps + 1
    local source, state, previous = job.source, job.state, job.previous
    if job.phase == "header" then
        local header = job.change and job.change.kind == "config" and job.change.record or source.header
        append(job, header)
        nextPhase(job, "tabs")
    elseif job.phase == "tabs" or job.phase == "controls" then
        local list = job.phase == "tabs" and source.tabs or source.controls
        local record = list[job.index]
        if record then
            record = sourceRecord(job, record)
            if record then append(job, record) end
            job.index = job.index + 1
        else
            local kind = job.phase == "tabs" and "tab" or "control"
            local change = job.change
            if change and change.kind == kind and not change.remove and not job.found then
                append(job, change.record)
                job.found = true
            end
            if kind == "tab" then nextPhase(job, "controls")
            else
                if change and change.remove and not job.found then
                    job.done, job.error = true, app.t("Configuration record no longer exists")
                    return
                end
                local valid, err = app.config.finish(job.builder)
                if not valid then job.done, job.error = true, err; return end
                nextPhase(job, "sender")
            end
        end
    elseif job.phase == "sender" then
        local control = state.data.controls[job.index]
        if control then
            state.backend.addControl(state.sender, control, state.addresses[control.id], state.values[control.id])
            if previous then app.outputs.inherit(state.sender, previous.sender, control.id) end
            job.index = job.index + 1
        else
            nextPhase(job, "pending-off")
            job.offProtocol = 0
            job.index = previous and previous.sender.offIndex[0] or 1
        end
    elseif job.phase == "pending-off" then
        local payload = previous and previous.sender.off[job.offProtocol][job.index]
        if payload then
            if not payload.done then
                local queue = state.sender.off[job.offProtocol]
                queue[#queue + 1] = payload
            end
            job.index = job.index + 1
        elseif job.offProtocol < 3 then
            job.offProtocol = job.offProtocol + 1
            job.index = previous and previous.sender.offIndex[job.offProtocol] or 1
        else nextPhase(job, "retire-switches") end
    elseif job.phase == "retire-switches" then
        local group = previous and previous.sender.groups[job.index]
        if group then
            previous.backend.retireGroup(state.sender, previous.sender, group)
            job.index = job.index + 1
        else nextPhase(job, "retire-sliders") end
    elseif job.phase == "retire-sliders" then
        local prop = previous and previous.sender.props[job.index]
        if prop then
            previous.backend.retireProp(state.sender, previous.sender, prop)
            job.index = job.index + 1
        else
            job.phase, job.done = "complete", true
        end
    end
end

return M
