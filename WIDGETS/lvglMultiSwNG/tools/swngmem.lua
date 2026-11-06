-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 Wilhelm Meier

local DIR = "/WIDGETS/lvglMultiSwNG/"
local LOG = "/LOGS/swngmem.csv"
local SIZES = {8, 32, 64, 128, 256}
local CASES = {
    {name = "CRSF buttons", protocol = 0, type = 1},
    {name = "CRSF sliders", protocol = 0, type = 5},
    {name = "S.Port WM", protocol = 1, type = 1},
    {name = "ACW 1.5", protocol = 2, type = 1},
    {name = "ACW 1.4", protocol = 3, type = 1},
    {name = "Empty tabs", protocol = 0, type = 1, tabsOnly = true},
}
local HEADER = "radio,version,case,controls,tabs,before_modules_kib,baseline_kib,two_slots_kib,active_kib," ..
    "prepare_kib,sampled_peak_kib,min_free_kib,reserve_kib,status,error\n"
local state

local function selection()
    local case = CASES[(state.selection - 1) % #CASES + 1]
    local count = SIZES[math.floor((state.selection - 1) / #CASES) + 1]
    if case.tabsOnly then return case, 0, count end
    if case.protocol >= 2 then count = math.min(count, 255) end
    return case, count, math.ceil(count / 8)
end

local function sample()
    local used, free = collectgarbage("count"), getAvailableMemory()
    if type(used) ~= "number" or used < 0 or type(free) ~= "number" or free < 0 then
        error("Invalid memory API result")
    end
    free = free / 1024
    state.peak = math.max(state.peak or used, used)
    state.minimum = math.min(state.minimum or free, free)
    return used, free
end

local function snapshot(key)
    collectgarbage("collect")
    state.metrics[key] = sample()
end

local function csv(value)
    if value == nil then return "" end
    if type(value) == "number" then return string.format("%.1f", value) end
    return '"' .. string.gsub(value, '"', '""') .. '"'
end

local function report(status, reason)
    local fresh = fstat(LOG) == nil
    local file, err = io.open(LOG, "a")
    if not file then return nil, err or "Cannot open diagnostic CSV" end
    local fields = {
        csv(state.radio), csv(state.version), csv(state.case.name), tostring(state.count), tostring(state.tabs),
        csv(state.moduleBase), csv(state.metrics.baseline), csv(state.metrics.slots), csv(state.metrics.active),
        csv(state.metrics.prepare), csv(state.peak), csv(state.minimum), csv(state.reserve),
        csv(status), csv(reason),
    }
    local ok
    ok, err = io.write(file, (fresh and HEADER or "") .. table.concat(fields, ",") .. "\n")
    local closed, closeError = io.close(file)
    if not ok or closed == false or closeError then
        return nil, err or closeError or "Cannot write diagnostic CSV"
    end
    return true
end

local function finish(status, reason)
    state.builder, state.first, state.second, state.job, state.active = nil, nil, nil, nil, nil
    if not state.loaded then state.app = nil end
    collectgarbage("collect")
    state.phase, state.error = nil, reason
    local ok, err = report(status, reason)
    if not ok then state.error = (reason and (reason .. "; ") or "") .. err end
    state.status = state.error and "Stopped" or "Complete"
end

local function module(name, argument)
    local script, err = loadScript(DIR .. name .. ".lua", "tx")
    if not script then error("Cannot load " .. name .. ": " .. tostring(err)) end
    local result = script(argument)
    if type(result) ~= "table" then error("Invalid module: " .. name) end
    return result
end

local function firstRecord(index)
    local config = state.app.config
    if index == 1 then
        local header = config.defaults().header
        header.name, header.autoSave, header.protocol = "Memory profile", 0, state.case.protocol
        return header
    elseif index <= state.tabs + 1 then
        local id = index - 1
        return {kind = "tab", id = id, name = "Tab " .. id, address = id - 1, columns = 2, height = 0}
    end
    local id = index - state.tabs - 1
    if id <= state.count then
        local control = config.newControl(id, math.floor((id - 1) / 8) + 1, (id - 1) % 8 + 1)
        control.type = state.case.type
        return control
    end
end

local function secondRecord(index)
    local data = state.first
    local record
    if index == 1 then record = data.header
    elseif index <= #data.tabs + 1 then record = data.tabs[index - 1]
    else record = data.controls[index - #data.tabs - 1] end
    if record then return state.app.config.copy(record) end
end

local function beginData()
    snapshot("baseline")
    state.builder, state.index, state.phase = state.app.config.builder(), 1, "first slot"
end

local function step()
    if state.phase == "app" then
        state.app = module("app", {dir = DIR})
        state.index, state.phase = 1, "modules"
    elseif state.phase == "modules" then
        local app = state.app
        if app.i18n and not app.i18n.ready then
            local ok, err = app.i18n.step("tx")
            if not ok then error(err) end
            return
        end
        local name = app.modules[state.index]
        app[name] = module(name, name == "storage" and app.config or app)
        state.index = state.index + 1
        if state.index > #app.modules then state.loaded = true; beginData() end
    elseif state.phase == "first slot" or state.phase == "second slot" then
        local config = state.app.config
        local record
        if state.phase == "first slot" then record = firstRecord(state.index)
        else record = secondRecord(state.index) end
        if record then
            local ok, err = config.append(state.builder, record)
            if not ok then error(err) end
            state.index = state.index + 1
        else
            local data, err = config.finish(state.builder)
            if not data then error(err) end
            state.builder = nil
            if state.phase == "first slot" then
                state.first = data
                state.builder, state.index, state.phase = config.builder(), 1, "second slot"
            else
                state.second = data
                snapshot("slots")
                state.second = nil
                state.job = state.app.runtime.begin(state.first, nil, nil)
                state.phase = "runtime"
            end
        end
    elseif state.phase == "runtime" or state.phase == "prepare" then
        local runtime = state.app.runtime
        runtime.step(state.job)
        if state.job.done then
            if state.job.error then error(state.job.error) end
            if state.phase == "runtime" then
                state.active = state.job.state
                state.first, state.job = nil, nil
                snapshot("active")
                local header = state.app.config.copy(state.active.data.header)
                header.name = "Memory update"
                state.job = runtime.begin(state.active.data, state.active, {kind = "config", record = header})
                state.phase = "prepare"
            else
                snapshot("prepare")
                finish("complete")
            end
        end
    end
end

local function start()
    state.case, state.count, state.tabs = selection()
    state.metrics, state.peak, state.minimum, state.error = {}, nil, nil, nil
    collectgarbage("collect")
    local used, free = sample()
    if not state.loaded then state.moduleBase = used end
    -- A diagnostic safety margin, not a widget configuration limit.
    state.reserve = math.max(128, free / 4)
    if free <= state.reserve then finish("stopped", "Insufficient heap reserve"); return end
    state.status = "Running"
    if state.loaded then beginData()
    else state.phase = "app" end
end

local function draw()
    lcd.clear()
    local case, count, tabs = selection()
    lcd.drawText(10, 8, "MultiSw NG memory", BOLD)
    lcd.drawText(10, 32, case.name .. ": " .. count .. " controls, " .. tabs .. " tabs", SMLSIZE)
    lcd.drawText(10, 54, "Rotary: select; ENTER: run; EXIT: cancel/close", SMLSIZE)
    lcd.drawText(10, 76, state.phase or state.status, SMLSIZE)
    local metrics = state.metrics
    lcd.drawText(10, 100, "Baseline / two slots: " .. csv(metrics.baseline) .. " / " .. csv(metrics.slots) .. " KiB", SMLSIZE)
    lcd.drawText(10, 122, "Active / preparation: " .. csv(metrics.active) .. " / " .. csv(metrics.prepare) .. " KiB", SMLSIZE)
    lcd.drawText(10, 144, "Sampled peak / min free: " .. csv(state.peak) .. " / " .. csv(state.minimum) .. " KiB", SMLSIZE)
    lcd.drawText(10, 166, "Heap reserve: " .. csv(state.reserve) .. " KiB; no output packets", SMLSIZE)
    lcd.drawText(10, 188, "CSV: " .. LOG, SMLSIZE)
    lcd.drawText(10, 210, state.error or "Lua data only; native LVGL objects are not measured.", SMLSIZE)
    lcd.drawText(10, 232, "Run only on the ground with RF modules disabled.", SMLSIZE)
end

local function init()
    state = {selection = 1, metrics = {}, status = "Ready"}
    state.version, state.radio = getVersion()
    if type(collectgarbage) ~= "function" or type(getAvailableMemory) ~= "function" then
        state.error, state.status, state.disabled = "Required memory APIs unavailable", "Stopped", true
    elseif type(fstat) ~= "function" then
        state.error, state.status, state.disabled = "fstat API unavailable", "Stopped", true
    end
end

local function advance()
    local _, free = sample()
    if free <= state.reserve then finish("stopped", "Heap reserve reached"); return end
    step()
    if state.phase then
        _, free = sample()
        if free <= state.reserve then finish("stopped", "Heap reserve reached") end
    end
end

local function run(event)
    if event == EVT_VIRTUAL_EXIT then
        if state.phase then finish("cancelled", "Cancelled by user")
        else return 2 end
    elseif not state.phase and not state.disabled then
        if event == EVT_VIRTUAL_ENTER then
            local ok, err = pcall(start)
            if not ok then finish("error", tostring(err)) end
        elseif event == EVT_VIRTUAL_NEXT or event == EVT_VIRTUAL_PREV then
            local offset = event == EVT_VIRTUAL_NEXT and 1 or -1
            state.selection = (state.selection + offset - 1) % (#CASES * #SIZES) + 1
            state.metrics, state.peak, state.minimum, state.reserve, state.error = {}, nil, nil, nil, nil
            state.status = "Ready"
        end
    end
    if state.phase then
        local ok, err = pcall(advance)
        if not ok then finish("error", tostring(err)) end
    end
    draw()
    return 0
end

return {name = "NG memory", init = init, run = run}
