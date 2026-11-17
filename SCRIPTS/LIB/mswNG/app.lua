-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 Wilhelm Meier

local telemetry = ...
local app = {version = 5, page = 1, telemetry = telemetry, dirty = false}
local directory = "/SCRIPTS/LIB/mswNG/"
local ui, storage, job, path, afterSave
local slot, generation, quitting = 0, 0, false
local lastForeground

function app.load(name, ...)
    local chunk, err = loadScript(directory .. name .. ".lua", "btd")
    if not chunk then error(err or ("Fehlt: " .. name)) end
    return chunk(...)
end

function app.changed()
    app.release()
    app.dirty, app.inputDirty = true, true
    app.core.rebuild(app.sender, app.config)
end

function app.save(action)
    app.release()
    storage = app.load("storage", app.core)
    job = storage.save(path, app.config, slot, generation)
    app.busy, afterSave = true, action
end

local function progress()
    if not job then return end
    storage.step(job)
    if not job.done then return end
    if job.mode == "load" then
        if job.error then app.fatal = job.error
        else
            app.config = job.result or app.core.defaults()
            slot, generation = job.slot, job.generation or 0
            app.message = job.warning
            app.sender = app.core.sender()
            app.core.rebuild(app.sender, app.config)
        end
    elseif job.error then
        app.message = "Speichern: " .. job.error
    else
        app.dirty, slot, generation = false, job.slot, job.generation
        quitting = afterSave == "exit" and not telemetry
        ui = nil
    end
    job, storage, afterSave, app.busy = nil, nil, nil, false
    return true
end

local function poll()
    if not app.sender then return end
    app.core.poll(app.sender, app.config)
    app.inputDirty = false
end

local function update()
    if not app.sender then return end
    if app.inputDirty then poll() end
    app.core.tick(app.sender, app.config, getTime())
end

function app.release()
    if not app.held then return end
    app.held[4] = 0
    app.held = nil
    app.core.rebuild(app.sender, app.config)
end

function app.init()
    app.core = app.load("core")
    storage = app.load("storage", app.core)
    path = storage.path()
    job = storage.load(path)
    app.busy = true
end

function app.run(event)
    if event == nil then return telemetry and 0 or 2 end
    lastForeground = getTime()
    if progress() then event = 0 end
    if quitting then return 2 end
    poll()
    ui = ui or app.load("ui", app)
    local result = ui.run(event)
    update()
    return result
end

function app.background()
    -- EdgeTX also calls background between foreground frames of a visible script.
    local now = getTime()
    if lastForeground and (now < lastForeground or now - lastForeground >= 100) then
        app.release()
        ui = nil
    end
    progress()
    poll()
    update()
end

return app
