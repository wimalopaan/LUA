-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 Wilhelm Meier

local app = ...
app.modules = {"config", "storage", "crsf", "runtime", "ui"}
app.moduleIndex, app.phase, app.revision = 1, "modules", 0
app.values, app.inputIndex = {}, 1

function app.status()
    if app.error then return app.error end
    if app.prepare then
        return "Preparing " .. app.prepare.phase .. ": " .. app.prepare.index
    end
    if app.phase ~= "ready" then return "Loading: " .. app.phase end
    if app.saveJob then return "Saving configuration ..." end
    if app.sender.error then return app.sender.error end
    local status = app.warning or (app.dirty and "Unsaved changes" or "Configuration saved")
    if app.sender.notice then return app.sender.notice .. "; " .. status end
    return status
end

local function beginPrepare(source, change, callback, dirty)
    app.prepare = app.runtime.begin(source, app.data and app or nil, change)
    app.prepare.callback, app.prepare.dirty = callback, dirty
    return app.prepare
end

local function completePrepare(job)
    app.prepare = nil
    if job.error then
        app.error, job.success = job.error, false
        app.phase = app.data and "ready" or "error"
        app.saveRequested = nil
    else
        local state = job.state
        local autoSave = app.data and app.data.header.autoSave == 1 or state.data.header.autoSave == 1
        -- Only references are exchanged here; no configuration-sized loop runs.
        app.data, app.tabs, app.controls = state.data, state.tabs, state.controls
        app.values, app.physical, app.winners = state.values, state.physical, state.winners
        app.addresses, app.sender = state.addresses, state.sender
        app.tabOrder, app.tabControls = state.tabOrder, state.tabControls
        app.visibleControls, app.masks = state.visibleControls, state.masks
        app.usedAddresses = state.usedAddresses
        app.maxTabId, app.maxControlId = state.maxTabId, state.maxControlId
        app.inputIndex, app.phase, app.error = 1, "ready", nil
        app.revision = app.revision + 1
        if job.dirty then app.dirty = true
        else app.dirty = false end
        if job.change and autoSave then app.autoSavePending = true end
        job.success = true
    end
    if job.callback then job.callback(job.success, job.error) end
    if app.saveRequested then
        app.saveRequested = nil
        app.save()
    end
end

function app.commit(kind, record, remove, callback)
    if app.phase ~= "ready" or app.prepare then
        app.error = "Configuration preparation already in progress"
        return
    end
    local ok, err = app.config.validateRecord(record)
    if not ok or kind ~= record.kind or kind == "config" and remove then
        app.error = err or (kind == "config" and remove and "Cannot remove configuration header")
            or "Incorrect configuration record kind"
        return
    end
    app.error = nil
    return beginPrepare(app.data, {kind = kind, record = app.config.copy(record), remove = remove}, callback, true)
end

function app.cancelUpdate(job)
    if app.prepare ~= job or not job.change then return end
    job.done, job.error = true, "Configuration update cancelled"
    completePrepare(job)
end

function app.active(control)
    return control.activation == 0 or getSwitchValue(control.activation)
end

local function setState(state, id, value, changed)
    local control = state.controls[id]
    if not control then return end
    if control.type == 5 then value = math.max(0, math.min(100, math.floor(value + 0.5)))
    else value = math.max(0, math.min(control.type == 3 and 2 or 1, value)) end
    if state.values[id] == value then return end
    if value > 0 and control.group > 0 and control.type ~= 5 then
        local other = state.winners[control.group]
        if other and other ~= id then
            state.values[other] = 0
            app.crsf.set(state.sender, other, 0)
            if changed then changed(other, 0) end
        end
        state.winners[control.group] = id
    elseif control.group > 0 and state.winners[control.group] == id then
        state.winners[control.group] = nil
    end
    state.values[id] = value
    app.crsf.set(state.sender, id, value)
    if changed then changed(id, value) end
end

local function mirror(id, value)
    local job = app.prepare
    if job and job.preserve[id] then
        setState(job.state, id, value)
    end
end

function app.set(id, value)
    setState(app, id, value, mirror)
end

function app.newTab()
    local address = 0
    while app.usedAddresses[address] and address < 256 do address = address + 1 end
    if address == 256 then app.error = "No unused switch address"; return end
    local id = app.maxTabId + 1
    return {kind = "tab", id = id, name = "Tab " .. id, address = address, columns = 2, height = 0}
end

function app.newControl(tab)
    -- The protocol has exactly 256 addresses, with eight outputs each.
    for offset = 0, 255 do
        local address = (tab.address + offset) % 256
        local mask = app.masks[address] or 0
        if mask ~= 0xff then
            for output = 1, 8 do
                if (mask & (1 << (output - 1))) == 0 then
                    local control = app.config.newControl(app.maxControlId + 1, tab.id, output)
                    if address ~= tab.address then control.address = address end
                    return control
                end
            end
        end
    end
    app.error = "All switch outputs are assigned"
end

function app.save()
    if app.prepare then app.saveRequested = true; return end
    if app.phase ~= "ready" then return end
    if app.saveJob then app.saveAgain = true; return end
    app.autoSaveRevision, app.autoSavePending = app.revision, nil
    local generation = app.generation + 1
    if generation > 2147483647 then app.error = "Configuration generation overflow"; return end
    local slot = app.slot == "a" and "b" or "a"
    app.saveRevision, app.saveSlot, app.saveGeneration = app.revision, slot, generation
    app.saveSnapshot = app.data
    app.saveJob = app.storage.save(app.path .. "." .. slot .. ".lua", app.data, generation)
    app.error = nil
