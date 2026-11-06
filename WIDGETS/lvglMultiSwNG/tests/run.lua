-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 Wilhelm Meier

-- Run from lvglMultiSwNG: lua tests/run.lua
local root = (string.match(arg[0], "^(.*)tests/") or "")
local hostIO = io
local stringMetatable = debug.getmetatable("")
-- Reproduce the simulator's lack of string method lookup.
debug.setmetatable("", nil)
local fs, now, frames, switches, sources, definitions, full, blocked, truncate, writeFailure
local readCount, writeCount, loads, dialogs, quality, objectCount, createdTypes
COLOR_THEME_SECONDARY3, COLOR_THEME_PRIMARY3, COLOR_THEME_WARNING = 3, 4, 5
LCD_W, LCD_H = 480, 272
LEFT, VCENTER, SMLSIZE, BOLD = 0, 32, 1, 2

local function equal(actual, expected, message)
    if actual ~= expected then
        error((message or "Unexpected value") .. ": expected " .. tostring(expected) ..
              ", got " .. tostring(actual), 2)
    end
end

local function contains(text, fragment)
    assert(text and string.find(text, fragment, 1, true), tostring(text) .. " does not contain " .. fragment)
end

local function encode(values)
    local parts = {}
    for _, value in ipairs(values) do parts[#parts + 1] = tostring(value) end
    return table.concat(parts, ",")
end

local function collect(defs)
    local refs = {}
    local function visit(items)
        for _, item in ipairs(items) do
            if item.type == "momentaryButton" then
                assert(item.checked == nil, "Invalid property 'checked' on momentaryButton")
            end
            if item.name then
                local ref = {definition = item}
                function ref:set(changes)
                    if self.definition.type == "momentaryButton" then
                        assert(changes.checked == nil, "Invalid property 'checked' on momentaryButton")
                    end
                    for key, value in pairs(changes) do self.definition[key] = value end
                end
                refs[item.name] = ref
            end
            if item.children then visit(item.children) end
        end
    end
    visit(defs)
    return refs
end

local function reset()
    LCD_W, LCD_H = 480, 272
    fs, now, frames, switches, sources = {}, 0, {}, {}, {}
    definitions, full, blocked, truncate, writeFailure = {}, true, false, false, false
    readCount, writeCount, loads, dialogs, quality, objectCount = 0, 0, 0, {}, 0, 0
    createdTypes = {}
    io = {
        open = function(path, mode)
            if mode == "r" then
                if fs[path] == nil then return nil, "not found: " .. path, 2 end
            else fs[path] = "" end
            return {path = path, position = 1, mode = mode}
        end,
        read = function(file, size)
            assert(not file.closed)
            assert(size <= 512, "Unbounded read")
            readCount = readCount + 1
            local data = string.sub(fs[file.path], file.position, file.position + size - 1)
            file.position = file.position + #data
            return data -- EdgeTX returns an empty string at EOF.
        end,
        write = function(file, text)
            assert(not file.closed)
            assert(#text < 2048, "Unbounded write")
            writeCount = writeCount + 1
            if writeFailure then return nil, "SD full" end
            fs[file.path] = fs[file.path] .. text
            return file
        end,
        close = function(file)
            assert(not file.closed)
            file.closed = true
            if truncate and file.mode == "w" then fs[file.path] = string.sub(fs[file.path], 1, -4) end
            -- EdgeTX has no success return value.
        end,
    }
    loadScript = function(path)
        loads = loads + 1
        return loadfile(path)
    end
    getTime = function() return now end
    getVersion = function() return "3.0.0", "tx16s" end
    serialWrite = nil
    getSwitchValue = function(id) return switches[id] or false end
    getSourceValue = function(id) return sources[id] end
    getValue = function() return quality end
    model = {getInfo = function() return {name = "Model/1"} end}
    fstat = function(path)
        if fs[path] ~= nil then return {size = #fs[path]} end
    end
    lcd = {
        getColor = function() return 0x07e08000 end,
        drawText = function() end,
    }
    crossfireTelemetryPush = function(kind, payload)
        equal(kind, 0x32)
        assert(#payload <= 59, "CRSF frame too large")
        for _, value in ipairs(payload) do assert(value >= 0 and value <= 255 and value % 1 == 0) end
        frames[#frames + 1] = {payload = payload, blocked = blocked}
        return not blocked
    end
    lvgl = {
        FLOW_ROW = 1, FLOW_COLUMN = 2,
        SCROLL_OFF = 0, SCROLL_VER = 2,
        SW_SWITCH = 1, SW_TRIM = 2, SW_LOGICAL_SWITCH = 4, SW_CLEAR = 8, SW_VIRTUAL = 16,
        clear = function() definitions = {} end,
        build = function(parent, items)
            if not items then items, parent = parent, nil end
            equal(#items, 1, "More than one LVGL object per build")
            assert(not items[1].children, "Recursive native LVGL construction")
            objectCount = objectCount + 1
            createdTypes[#createdTypes + 1] = items[1].type
            local target = definitions
            if parent then
                parent.definition.children = parent.definition.children or {}
                target = parent.definition.children
            end
            target[#target + 1] = items[1]
            return collect(items)
        end,
        page = function(params)
            objectCount = objectCount + 1
            createdTypes[#createdTypes + 1] = "page"
            return {definition = {children = definitions}, params = params}
        end,
        isFullScreen = function() return full end,
        isAppMode = function() return false end,
        exitFullScreen = function() full = false end,
        confirm = function(dialog) dialogs[#dialogs + 1] = dialog end,
    }
end

local config = assert(loadfile(root .. "config.lua"))()
local storage = assert(loadfile(root .. "storage.lua"))(config)
local crsf = assert(loadfile(root .. "crsf.lua"))()

local function finish(job, step)
    for _ = 1, 20000 do
        if job.done then return job end
        step(job)
    end
    error("Job did not finish")
end

local function appInstance(path)
    return assert(loadfile(root .. "app.lua"))({dir = root, path = path or "model"})
end

local function advance(app, count)
    for _ = 1, count or 1 do now = now + 1; app.tick() end
end

local function ready(app)
    for _ = 1, 20000 do
        if app.phase == "ready" or app.phase == "error" then return end
        advance(app)
    end

    error("App did not initialize")
end

local function commit(app, ...)
    local job = app.commit(...)
    if not job then return end
    finish(job, function() advance(app) end)
    return job.success, job.error
end

local function render(app, view)
    for _ = 1, 20000 do
        advance(app)
        local before = objectCount
        app.ui.refresh(view)
        assert(objectCount - before <= 4, "More than four LVGL constructor calls per refresh")
        if not view.buildJob and view.uiReady and not view.pending then
            app.ui.refresh(view)
            return
        end
    end
    error("UI construction did not finish")
end

local function configure(sender, data, values)
    crsf.header(sender, data.header)
    local tabs = {}
    for _, tab in ipairs(data.tabs) do tabs[tab.id] = tab end
    for _, control in ipairs(data.controls) do
        crsf.addControl(sender, control, config.address(control, tabs[control.tab]), values[control.id] or 0)
    end
end

local function save(app)
    app.save()
    for _ = 1, 20000 do
        if not app.saveJob then return end
        advance(app)
    end
    error("Save did not finish")
end

local function settleAutosave(app)
    for _ = 1, 2000 do
        advance(app)
        if not app.prepare and not app.saveJob and (not app.dirty or app.error) then return end
    end
    error("Automatic save did not finish")
end

local function find(predicate, items)
    for _, item in ipairs(items or definitions) do
        local visible = item.visible == nil or item.visible == true or item.visible == 1
            or type(item.visible) == "function" and item.visible()
        if visible then
            if predicate(item) then return item end
            local child = item.children and find(predicate, item.children)
            if child then return child end
        end
    end
end

local function press(text)
    local item = assert(find(function(item) return item.type == "button" and item.text == text end),
                        "Button not found: " .. text)
    assert(not item.active or item.active(), "Button inactive: " .. text)
    return item.press()
end

local function form(caption)
    local item = assert(find(function(item)
        return item.type == "box" and item.children and item.children[1].type == "label"
            and item.children[1].text == caption
    end), "Setting not found: " .. caption)
    return item.children[2]
end

local tests = {}
local function test(name, body) tests[#tests + 1] = {name, body} end

test("Incremental Lua roundtrip, escaped strings and signed colors", function()
    local data = config.defaults()
    data.controls[1].name = 'Licht "vorne" \\ hinten'
    data.controls[1].color = -134184960
    local job = storage.save("config.a.lua", data, 7)
    storage.stepSave(job)
    equal(fs["config.a.lua"], "return {\n")
    equal(writeCount, 1)
    finish(job, storage.stepSave)
    assert(not job.error, job.error)
    local chunk = assert(load(fs["config.a.lua"], "configuration", "t", {}))
    local records = chunk()
    equal(#records, 10)
    equal(records[1].generation, 7)
    equal(data.header.generation, 0)
    local loaded = finish(storage.load("config.a.lua"), storage.stepLoad)
    assert(loaded.result, loaded.error)
    equal(loaded.result.controls[1].name, data.controls[1].name)
    equal(loaded.result.controls[1].color, data.controls[1].color)
    assert(readCount > 1)
end)

test("Incomplete, executable and oversized records fail explicitly", function()
    fs.bad = "return {\n"
    contains(finish(storage.load("bad"), storage.stepLoad).error, "Incomplete")
    fs.bad = 'return {\n{kind="config",name=os.execute("false")},\n}\n'
    assert(finish(storage.load("bad"), storage.stepLoad).error)
    fs.bad = "return {\n" .. string.rep("x", 3000)
    contains(finish(storage.load("bad"), storage.stepLoad).error, "exceeds")
    fs.bad = "return {\n}\nextra\n"
    contains(finish(storage.load("bad"), storage.stepLoad).error, "Data after")
end)

test("Inherited addresses and output collisions are validated", function()
    local data = config.defaults()
    data.tabs[1].address = 23
    equal(config.address(data.controls[1], data.tabs[1]), 23)
    data.controls[1].address = 44
    equal(config.address(data.controls[1], data.tabs[1]), 44)
    data.controls[2].address, data.controls[2].output = 44, 1
    local _, err = config.validate(data)
    contains(err, "already assigned")
    data.controls[2].output = 2
    assert(config.validate(data))
    data.controls[2].tab = 99
    _, err = config.validate(data)
    contains(err, "unknown tab")
end)

test("Set4 uses documented high/low bytes and output numbering", function()
    local data, sender = config.defaults(), crsf.new()
    data.controls[6].type = 3
    configure(sender, data, {[1] = 1, [6] = 2}, config)
    crsf.tick(sender, 1)
    equal(encode(frames[1].payload), "0,234,161,7,0,8,1")
end)

test("Set4M splits more than eighteen addresses without starvation", function()
    local data, sender = config.defaults(), crsf.new()
    data.controls = {}
    for i = 1, 37 do
        local control = config.newControl(i, 1, 1)
        control.address = i - 1
        data.controls[i] = control
    end
    configure(sender, data, {}, config)
    for t = 1, 3 do crsf.tick(sender, t) end
    equal(frames[1].payload[4], 0x09)
    equal(frames[1].payload[5], 18)
    equal(#frames[1].payload, 59)
    equal(frames[2].payload[5], 18)
    equal(encode(frames[3].payload), "0,234,161,7,36,0,0")
end)

test("Full CRSF FIFO retries; PWM rounds and uses configured output", function()
    local data, sender = config.defaults(), crsf.new()
    data.controls[3].type = 5
    configure(sender, data, {}, config)
    blocked = true
    crsf.tick(sender, 1)
    contains(sender.error, "busy")
    blocked = false
    crsf.tick(sender, 2)
    equal(encode(frames[1].payload), encode(frames[2].payload))
    crsf.set(sender, 3, 50)
    crsf.tick(sender, 3)
    equal(encode(frames[3].payload), "0,234,161,2,0,2,50")
    equal(sender.error, nil)
end)

test("LED colors use RGB444 and can be requeued", function()
    local data, sender = config.defaults(), crsf.new()
    data.controls = {data.controls[1], data.controls[2]}
    data.header.sendColors = 1
    data.controls[1].color, data.controls[2].color = 0xf8008000, 0x001f8000
    configure(sender, data, {}, config)
    crsf.tick(sender, 1)
    crsf.tick(sender, 2)
    equal(encode(frames[2].payload), "0,234,161,10,0,2,15,0,16,15")
    crsf.colors(sender)
    crsf.tick(sender, 3)
    equal(frames[3].payload[4], 0x0a)
end)

test("Inactive CRSF protocol is not reported as a full queue or accepted as sent", function()
    local sender = crsf.new()
    configure(sender, config.defaults(), {[1] = 1}, config)
    local push = crossfireTelemetryPush
    crossfireTelemetryPush = function() return nil end
    crsf.tick(sender, 1)
    equal(sender.error, "CRSF inactive: select a CRSF/ELRS RF module")
    equal(sender.groups[1].dirty, true)
    equal(sender.groups[1].last, -100000)
    equal(#frames, 0)
    crossfireTelemetryPush = push
    crsf.tick(sender, 2)
    equal(sender.error, nil)
    equal(sender.groups[1].dirty, false)
    equal(encode(frames[1].payload), "0,234,161,7,0,0,1")
end)

test("Simulator serial Set4 frame matches documented command and frame CRCs", function()
    getVersion = function() return "3.0.0", "tx16s-simu" end
    local written = {}
    serialWrite = function(data) written[#written + 1] = data end
    local native = function() error("Simulator must not use native CRSF") end
    crossfireTelemetryPush = native
    local sender, data = crsf.new(), config.defaults()
    data.controls[6].type = 3
    configure(sender, data, {[1] = 1, [6] = 2}, config)
    crsf.tick(sender, 1)
    equal(#written, 1)
    local bytes = {string.byte(written[1], 1, #written[1])}
    equal(encode(bytes), "200,10,50,0,234,161,7,0,8,1,0,240")
    equal(sender.error, nil)
    equal(sender.groups[1].dirty, false)
    contains(sender.notice, "delivery unconfirmed")
    equal(crossfireTelemetryPush, native)
    local app = appInstance()
    ready(app)
    advance(app)
    settleAutosave(app)
    contains(app.status(), "Simulator: serial CRSF")
end)

test("Simulator serial Prop and RGB frames match the protocol examples", function()
    getVersion = function() return "3.0.0", "tx16s-simu" end
    local written = {}
    serialWrite = function(data) written[#written + 1] = data end
    crossfireTelemetryPush = nil
    local sender, data = crsf.new(), config.defaults()
    data.controls = {data.controls[3]}
    data.controls[1].type = 5
    configure(sender, data, {[3] = 50}, config)
    crsf.tick(sender, 1)
    crsf.tick(sender, 2)
    equal(encode({string.byte(written[2], 1, #written[2])}), "200,10,50,0,234,161,2,0,2,50,30,54")
    sender, data, written = crsf.new(), config.defaults(), {}
    data.tabs[1].address, data.header.sendColors = 8, 1
    data.controls = {data.controls[1], data.controls[2]}
    data.controls[1].color, data.controls[2].color = 0xf8008000, 0x001f8000
    configure(sender, data, {}, config)
    crsf.tick(sender, 1)
    crsf.tick(sender, 2)
    equal(encode({string.byte(written[2], 1, #written[2])}), "200,13,50,0,234,161,10,8,2,15,0,16,15,90,147")
end)

test("Missing simulator serial API leaves packets pending without using native CRSF", function()
    getVersion = function() return "3.0.0", "tx16s-simu" end
    local sender = crsf.new()
    configure(sender, config.defaults(), {}, config)
    crsf.tick(sender, 1)
    equal(sender.error, "Simulator serialWrite API unavailable")
    equal(sender.groups[1].dirty, true)
    equal(#frames, 0)
end)

test("Hardware CRSF does not switch to serial when native CRSF is inactive", function()
    serialWrite = function() error("Hardware must not use serial simulator transport") end
    crossfireTelemetryPush = function() return nil end
    local sender = crsf.new()
    configure(sender, config.defaults(), {}, config)
    crsf.tick(sender, 1)
    equal(sender.error, "CRSF inactive: select a CRSF/ELRS RF module")
    equal(sender.notice, nil)
    equal(sender.groups[1].dirty, true)
end)

test("Remapped and deleted outputs are explicitly switched off", function()
    local data, sender = config.defaults(), crsf.new()
    data.controls = {data.controls[1]}
    data.controls[1].type = 5
    configure(sender, data, {[1] = 80}, config)
    crsf.tick(sender, 1)
    crsf.tick(sender, 2)
    data.controls = {}
    local previous = sender
    sender = crsf.new()
    configure(sender, data, {}, config)
    crsf.retireGroup(sender, previous, previous.groups[1])
    crsf.retireProp(sender, previous, previous.props[1])
    crsf.tick(sender, 3)
    crsf.tick(sender, 4)
    local off, pwmOff = false, false
    for i = 3, #frames do
        off = off or encode(frames[i].payload) == "0,234,161,7,0,0,0"
        pwmOff = pwmOff or encode(frames[i].payload) == "0,234,161,2,0,0,0"
    end
    assert(off and pwmOff)
    equal(#sender.groups, 0)
    equal(#sender.props, 0)
end)

test("Physical controls, negative switches, source and activation work across tabs", function()
    local app = appInstance()
    ready(app)
    local tab = app.newTab()
    assert(commit(app, "tab", tab))
    local control = app.newControl(tab)
    control.switch, control.switch2, control.type = -10, 11, 3
    assert(commit(app, "control", control))
    switches[11] = true
    advance(app, 3)
    equal(app.values[control.id], 2)
    switches[-10] = true
    advance(app, 3)
    equal(app.values[control.id], 1)
    control = config.copy(control)
    control.activation = 12
    assert(commit(app, "control", control))
    advance(app, 3)
    equal(app.values[control.id], 0)
    switches[12] = true
    advance(app, 3)
    equal(app.values[control.id], 1)
    control = config.copy(app.data.controls[1])
    control.type, control.source = 5, 9
    sources[9] = 512
    assert(commit(app, "control", control))
    advance(app, 3)
    equal(app.values[control.id], 50)
    sources[9] = -1024
    advance(app, 3)
    equal(app.values[control.id], 0)
    sources[9] = 2048
    advance(app, 3)
    equal(app.values[control.id], 100)
    sources[9] = nil
    advance(app, 3)
    equal(app.values[control.id], 0)
    contains(app.error, "Source unavailable")
end)

test("Mutex groups do not oscillate while physical switches stay on", function()
    local app = appInstance()
    ready(app)
    for i = 1, 2 do
        local control = config.copy(app.controls[i])
        control.group, control.switch = 1, i
        assert(commit(app, "control", control))
    end
    switches[1], switches[2] = true, true
    advance(app, 5)
    equal(app.values[1], 0)
    equal(app.values[2], 1)
    advance(app, 5)
    equal(app.values[1], 0)
    equal(app.values[2], 1)
end)

test("Old headers without Auto-Save remain readable and do not enable saving", function()
    local data = config.defaults()
    data.header.autoSave = nil
    finish(storage.save("model.a.lua", data, 1), storage.stepSave)
    local writes = writeCount
    local app = appInstance()
    ready(app)
    equal(app.phase, "ready")
    equal(app.data.header.autoSave, 0)
    local header = config.copy(app.data.header)
    header.name = "Manual changes"
    assert(commit(app, "config", header))
    advance(app, 100)
    equal(writeCount, writes)
    assert(app.dirty)
    header.autoSave = 2
    assert(not commit(app, "config", header))
    contains(app.error, "Invalid config.autoSave")
end)

test("Global Auto-Save persists applied changes, not drafts or runtime switches", function()
    local data = config.defaults()
    data.header.autoSave = 0
    finish(storage.save("model.a.lua", data, 0), storage.stepSave)
    local app = appInstance()
    ready(app)
    local initialWrites = writeCount
    local view = {zone = {w = 480, h = 272}, app = app, page = "control"}
    render(app, view)
    press("Setup")
    render(app, view)
    press("Global")
    render(app, view)
    local setting = assert(find(function(item)
        return item.type == "box" and item.children and item.children[1].text == "Auto-Save:"
    end))
    setting.children[2].set(1)
    advance(app, 2)
    equal(app.data.header.autoSave, 0)
    equal(writeCount, initialWrites)
    press("Apply")
    equal(writeCount, initialWrites)
    settleAutosave(app)
    assert(not app.error, app.error)
    equal(app.dirty, false)
    equal(app.generation, 1)
    local fresh = appInstance()
    ready(fresh)
    equal(fresh.data.header.autoSave, 1)
    local writes = writeCount
    app.set(1, 1)
    advance(app, 100)
    equal(writeCount, writes)
    local tab = app.newTab()
    assert(commit(app, "tab", tab))
    local back, page = nil, lvgl.page
    lvgl.page = function(params) back = params.back; return page(params) end
    render(app, view)
    back()
    equal(full, false)
    equal(#dialogs, 0)
    settleAutosave(app)
    equal(app.generation, 2)
    fresh = appInstance()
    ready(fresh)
    equal(#fresh.data.tabs, 2)
end)

test("Auto-Save follows concurrent edits with a new immutable snapshot", function()
    local app = appInstance()
    ready(app)
    settleAutosave(app)
    local header = config.copy(app.data.header)
    header.autoSave, header.name = 1, "First snapshot"
    assert(commit(app, "config", header))
    advance(app, 2)
    assert(app.saveJob)
    header = config.copy(app.data.header)
    header.name = "Latest snapshot"
    assert(commit(app, "config", header))
    settleAutosave(app)
    equal(app.dirty, false)
    equal(app.generation, 3)
    local first = finish(storage.load("model.b.lua"), storage.stepLoad)
    equal(first.result.header.name, "First snapshot")
    local fresh = appInstance()
    ready(fresh)
    equal(fresh.data.header.name, "Latest snapshot")
    local writes = writeCount
    advance(app, 100)
    equal(writeCount, writes)
end)

test("Disabling Auto-Save during a save is persisted once, then saving stops", function()
    local app = appInstance()
    ready(app)
    local header = config.copy(app.data.header)
    header.autoSave = 1
    assert(commit(app, "config", header))
    advance(app, 2)
    assert(app.saveJob)
    header = config.copy(app.data.header)
    header.autoSave = 0
    assert(commit(app, "config", header))
    settleAutosave(app)
    equal(app.generation, 2)
    equal(app.dirty, false)
    local fresh = appInstance()
    ready(fresh)
    equal(fresh.data.header.autoSave, 0)
    local writes = writeCount
    header = config.copy(app.data.header)
    header.name = "Manual again"
    assert(commit(app, "config", header))
    advance(app, 100)
    equal(writeCount, writes)
    assert(app.dirty)
end)

test("Auto-Save failures stay visible without retrying every background tick", function()
    local app = appInstance()
    ready(app)
    settleAutosave(app)
    local header = config.copy(app.data.header)
    header.autoSave = 1
    assert(commit(app, "config", header))
    writeFailure = true
    settleAutosave(app)
    contains(app.error, "Save failed")
    assert(app.dirty)
    local writes = writeCount
    advance(app, 100)
    equal(writeCount, writes)
    contains(app.error, "Save failed")
    writeFailure = false
    save(app)
    assert(not app.error, app.error)
    equal(app.dirty, false)
    local control = config.copy(app.controls[1])
    control.name = "Changed control"
    assert(commit(app, "control", control))
    settleAutosave(app)
    equal(app.dirty, false)
    equal(app.generation, 3)
end)

test("Latest complete generation wins and truncated saves recover previous slot", function()
    local app = appInstance()
    ready(app)
    save(app)
    assert(not app.error, app.error)
    equal(app.slot, "a")
    local header = config.copy(app.data.header)
    header.name = "Generation two"
    assert(commit(app, "config", header))
    save(app)
    equal(app.slot, "b")
    local fresh = appInstance()
    ready(fresh)
    equal(fresh.data.header.name, "Generation two")
    equal(fresh.generation, 2)
    fs["model.b.lua"] = string.sub(fs["model.b.lua"], 1, -4)
    fresh = appInstance()
    ready(fresh)
    equal(fresh.slot, "a")
    contains(fresh.warning, "Recovered")
    equal(fresh.data.header.name, "MultiSwitch NG")
end)

test("EdgeTX generic file errors for missing slots are not recovery warnings", function()
    local open = io.open
    io.open = function(path, mode)
        if mode == "r" and fs[path] == nil then return nil, path .. ": file error", 0 end
        return open(path, mode)
    end
    local app = appInstance()
    ready(app)
    equal(app.warning, nil)
    equal(app.dirty, true)
    save(app)
    assert(not app.error, app.error)
    equal(app.slot, "a")
    equal(fs["model.b.lua"], nil)
    local fresh = appInstance()
    ready(fresh)
    equal(fresh.phase, "ready")
    equal(fresh.warning, nil)
    equal(fresh.slot, "a")
end)

test("An existing but unreadable backup still produces a warning", function()
    local app = appInstance()
    ready(app)
    save(app)
    fs["model.b.lua"] = "unreadable contents"
    local open = io.open
    io.open = function(path, mode)
        if path == "model.b.lua" and mode == "r" then return nil, path .. ": file error", 0 end
        return open(path, mode)
    end
    local fresh = appInstance()
    ready(fresh)
    equal(fresh.phase, "ready")
    equal(fresh.slot, "a")
    contains(fresh.warning, "other slot: model.b.lua: file error")
end)

test("Write and close-time truncation fail; edits during saving remain dirty", function()
    local app = appInstance()
    ready(app)
    writeFailure = true
    save(app)
    contains(app.error, "SD full")
    assert(app.dirty)
    writeFailure, truncate = false, true
    save(app)
    contains(app.error, "Save failed")
    equal(app.generation, 0)
    truncate = false
    app.save()
    advance(app, 2)
    local header = config.copy(app.data.header)
    header.name = "Changed during saving"
    assert(commit(app, "config", header))
    for _ = 1, 500 do if not app.saveJob then break end; advance(app) end
    assert(not app.error, app.error)
    assert(app.dirty)
    local fresh = appInstance()
    ready(fresh)
    equal(fresh.data.header.name, "MultiSwitch NG")
end)

test("All corrupt files stop instead of overwriting with defaults", function()
    fs["model.a.lua"], fs["model.b.lua"] = "broken", "return {\n"
    local app = appInstance()
    ready(app)
    equal(app.phase, "error")
    contains(app.error, "Cannot load")
    equal(writeCount, 0)
end)

test("Closing during a save queues the latest applied changes", function()
    local app = appInstance()
    ready(app)
    app.save()
    advance(app, 2)
    local header = config.copy(app.data.header)
    header.name = "Save again"
    assert(commit(app, "config", header))
    app.save()
    for _ = 1, 1000 do if not app.saveJob then break end; advance(app) end
    assert(not app.error, app.error)
    equal(app.dirty, false)
    equal(app.generation, 2)
    local fresh = appInstance()
    ready(fresh)
    equal(fresh.data.header.name, "Save again")
end)

test("Readback compares contents, not only the generation", function()
    local data = config.defaults()
    finish(storage.save("config", data, 1), storage.stepSave)
    fs.config = string.gsub(fs.config, 'name="MultiSwitch NG"', 'name="Wrong contents"')
    local verified = finish(storage.load("config", data, 1), storage.stepLoad)
    contains(verified.error, "Saved value differs")
end)

test("Periodic refresh, reconnect colors and unavailable CRSF stay explicit", function()
    local app = appInstance()
    ready(app)
    local header = config.copy(app.data.header)
    header.sendColors, header.interval = 1, 10
    assert(commit(app, "config", header))
    advance(app, 3)
    frames = {}
    advance(app, 11)
    assert(#frames > 0)
    frames = {}
    quality = 100
    advance(app, 3)
    assert(find(function(item) return item.payload[4] == 0x0a end, frames))
    settleAutosave(app)
    crossfireTelemetryPush = nil
    advance(app)
    contains(app.status(), "CRSF API unavailable")
end)

test("Control setup actions collapse without changing switches and reset on fullscreen exit", function()
    local app = appInstance()
    ready(app)
    local view = {zone = {w = 480, h = 272}, app = app, page = "control"}
    render(app, view)
    local function visible(text)
        return find(function(item) return item.type == "button" and item.text == text end) ~= nil
    end
    assert(visible("Setup"))
    assert(find(function(item) return item.type == "hline" end))
    local setupIndex
    for index, item in ipairs(definitions) do
        if item.type == "button" and item.text == "Setup" then setupIndex = index end
    end
    assert(setupIndex, "Setup must be attached directly to the page, not an extra scrolling box")
    equal(definitions[setupIndex - 1].type, "hline")
    equal(definitions[setupIndex - 1].h, 1)
    for _, text in ipairs({"Tab settings", "New tab", "Global", "Save"}) do assert(not visible(text)) end
    equal(press("Output 1"), 1)
    local revision = app.revision
    press("Setup")
    render(app, view)
    assert(visible("Hide setup"))
    for _, text in ipairs({"Tab settings", "New tab", "Global", "Save"}) do assert(visible(text)) end
    equal(app.values[1], 1)
    equal(app.revision, revision)
    press("Hide setup")
    render(app, view)
    for _, text in ipairs({"Tab settings", "New tab", "Global", "Save"}) do assert(not visible(text)) end
    equal(app.values[1], 1)
    press("Setup")
    render(app, view)
    full = false
    render(app, view)
    full = true
    render(app, view)
    assert(visible("Setup"))
    assert(not visible("Hide setup"))
    assert(not visible("Tab settings"))
end)

test("Tabbed UI supports create, edit, move, delete and checked updates", function()
    local app = appInstance()
    ready(app)
    local view = {zone = {w = 480, h = 272}, app = app, page = "control"}
    render(app, view)
    equal(press("Output 1"), 1)
    render(app, view)
    equal(view.refs.c1.definition.checked, true)
    press("Setup")
    render(app, view)
    press("New tab")
    render(app, view)
    view.edit.name = "Lights"
    press("Apply")
    render(app, view)
    equal(#app.data.tabs, 2)
    equal(view.tab, 2)
    press("Add control")
    render(app, view)
    assert(not find(function(item) return item.type == "label" and item.text == "Tab:" end))
    view.edit.type = 5
    view.edit.address = 2
    press("Apply")
    render(app, view)
    equal(#app.data.controls, 9)
    press("Edit")
    render(app, view)
    press("Move")
    render(app, view)
    press("Move")
    render(app, view)
    equal(app.controls[9].tab, 1)
    equal(app.controls[9].address, 2)
    equal(view.tab, 1)
    view.tab, view.renderRevision = 2, nil
    render(app, view)
    press("Edit tab")
    render(app, view)
    press("Delete tab")
    dialogs[#dialogs].confirm()
    render(app, view)
    equal(#app.data.tabs, 1)
    equal(#app.data.controls, 9)
end)

test("Move action previews inherited address, cancels, and preserves element identity", function()
    local app = appInstance()
    ready(app)
    local tab = app.newTab()
    assert(commit(app, "tab", tab))
    local view = {zone = {w = 480, h = 272}, app = app, tab = 1, page = "tab"}
    render(app, view)
    press("Edit")
    render(app, view)
    press("Move")
    render(app, view)
    equal(view.page, "move")
    local preview = assert(find(function(item) return item.type == "label" and type(item.text) == "function" end))
    contains(preview.text(), "Inherited address: 0 -> 1")
    equal(app.controls[1].tab, 1)
    press("Cancel")
    render(app, view)
    equal(view.page, "editor")
    equal(app.controls[1].tab, 1)
    press("Move")
    render(app, view)
    press("Move")
    render(app, view)
    equal(view.tab, tab.id)
    equal(app.controls[1].tab, tab.id)
    equal(app.controls[1].address, -1)
    equal(app.controls[1].output, 1)
    equal(app.controls[1].name, "Output 1")
    equal(app.config.address(app.controls[1], app.tabs[tab.id]), 1)
end)

test("Move rejects output conflicts and stale shared-view changes", function()
    local app = appInstance()
    ready(app)
    local tab = app.newTab()
    assert(commit(app, "tab", tab))
    local other = app.newControl(tab)
    assert(commit(app, "control", other))
    local view = {zone = {w = 480, h = 272}, app = app, tab = 1, page = "tab"}
    render(app, view)
    press("Edit")
    render(app, view)
    press("Move")
    render(app, view)
    press("Move")
    render(app, view)
    contains(app.error, "already assigned")
    equal(view.page, "move")
    equal(app.controls[1].tab, 1)
    press("Cancel")
    render(app, view)
    press("Move")
    render(app, view)
    local header = config.copy(app.data.header)
    header.name = "Changed elsewhere"
    assert(commit(app, "config", header))
    render(app, view)
    press("Move")
    contains(app.error, "another view")
    equal(app.controls[1].tab, 1)
end)

test("Momentary releases on navigation and leaving fullscreen; small view is passive", function()
    local app = appInstance()
    ready(app)
    local view = {zone = {w = 200, h = 100}, app = app, page = "control"}
    render(app, view)
    equal(press("Output 1"), 1)
    press("Setup")
    render(app, view)
    local control = config.copy(app.controls[1])
    control.type = 4
    assert(commit(app, "control", control))
    render(app, view)
    equal(app.values[1], 0)
    local momentary = assert(find(function(item) return item.type == "momentaryButton" end))
    momentary.press()
    equal(app.values[1], 1)
    momentary.release()
    equal(app.values[1], 0)
    momentary.press()
    press("Tab settings")
    equal(app.values[1], 0)
    render(app, view)
    press("Control")
    render(app, view)
    momentary = assert(find(function(item) return item.type == "momentaryButton" end))
    momentary.press()
    full = false
    render(app, view)
    equal(app.values[1], 0)
    assert(not find(function(item) return item.type == "button" end))
end)

test("Missing simulator model identity waits and retries without loading or writing", function()
    local main = assert(loadfile(root .. "main.lua"))()
    model.getInfo = function() return {} end
    local a = main.create({w = 480, h = 272}, {}, root)
    local b = main.create({w = 480, h = 272}, {}, root)
    equal(a.app.phase, "identity")
    contains(a.app.error, "Waiting for model")
    main.refresh(a)
    equal(loads, 0)
    equal(writeCount, 0)
    model.getInfo = function() return {filename = "", name = ""} end
    main.background(a)
    equal(a.app.phase, "identity")
    model.getInfo = function() return nil end
    main.background(a)
    equal(a.app.phase, "identity")
    model.getInfo = function() return {filename = "model1.yml"} end
    for _ = 1, 200 do now = now + 1; main.background(a); main.background(b) end
    equal(a.app, b.app)
    equal(a.app.phase, "ready")
    equal(a.app.path, root .. "model_6d6f64656c312e796d6c")
end)

test("Empty model filename falls back to the model name", function()
    local main = assert(loadfile(root .. "main.lua"))()
    model.getInfo = function() return {filename = "", name = "Model/1"} end
    local view = main.create({w = 480, h = 272}, {}, root)
    equal(view.app.path, root .. "model_4d6f64656c2f31")
end)

test("Shared instances run one scheduler per tick and detect stale editors", function()
    local main = assert(loadfile(root .. "main.lua"))()
    equal(#main.options, 0)
    local a = main.create({w = 480, h = 272}, {}, root)
    local b = main.create({w = 480, h = 272}, {}, root)
    equal(a.app, b.app)
    for _ = 1, 200 do now = now + 1; main.background(a); main.background(b) end
    equal(a.app.phase, "ready")
    local app = a.app
    render(app, a)
    press("Setup")
    render(app, a)
    press("Global")
    render(app, a)
    local header = config.copy(app.data.header)
    header.name = "Other view"
    assert(commit(app, "config", header))
    render(app, a)
    press("Apply")
    contains(app.error, "another view")
    equal(app.data.header.name, "Other view")
    local before = #frames
    now = now + 200
    main.background(a)
    main.background(b)
    equal(#frames - before, 1)
end)

test("Large preparation is bounded and activates preserved live values atomically", function()
    local data = config.defaults()
    data.tabs, data.controls = {}, {}
    for id = 1, 4 do
        data.tabs[id] = {kind = "tab", id = id, name = "Tab " .. id,
                        address = (id - 1) * 4, columns = 2, height = 48}
    end
    for id = 1, 128 do
        local control = config.newControl(id, (id - 1) // 32 + 1, (id - 1) % 8 + 1)
        control.address = (id - 1) // 8
        data.controls[id] = control
    end
    data.controls[1].switch = 1
    data.controls[2].group, data.controls[3].group = 1, 1
    finish(storage.save("model.a.lua", data, 1), storage.stepSave)
    local app = appInstance()
    ready(app)
    switches[1] = true
    advance(app)
    equal(app.values[1], 1)
    local oldData, oldSender, revision, beforeFrames = app.data, app.sender, app.revision, #frames
    local header = config.copy(app.data.header)
    header.name = "Prepared"
    local job = assert(app.commit("config", header))
    local added = 0
    local addControl = app.crsf.addControl
    app.crsf.addControl = function(...)
        added = added + 1
        return addControl(...)
    end
    while not job.done do
        if job.phase == "controls" and job.index == 5 then app.set(2, 1) end
        if job.phase == "crsf" and job.index == 2 then
            switches[1] = false
            app.set(3, 1)
        end
        local records = #job.state.data.tabs + #job.state.data.controls
        local bindings, off, steps = added, #job.state.sender.off, job.steps
        advance(app)
        equal(job.steps - steps, 1)
        assert(#job.state.data.tabs + #job.state.data.controls - records <= 1)
        assert(added - bindings <= 1)
        assert(#job.state.sender.off - off <= 1)
        if not job.done then
            equal(app.data, oldData)
            equal(app.sender, oldSender)
            equal(app.revision, revision)
        end
    end
    assert(job.success, job.error)
    assert(#frames > beforeFrames, "Old runtime stopped transmitting during preparation")
    equal(app.revision, revision + 1)
    equal(app.data.header.name, "Prepared")
    equal(app.values[1], 0)
    equal(app.values[2], 0)
    equal(app.values[3], 1)
    equal(app.winners[1], 3)
    equal(app.sender.bindings[1].code, 0)
    equal(app.sender.bindings[3].code, 1)
    equal(app.physical[1], 0)
end)

test("Rejected and cancelled candidates do not activate or write deferred saves", function()
    local app = appInstance()
    ready(app)
    local header = config.copy(app.data.header)
    header.autoSave = 1
    assert(commit(app, "config", header))
    settleAutosave(app)
    local previous, revision, writes = app.data, app.revision, writeCount
    local control = config.copy(app.controls[2])
    control.output = 1
    local job = assert(app.commit("control", control))
    app.save()
    assert(not app.commit("config", header))
    contains(app.error, "already in progress")
    finish(job, function() advance(app) end)
    assert(not job.success)
    contains(job.error, "already assigned")
    equal(app.data, previous)
    equal(app.revision, revision)
    equal(writeCount, writes)
    equal(app.saveRequested, nil)
    header.name = "Cancelled"
    local called = 0
    job = assert(app.commit("config", header, false, function(ok)
        equal(ok, false)
        called = called + 1
    end))
    advance(app, 3)
    app.save()
    app.cancelUpdate(job)
    equal(called, 1)
    assert(job.done and not job.success)
    advance(app, 100)
    equal(app.data, previous)
    equal(writeCount, writes)
    equal(app.saveJob, nil)
    contains(app.error, "cancelled")
    control.id = 999
    job = assert(app.commit("control", control, true))
    finish(job, function() advance(app) end)
    contains(job.error, "no longer exists")
    equal(app.data, previous)
end)

test("Auto-Save waits for candidate activation and saves only the new configuration", function()
    local app = appInstance()
    ready(app)
    settleAutosave(app)
    local header = config.copy(app.data.header)
    local writes = writeCount
    header.name = "After activation"
    local job = assert(app.commit("config", header))
    app.save()
    while not job.done do
        advance(app)
        if not job.done then equal(writeCount, writes); equal(app.saveJob, nil) end
    end
    assert(job.success)
    assert(app.saveJob)
    equal(app.saveSnapshot.header.name, "After activation")
    settleAutosave(app)
    equal(app.generation, 2)
    local fresh = appInstance()
    ready(fresh)
    equal(fresh.data.header.name, "After activation")
end)

test("Retired CRSF outputs survive full queues and subsequent preparation", function()
    local app = appInstance()
    ready(app)
    local control = config.copy(app.controls[1])
    control.type = 5
    assert(commit(app, "control", control))
    app.set(1, 80)
    advance(app, 2)
    blocked = true
    control.address = 9
    assert(commit(app, "control", control))
    local pending = assert(app.sender.off[app.sender.offIndex])
    equal(encode(pending), "0,234,161,2,0,0,0")
    app.set(1, 80)
    local header = config.copy(app.data.header)
    header.destination = 55
    assert(commit(app, "config", header))
    equal(app.sender.off[1], pending)
    equal(#app.sender.off, 4)
    advance(app)
    equal(app.sender.offIndex, 1)
    equal(encode(frames[#frames].payload), encode(pending))
    blocked = false
    frames = {}
    advance(app, 4)
    equal(encode(frames[1].payload), encode(pending))
    for _, frame in ipairs(frames) do equal(frame.payload[1], 0) end
    equal(#app.sender.off, 0)
    frames = {}
    advance(app, 3)
    assert(find(function(frame)
        return encode(frame.payload) == "55,234,161,2,9,0,80"
    end, frames))
end)

test("Partial and stale LVGL controls cannot mutate values or drafts", function()
    local app = appInstance()
    ready(app)
    local tab = app.newTab()
    assert(commit(app, "tab", tab))
    local view = {zone = {w = 480, h = 272}, app = app, page = "control", tab = 1}
    local partial
    for _ = 1, 100 do
        local before = objectCount
        app.ui.refresh(view)
        assert(objectCount - before <= 4)
        partial = find(function(item) return item.text == "Output 1" end)
        if partial then break end
    end
    assert(partial and not view.uiReady)
    assert(not partial.active())
    partial.press()
    equal(app.values[1], 0)
    view.tab, view.renderRevision = tab.id, nil
    render(app, view)
    assert(not partial.active())
    partial.press()
    equal(app.values[1], 0)
    view.edit, view.editKind, view.editRevision = config.copy(app.data.header), "config", app.revision
    view.page, view.renderRevision = "editor", nil
    local field
    for _ = 1, 100 do
        app.ui.refresh(view)
        field = find(function(item) return item.type == "textEdit" end)
        if field then break end
    end
    local name = view.edit.name
    field.set("Partial")
    equal(view.edit.name, name)
    render(app, view)
    field.set("Accepted draft")
    equal(view.edit.name, "Accepted draft")
    press("Cancel")
    render(app, view)
    field.set("Stale")
    equal(view.edit.name, "Accepted draft")
end)

test("Nested LVGL objects are incremental and stale momentary releases are ignored", function()
    local app = appInstance()
    ready(app)
    local control = config.copy(app.controls[1])
    control.type = 5
    assert(commit(app, "control", control))
    control = config.copy(app.controls[2])
    control.image = "test.png"
    assert(commit(app, "control", control))
    control = config.copy(app.controls[3])
    control.type = 4
    assert(commit(app, "control", control))
    local view = {zone = {w = 480, h = 272}, app = app, page = "control"}
    render(app, view)
    assert(find(function(item) return item.type == "slider" end))
    assert(find(function(item) return item.type == "image" end))
    local old = assert(find(function(item) return item.type == "momentaryButton" end))
    old.press()
    equal(app.values[3], 1)
    view.renderRevision = nil
    app.ui.refresh(view)
    equal(app.values[3], 0)
    render(app, view)
    local current = assert(find(function(item) return item.type == "momentaryButton" end))
    current.press()
    old.release()
    equal(app.values[3], 1)
    current.release()
    equal(app.values[3], 0)
end)

test("Pending UI updates can be cancelled without losing the editor draft", function()
    local app = appInstance()
    ready(app)
    local view = {zone = {w = 480, h = 272}, app = app, page = "control"}
    render(app, view)
    press("Setup")
    render(app, view)
    press("Global")
    render(app, view)
    view.edit.name = "Keep this draft"
    press("Apply")
    local job = assert(view.pending)
    for _ = 1, 100 do
        app.ui.refresh(view)
        if view.uiReady then break end
    end
    assert(view.uiReady and app.prepare == job)
    press("Cancel update")
    assert(job.done and not job.success)
    equal(app.data.header.name, "MultiSwitch NG")
    equal(view.edit.name, "Keep this draft")
    render(app, view)
    equal(view.page, "editor")
    press("Apply")
    render(app, view)
    equal(app.data.header.name, "Keep this draft")
    equal(view.page, "control")
end)

test("Header tab navigation respects bounds and stays out of editor pages", function()
    local app = appInstance()
    ready(app)
    local view = {zone = {w = 480, h = 272}, app = app, page = "control"}
    app.ui.refresh(view)
    local partial = view.uiJob.page.params
    equal(partial.subtitle, app.tabs[1].name .. " (1/1)")
    assert(not partial.prevButton.active() and not partial.nextButton.active())
    partial.nextButton.press()
    equal(view.tab, 1)
    render(app, view)
    local header = view.uiJob.page.params
    assert(not header.prevButton.active() and not header.nextButton.active())
    header.prevButton.press()
    equal(view.tab, 1)
    assert(not find(function(item)
        return item.type == "button" and (item.text == "<" or item.text == ">"
            or item.text == app.tabs[1].name)
    end))
    press("Setup")
    render(app, view)
    press("Global")
    render(app, view)
    header = view.uiJob.page.params
    equal(header.subtitle, "editor")
    equal(header.prevButton, nil)
    equal(header.nextButton, nil)
    equal(type(header.back), "function")
end)

test("Header navigation changes tabs safely and updates their names and positions", function()
    local app = appInstance()
    ready(app)
    local tab = app.newTab()
    tab.id, tab.name = 7, "Lights"
    assert(commit(app, "tab", tab))
    tab = app.newTab()
    tab.name = "Aux"
    assert(commit(app, "tab", tab))
    local control = config.copy(app.controls[1])
    control.type = 4
    assert(commit(app, "control", control))
    local view = {zone = {w = 480, h = 272}, app = app, page = "control"}
    app.ui.refresh(view)
    local partial = view.uiJob.page.params
    assert(not partial.nextButton.active())
    partial.nextButton.press()
    equal(view.tab, 1)
    render(app, view)
    local first = view.uiJob.page.params
    equal(first.subtitle, app.tabs[1].name .. " (1/3)")
    assert(not first.prevButton.active() and first.nextButton.active())
    local momentary = assert(find(function(item) return item.type == "momentaryButton" end))
    momentary.press()
    equal(app.values[1], 1)
    first.nextButton.press()
    equal(view.tab, 7)
    equal(app.values[1], 0)
    render(app, view)
    local middle = view.uiJob.page.params
    equal(middle.subtitle, "Lights (2/3)")
    assert(middle.prevButton.active() and middle.nextButton.active())
    assert(not first.nextButton.active())
    first.nextButton.press()
    equal(view.tab, 7)
    local header = config.copy(app.data.header)
    header.name = "Preparing"
    local job = assert(app.commit("config", header))
    assert(not middle.nextButton.active())
    middle.nextButton.press()
    equal(view.tab, 7)
    app.cancelUpdate(job)
    middle.nextButton.press()
    equal(view.tab, tab.id)
    render(app, view)
    local last = view.uiJob.page.params
    equal(last.subtitle, "Aux (3/3)")
    assert(last.prevButton.active() and not last.nextButton.active())
    last.nextButton.press()
    equal(view.tab, tab.id)
    last.prevButton.press()
    render(app, view)
    equal(view.tab, 7)
    equal(view.uiJob.page.params.subtitle, "Lights (2/3)")
    view.uiJob.page.params.nextButton.press()
    render(app, view)
    last = view.uiJob.page.params
    assert(commit(app, "tab", app.tabs[tab.id], true))
    assert(not last.prevButton.active())
    last.prevButton.press()
    equal(view.tab, tab.id)
    render(app, view)
    equal(view.tab, 1)
    equal(view.uiJob.page.params.subtitle, app.tabs[1].name .. " (1/2)")
end)

test("Settings forms align fields and keep actions outside the scrolling area on different screens", function()
    local app = appInstance()
    ready(app)
    for _, screen in ipairs({
        {480, 272, 227}, {320, 240, 204}, {800, 480, 412},
    }) do
        LCD_W, LCD_H = screen[1], screen[2]
        if LCD_W == 800 then lvgl.PAGE_BODY_HEIGHT, lvgl.UI_ELEMENT_HEIGHT = 412, 48 end
        local view = {zone = {w = LCD_W, h = LCD_H}, app = app, page = "editor",
                      edit = config.copy(app.data.header), editKind = "config", editRevision = app.revision}
        render(app, view)
        local content, actions, status = view.refs.settings.definition, view.refs.actions.definition, view.refs.status.definition
        equal(view.uiJob.page.params.scrollDir, lvgl.SCROLL_OFF)
        equal(view.uiJob.page.params.flexFlow, nil)
        equal(content.scrollDir, lvgl.SCROLL_VER)
        assert(content.h > 0 and content.y + content.h < actions.y)
        assert(actions.y + actions.h <= status.y)
        assert(status.y + status.h <= screen[3])
        assert(not find(function(item) return item.text == "Apply" or item.text == "Cancel" end, content.children))
        local column, fields = nil, 0
        for _, item in ipairs(content.children) do
            if item.type == "box" and item.children and item.children[1].type == "label" then
                equal(#item.children, 2)
                local caption, input = item.children[1], item.children[2]
                if not column then column = input.x end
                equal(input.x, column)
                assert(caption.w <= input.x and input.x + input.w <= item.w)
                assert(input.y + input.h <= item.h)
                assert(item.w < content.w)
                equal(item.scrollDir, lvgl.SCROLL_OFF)
                fields = fields + 1
            end
        end
        equal(fields, 5)
    end
end)

test("Element editor sections preserve drafts and show only relevant input and image fields", function()
    local app = appInstance()
    ready(app)
    settleAutosave(app)
    local writes = writeCount
    local view = {zone = {w = 480, h = 272}, app = app, tab = 1, page = "tab"}
    render(app, view)
    press("Edit")
    render(app, view)
    local footerY = view.refs.actions.definition.y
    form("Name:").set("Draft light")
    form("Type:").set(3)
    render(app, view)
    press("Inputs")
    render(app, view)
    equal(view.refs.actions.definition.y, footerY)
    form("Switch:").set(16)
    form("Switch 2:").set(17)
    form("Activation:").set(42)
    form("Mutex group:").set(9)
    assert(not find(function(item) return item.text == "Source:" end))
    press("Appearance")
    render(app, view)
    form("Color:").set(0xf8008000)
    assert(not find(function(item) return item.text == "Image:" end))
    press("Basic")
    render(app, view)
    equal(form("Name:").value, "Draft light")
    form("Type:").set(5)
    render(app, view)
    press("Inputs")
    render(app, view)
    form("Source:").set(9)
    assert(not find(function(item)
        return item.text == "Switch:" or item.text == "Switch 2:" or item.text == "Mutex group:"
    end))
    equal(view.edit.switch2, 17)
    equal(view.edit.group, 9)
    press("Basic")
    render(app, view)
    form("Type:").set(1)
    render(app, view)
    press("Inputs")
    render(app, view)
    assert(not find(function(item) return item.text == "Switch 2:" or item.text == "Source:" end))
    equal(view.edit.source, 9)
    press("Appearance")
    render(app, view)
    equal(form("Color:").get(), 0xf8008000)
    form("Image:").set("lamp.png")
    equal(app.controls[1].name, "Output 1")
    equal(writeCount, writes)
    press("Apply")
    render(app, view)
    equal(app.controls[1].name, "Draft light")
    equal(app.controls[1].switch, 16)
    equal(app.controls[1].switch2, 17)
    equal(app.controls[1].source, 9)
    equal(app.controls[1].image, "lamp.png")
    equal(app.controls[1].color, 0xf8008000)
    equal(view.page, "tab")
end)

test("Management actions move into editors and moving retains and applies the draft", function()
    local app = appInstance()
    ready(app)
    local tab = app.newTab()
    assert(commit(app, "tab", tab))
    local view = {zone = {w = 480, h = 272}, app = app, tab = 1, page = "tab"}
    render(app, view)
    assert(not find(function(item)
        return item.text == "Move" or item.text == "Delete control" or item.text == "Delete tab"
    end))
    press("Edit")
    render(app, view)
    form("Name:").set("Moved draft")
    press("Move")
    render(app, view)
    assert(not find(function(item) return item.text == "Move" and item.type == "button" end, view.refs.settings.definition.children))
    press("Cancel")
    render(app, view)
    equal(view.page, "editor")
    equal(form("Name:").value, "Moved draft")
    equal(app.controls[1].name, "Output 1")
    press("Move")
    render(app, view)
    press("Move")
    render(app, view)
    equal(app.controls[1].tab, tab.id)
    equal(app.controls[1].name, "Moved draft")
    press("Add control")
    render(app, view)
    assert(not find(function(item) return item.text == "Move" or item.text == "Delete control" end))
    form("Name:").set("Discarded draft")
    press("Cancel")
    render(app, view)
    equal(#app.data.controls, 8)
    equal(view.page, "tab")
end)

test("Editor deletion preserves last-tab protection and rejects stale confirmations", function()
    local app = appInstance()
    ready(app)
    local view = {zone = {w = 480, h = 272}, app = app, tab = 1, page = "tab"}
    render(app, view)
    press("Edit tab")
    render(app, view)
    local delete = assert(find(function(item) return item.text == "Delete tab" end))
    assert(not delete.active())
    press("Cancel")
    render(app, view)
    press("Edit")
    render(app, view)
    press("Delete control")
    local confirmation = dialogs[#dialogs]
    local header = config.copy(app.data.header)
    header.name = "Another view"
    assert(commit(app, "config", header))
    confirmation.confirm()
    contains(app.error, "another view")
    assert(app.controls[1])
    render(app, view)
    press("Cancel")
    render(app, view)
    press("Edit")
    render(app, view)
    press("Delete control")
    dialogs[#dialogs].confirm()
    render(app, view)
    equal(app.controls[1], nil)
    equal(#app.data.controls, 7)
    equal(view.page, "tab")
    local tab = app.newTab()
    assert(commit(app, "tab", tab))
    render(app, view)
    press("Edit tab")
    render(app, view)
    press("Delete tab")
    dialogs[#dialogs].confirm()
    render(app, view)
    equal(#app.data.tabs, 1)
    equal(#app.data.controls, 0)
    equal(view.tab, tab.id)
end)

test("Tab item rows place name, effective address and edit action beside each other", function()
    local app = appInstance()
    ready(app)
    local control = config.copy(app.controls[2])
    control.name, control.address = "A long item name for the list", 255
    assert(commit(app, "control", control))
    local view = {zone = {w = 480, h = 272}, app = app, tab = 1, page = "tab"}
    render(app, view)
    for _, id in ipairs({1, 2}) do
        local control = app.controls[id]
        local row = assert(find(function(item)
            return item.type == "box" and item.children and item.children[1].text == control.name
        end))
        equal(#row.children, 3)
        local name, address, edit = row.children[1], row.children[2], row.children[3]
        equal(address.text, app.addresses[id] .. " / " .. control.output)
        equal(name.y, address.y)
        equal(address.y, edit.y)
        equal(name.h, edit.h)
        assert(name.x + name.w < address.x)
        assert(address.x + address.w < edit.x)
        assert(edit.x + edit.w <= row.w)
        equal(row.h, 40)
        equal(edit.text, "Edit")
    end
end)

test("Automatic default height fits eight buttons and puts Setup below the screen", function()
    local app = appInstance()
    ready(app)
    for _, screen in ipairs({
        {480, 272, 227, 2}, {320, 240, 204, 2}, {800, 480, 412, 3}, {480, 800, 755, 2},
    }) do
        LCD_W, LCD_H = screen[1], screen[2]
        lvgl.PAGE_BODY_HEIGHT, lvgl.PAD_OUTLINE, lvgl.UI_ELEMENT_HEIGHT = nil, nil, nil
        if LCD_W == 800 then
            lvgl.PAGE_BODY_HEIGHT, lvgl.PAD_OUTLINE, lvgl.UI_ELEMENT_HEIGHT = 412, 3, 48
        end
        local view = {zone = {w = LCD_W, h = LCD_H}, app = app, tab = 1, page = "control"}
        render(app, view)
        local cursor, rows, buttons, bottom, setup = screen[4], 0, 0, 0, false
        for _, item in ipairs(definitions) do
            if not item.visible or item.visible() then
                if item.type == "box" then
                    rows = rows + 1
                    equal(#item.children, 2)
                    for _, child in ipairs(item.children) do
                        equal(child.type, "button")
                        assert(child.h > 0)
                        equal(child.h + 2 * screen[4], item.h)
                        buttons = buttons + 1
                    end
                    bottom = cursor + item.h
                elseif item.type == "hline" then
                    assert(cursor >= screen[3], "Setup separator appears above the fold")
                elseif item.type == "button" and item.text == "Setup" then
                    assert(cursor >= screen[3], "Setup appears above the fold")
                    setup = true
                    break
                end
                cursor = cursor + item.h + screen[4]
            end
        end
        equal(rows, 4)
        equal(buttons, 8)
        equal(bottom + screen[4], screen[3])
        assert(setup)
        equal(app.tabs[1].height, 0)
    end
end)

test("New configurations automatically save defaults and subsequent applied changes", function()
    local app = appInstance()
    ready(app)
    equal(app.data.header.autoSave, 1)
    equal(app.tabs[1].height, 0)
    equal(app.newTab().height, 0)
    assert(app.dirty and app.saveJob)
    contains(app.status(), "Saving configuration")
    settleAutosave(app)
    equal(app.dirty, false)
    equal(app.generation, 1)
    contains(app.status(), "Configuration saved")
    local writes = writeCount
    app.set(1, 1)
    advance(app, 100)
    equal(writeCount, writes)
    local control = config.copy(app.controls[1])
    control.name = "Automatically saved"
    assert(commit(app, "control", control))
    settleAutosave(app)
    equal(app.dirty, false)
    equal(app.generation, 2)
    local fresh = appInstance()
    ready(fresh)
    equal(fresh.controls[1].name, "Automatically saved")
    equal(fresh.data.header.autoSave, 1)
    equal(fresh.tabs[1].height, 0)
end)

test("Existing manual height and disabled Auto-Save remain unchanged", function()
    local data = config.defaults()
    data.header.autoSave, data.tabs[1].height = 0, 48
    finish(storage.save("model.a.lua", data, 1), storage.stepSave)
    local app = appInstance()
    ready(app)
    local view = {zone = {w = 480, h = 272}, app = app, tab = 1, page = "control"}
    render(app, view)
    for id = 1, 8 do equal(view.refs["c" .. id].definition.h, 48) end
    local writes = writeCount
    local control = config.copy(app.controls[1])
    control.name = "Manual changes"
    assert(commit(app, "control", control))
    advance(app, 100)
    equal(writeCount, writes)
    equal(app.data.header.autoSave, 0)
    equal(app.tabs[1].height, 48)
    local tab = config.copy(app.tabs[1])
    tab.height = 1
    assert(not app.commit("tab", tab))
    contains(app.error, "use 0 or 30..240")
end)

test("Startup Auto-Save failures remain visible without endless retries", function()
    writeFailure = true
    local app = appInstance()
    ready(app)
    contains(app.status(), "Save failed")
    assert(app.dirty)
    equal(app.generation, 0)
    local writes = writeCount
    advance(app, 100)
    equal(writeCount, writes)
    writeFailure = false
    save(app)
    equal(app.dirty, false)
    equal(app.generation, 1)
    contains(app.status(), "Configuration saved")
end)

test("Unreadable existing slots are not overwritten by startup Auto-Save", function()
    fs["model.a.lua"], fs["model.b.lua"] = "existing A", "existing B"
    local open = io.open
    io.open = function(path, mode)
        if mode == "r" and (path == "model.a.lua" or path == "model.b.lua") then
            return nil, path .. ": read error", 5
        end
        return open(path, mode)
    end
    local app = appInstance()
    ready(app)
    equal(app.phase, "error")
    contains(app.error, "read error")
    advance(app, 100)
    equal(writeCount, 0)
    equal(fs["model.a.lua"], "existing A")
    equal(fs["model.b.lua"], "existing B")
end)

test("The standard control page builds in bounded batches within eight refreshes", function()
    local app = appInstance()
    ready(app)
    local view = {zone = {w = 480, h = 272}, app = app, page = "control"}
    local refreshes, batched = 0, false
    repeat
        local before = objectCount
        app.ui.refresh(view)
        local count = objectCount - before
        assert(count <= 4)
        if refreshes == 0 then
            equal(count, 1)
            equal(createdTypes[before + 1], "page")
        end
        if count > 1 then batched = true end
        refreshes = refreshes + 1
    until view.uiReady or refreshes == 8
    assert(view.uiReady, "Standard page did not finish within eight refreshes")
    assert(batched, "UI still builds only one object per refresh")
    for id = 1, 8 do assert(view.refs["c" .. id]) end
end)

test("Nested images and page frames have exclusive refreshes without losing deferred images", function()
    local data = config.defaults()
    data.controls[1].type = 5
    data.controls[2].image, data.controls[3].image = "first.png", "second.png"
    finish(storage.save("model.a.lua", data, 1), storage.stepSave)
    local app = appInstance()
    ready(app)
    local view = {zone = {w = 480, h = 272}, app = app, page = "control"}
    local images = 0
    for _ = 1, 30 do
        local before = objectCount
        app.ui.refresh(view)
        local count = objectCount - before
        assert(count <= 4)
        for index = before + 1, objectCount do
            local kind = createdTypes[index]
            if kind == "page" or kind == "image" then
                equal(count, 1, "Heavy constructor shared a refresh with another object")
            end
            if kind == "image" then images = images + 1 end
        end
        if view.uiReady then break end
    end
    assert(view.uiReady)
    equal(images, 2)
    equal(view.refs.c2.definition.children[1].file, "/IMAGES/first.png")
    equal(view.refs.c3.definition.children[1].file, "/IMAGES/second.png")
end)

test("Move targets batch empty transitions while respecting the sixteen-step budget", function()
    local data = config.defaults()
    data.tabs = {}
    for id = 1, 128 do
        data.tabs[id] = {kind = "tab", id = id, name = "Tab " .. id,
                        address = id - 1, columns = 2, height = 0}
    end
    finish(storage.save("model.a.lua", data, 1), storage.stepSave)
    local app = appInstance()
    ready(app)
    local view = {
        zone = {w = 480, h = 272}, app = app, tab = 1, page = "move",
        moveControl = config.copy(app.controls[1]), moveRevision = app.revision, moveAddress = 0,
    }
    local batched = false
    for _ = 1, 30 do
        local before = view.uiJob and view.uiJob.targets and #view.uiJob.targets.ids or 0
        local objects = objectCount
        app.ui.refresh(view)
        local after = view.uiJob.targets and #view.uiJob.targets.ids or 0
        local added = after - before
        assert(added <= 16, "Unbounded target preparation")
        assert(objectCount - objects <= 4)
        if added > 1 then batched = true end
        if view.uiReady then break end
    end
    assert(view.uiReady and batched)
    equal(#view.uiJob.targets.ids, 127)
    equal(view.moveTarget, 2)
end)

local failures = 0
for _, item in ipairs(tests) do
    reset()
    local ok, err = xpcall(item[2], debug.traceback)
    hostIO.write((ok and "PASS " or "FAIL ") .. item[1] .. "\n")
    if not ok then failures = failures + 1; hostIO.write(err .. "\n") end
end
io = hostIO
debug.setmetatable("", stringMetatable)
hostIO.write(string.format("%d/%d tests passed\n", #tests - failures, #tests))
os.exit(failures == 0 and 0 or 1)