end

function app.reset()
    if app.saveJob then return end
    beginPrepare(app.config.defaults(), nil, nil, true)
    app.phase, app.error, app.warning = "prepare", nil, nil
    app.autoSavePending = nil
    app.generation = app.generation or 0
end

local function loadComplete()
    local a, b = app.loads.a, app.loads.b
    local chosen, slot
    if a.result then chosen, slot = a.result, "a" end
    if b.result and (not chosen or b.result.header.generation > chosen.header.generation) then
        chosen, slot = b.result, "b"
    end
    if chosen then
        app.slot, app.generation = slot, chosen.header.generation
        beginPrepare(chosen, nil, nil, false)
        app.phase = "prepare"
        local broken = slot == "a" and b or a
        if not broken.result and not broken.missing then
            app.warning = "Recovered configuration; other slot: " .. broken.error
        end
    elseif a.missing and b.missing then
        app.reset()
    else
        app.phase, app.error = "error", "Cannot load configuration: A: " ..
            tostring(a.error or "missing") .. "; B: " .. tostring(b.error or "missing")
    end
    app.loads = nil
end

local function inputs()
    local count = #app.data.controls
    for _ = 1, math.min(8, count) do
        if app.inputIndex > count then app.inputIndex = 1 end
        local control = app.data.controls[app.inputIndex]
        if not app.active(control) then
            app.set(control.id, 0)
            app.physical[control.id] = nil
        elseif control.type == 5 and control.source ~= 0 then
            local value = getSourceValue(control.source)
            if type(value) == "number" then
                app.set(control.id, value / 10.24)
            else
                app.set(control.id, 0)
                app.error = "Source unavailable: " .. control.name
            end
        elseif control.type ~= 5 and control.switch ~= 0 then
            local value = getSwitchValue(control.switch) and 1 or 0
            if control.type == 3 and value == 0 and control.switch2 ~= 0 and getSwitchValue(control.switch2) then
                value = 2
            end
            -- Resolve physical mutex requests only on edges, not on every polling cycle.
            if app.physical[control.id] ~= value then
                app.physical[control.id] = value
                app.set(control.id, value)
            end
        end
        local job = app.prepare
        if job and job.preserve[control.id] then
            job.state.physical[control.id] = app.physical[control.id]
        end
        app.inputIndex = app.inputIndex + 1
    end
end

function app.tick()
    local now = getTime()
    if app.lastTick == now then return end
    app.lastTick = now
    if app.phase == "modules" then
        local name = app.modules[app.moduleIndex]
        local script, err = loadScript(app.dir .. name .. ".lua", "t")
        if not script then app.error = "Cannot load " .. name .. ": " .. tostring(err); app.phase = "error"; return end
        local ok, result = pcall(script, name == "storage" and app.config or app)
        if not ok or type(result) ~= "table" then
            app.error, app.phase = "Module " .. name .. ": " .. tostring(result), "error"
            return
        end
        app[name] = result
        app.moduleIndex = app.moduleIndex + 1
        if app.moduleIndex > #app.modules then
            app.sender, app.physical = app.crsf.new(), {}
            app.phase = "files"
            app.loads = {a = app.storage.load(app.path .. ".a.lua"), b = app.storage.load(app.path .. ".b.lua")}
        end
    elseif app.phase == "files" then
        if not app.loads.a.done then app.storage.stepLoad(app.loads.a)
        elseif not app.loads.b.done then app.storage.stepLoad(app.loads.b)
        else loadComplete() end
    elseif app.phase == "ready" or app.phase == "prepare" then
        if app.data then
            inputs()
            local quality = getValue("RQly")
            if type(quality) == "number" then
                if quality > 0 and (app.quality or 0) == 0 then
                    app.crsf.colors(app.sender)
                    app.crsf.invalidate(app.sender)
                end
                app.quality = quality
            end
            app.crsf.tick(app.sender, now)
        end
        if app.prepare then
            local job = app.prepare
            app.runtime.step(job)
            if job.done then completePrepare(job) end
        end
        if not app.prepare and app.dirty and not app.saveJob and (app.data.header.autoSave == 1 or app.autoSavePending)
            and app.autoSaveRevision ~= app.revision then
            app.save()
        end
        if app.saveJob then
            if app.saveVerify then app.storage.stepLoad(app.saveJob)
            else app.storage.stepSave(app.saveJob) end
            if app.saveJob.done then
                local saved = false
                if app.saveJob.error then app.error = "Save failed: " .. app.saveJob.error
                elseif not app.saveVerify then
                    app.saveJob = app.storage.load(app.path .. "." .. app.saveSlot .. ".lua",
                                                  app.saveSnapshot, app.saveGeneration)
                    app.saveVerify = true
                    return
                elseif app.saveJob.result and app.saveJob.result.header.generation == app.saveGeneration then
                    app.slot, app.generation = app.saveSlot, app.saveGeneration
                    app.dirty = app.revision ~= app.saveRevision
                    app.warning = nil
                    saved = true
                else
                    app.error = "Save verification failed"
                end
                app.saveJob, app.saveVerify = nil, nil
                app.saveSnapshot = nil
                local again = app.saveAgain
                app.saveAgain = nil
                if saved and app.dirty and again then app.save() end
            end
        end
    end
end

return app
