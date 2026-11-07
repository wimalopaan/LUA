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
local sportFrames, sportBlocked
COLOR_THEME_SECONDARY3, COLOR_THEME_PRIMARY3, COLOR_THEME_WARNING = 3, 4, 5
LCD_W, LCD_H = 480, 272
LEFT, VCENTER, SMLSIZE, BOLD, TINSIZE = 0, 32, 1, 2, 3
CENTER = 16

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
            elseif item.type == "toggle" then
                assert(item.min == nil and item.max == nil, "Invalid range properties on toggle")
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
    sportFrames, sportBlocked = {}, false
    io = {
        open = function(path, mode)
            if mode == "r" then
                if fs[path] == nil then return nil, "not found: " .. path, 2 end
            elseif mode == "a" then fs[path] = fs[path] or ""
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
    getGeneralSettings = function() return {language = "EN", voice = "de"} end
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
        sizeText = function(text, font)
            return #text * 8, font == TINSIZE and 12 or font == SMLSIZE and 16 or 22
        end,
    }
    crossfireTelemetryPush = function(kind, payload)
        equal(kind, 0x32)
        assert(#payload <= 59, "CRSF frame too large")
        for _, value in ipairs(payload) do assert(value >= 0 and value <= 255 and value % 1 == 0) end
        frames[#frames + 1] = {payload = payload, blocked = blocked}
        return not blocked
    end
    sportTelemetryPush = function(physicalId, primId, dataId, value)
        assert(physicalId >= 0 and physicalId <= 0x1b and physicalId % 1 == 0)
        assert(primId == 0x31 or primId == 0x10)
        assert(dataId >= 0 and dataId <= 0xffff and dataId % 1 == 0)
        assert(value >= 0 and value <= (primId == 0x31 and 0xffff or 0xffffffff) and value % 1 == 0)
        sportFrames[#sportFrames + 1] = {payload = {physicalId, primId, dataId, value}, blocked = sportBlocked}
        return not sportBlocked
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

local english = assert(loadfile(root .. "i18n.lua"))({dir = root})
local moduleContext = {t = english.t}
local config = assert(loadfile(root .. "config.lua"))(moduleContext)
local storage = assert(loadfile(root .. "storage.lua"))(config)
local outputs = assert(loadfile(root .. "outputs.lua"))(moduleContext)
moduleContext.outputs = outputs
local crsf = assert(loadfile(root .. "crsf.lua"))(moduleContext)
local sport = assert(loadfile(root .. "sport.lua"))(moduleContext)

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
    local backend = sender.protocol == 1 and sport or crsf
    backend.header(sender, data.header)
    local tabs = {}
    for _, tab in ipairs(data.tabs) do tabs[tab.id] = tab end
    for _, control in ipairs(data.controls) do
        backend.addControl(sender, control, config.address(control, tabs[control.tab]), values[control.id] or 0)
    end
end

local function offCount(sender)
    return #sender.off[0] + #sender.off[1] + #sender.off[2] + #sender.off[3]
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
        if not app.prepare and not app.saveJob and (not app.dirty or app.error or app.saveError) then return end
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
    contains(app.operationStatus(), "Source unavailable")
    equal(app.inputErrorCount, 1)
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
    settleAutosave(app)
    local header = config.copy(app.data.header)
    header.autoSave, header.name = 1, "Before disable"
    assert(commit(app, "config", header))
    advance(app, 2)
    assert(app.saveJob)
    local generation = app.saveGeneration
    header = config.copy(app.data.header)
    header.autoSave = 0
    assert(commit(app, "config", header))
    settleAutosave(app)
    equal(app.generation, generation + 1)
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
    contains(app.saveError, "Save failed")
    assert(app.dirty)
    local writes = writeCount
    advance(app, 100)
    equal(writeCount, writes)
    contains(app.saveError, "Save failed")
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
    contains(app.saveError, "SD full")
    assert(app.dirty)
    writeFailure, truncate = false, true
    save(app)
    contains(app.saveError, "Save failed")
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

test("Expanded setup footer never scrolls horizontally in either language or screen size", function()
    for _, language in ipairs({"EN", "DE"}) do
        getGeneralSettings = function() return {language = language} end
        local app = appInstance("scrollbar-" .. language)
        ready(app)
        for _, screen in ipairs({{480, 272, 227}, {320, 240, 204}, {800, 480, 412}}) do
            LCD_W, LCD_H, lvgl.PAGE_BODY_HEIGHT = screen[1], screen[2], screen[3]
            lvgl.UI_ELEMENT_HEIGHT = LCD_W == 800 and 48 or nil
            local view = {zone = {w = LCD_W, h = LCD_H}, app = app, page = "control", setupOpen = true}
            render(app, view)
            local footer = assert(find(function(item)
                return item.type == "box" and item.children
                    and item.children[1].text == app.t("Save")
            end))
            equal(footer.scrollBar, false)
            equal(footer.scrollDir, lvgl.SCROLL_OFF)
            equal(view.uiJob.page.params.scrollDir, lvgl.SCROLL_VER)
        end
    end
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

test("Changing an item to Schalter builds a native toggle without slider properties", function()
    getGeneralSettings = function() return {language = "DE"} end
    local app = appInstance()
    ready(app)
    local view = {zone = {w = 480, h = 272}, app = app, page = "editor",
                  editKind = "control", edit = config.copy(app.controls[1]), editRevision = app.revision}
    render(app, view)
    equal(form("Art:").values[2], "Schalter")
    form("Art:").set(2)
    render(app, view)
    press("Anwenden")
    render(app, view)
    press("Bedienung")
    render(app, view)
    equal(app.controls[1].type, 2)
    local toggle = assert(find(function(item) return item.type == "toggle" end))
    equal(toggle.get(), 0)
    toggle.set(1)
    equal(app.values[1], 1)
    toggle.set(0)
    equal(app.values[1], 0)
    app.set(1, 1)
    equal(toggle.get(), 1)
    equal(app.error, nil)
end)

test("Toggle appearance hides ineffective color while preserving text color and stored type-change colors", function()
    getGeneralSettings = function() return {language = "DE"} end
    local data = config.defaults()
    data.header.autoSave = 0
    data.controls[1].type, data.controls[1].color = 2, 0xf8008000
    finish(storage.save("model.a.lua", data, 1), storage.stepSave)
    local app = appInstance()
    ready(app)
    local view = {zone = {w = 480, h = 272}, app = app, page = "editor",
                  editKind = "control", edit = config.copy(app.controls[1]), editRevision = app.revision}
    render(app, view)
    press("Aussehen")
    render(app, view)
    assert(not find(function(item) return item.text == "Farbe:" end))
    form("Textfarbe:").set(0x07e08000)
    press("Allgemein")
    render(app, view)
    form("Art:").set(1)
    render(app, view)
    press("Aussehen")
    render(app, view)
    equal(form("Farbe:").get(), 0xf8008000)
    form("Farbe:").set(0x001f8000)
    press("Allgemein")
    render(app, view)
    form("Art:").set(2)
    render(app, view)
    press("Aussehen")
    render(app, view)
    assert(not find(function(item) return item.text == "Farbe:" end))
    equal(view.edit.color, 0x001f8000)
    equal(form("Textfarbe:").get(), 0x07e08000)
    press("Anwenden")
    render(app, view)
    press("Bedienung")
    render(app, view)
    local caption = assert(find(function(item)
        return item.type == "label" and item.text == app.controls[1].name
    end))
    equal(caption.color, 0x07e08000)
    save(app)
    equal(app.saveError, nil)
    local fresh = appInstance()
    ready(fresh)
    equal(fresh.controls[1].type, 2)
    equal(fresh.controls[1].color, 0x001f8000)
    equal(fresh.controls[1].textColor, 0x07e08000)
end)

test("Toggles align with centered captions while sliders and three-position labels retain their layout", function()
    local data = config.defaults()
    data.header.autoSave = 0
    data.controls = {data.controls[1], data.controls[2], data.controls[3]}
    data.controls[1].type, data.controls[2].type, data.controls[3].type = 2, 3, 5
    finish(storage.save("model.a.lua", data, 1), storage.stepSave)
    local app = appInstance()
    ready(app)
    for _, screen in ipairs({{320, 240, 42, 26}, {480, 272, 52, 32},
                            {800, 480, 78, 48}, {480, 800, 52, 32}}) do
        LCD_W, LCD_H = screen[1], screen[2]
        lvgl.UI_ELEMENT_HEIGHT = screen[4]
        local view = {zone = {w = LCD_W, h = LCD_H}, app = app, page = "control"}
        render(app, view)
        for _, control in ipairs(app.data.controls) do
            if control.type == 3 then
                local box = view.refs["c" .. control.id].definition
                equal(#box.children, 3)
                for _, item in ipairs(box.children) do equal(item.type, "button") end
                assert(not find(function(item) return item.type == "label" and item.text == control.name end, box.children))
            else
                local box = assert(find(function(item)
                    return item.type == "box" and item.children and item.children[1].text == control.name
                end))
                local caption, input = box.children[1], box.children[2]
                equal(box.flexFlow, lvgl.FLOW_COLUMN)
                equal(caption.align, CENTER)
                equal(caption.w, input.w)
                if control.type == 2 then
                    equal(input.type, "box")
                    equal(input.scrollDir, lvgl.SCROLL_OFF)
                    local toggle = input.children[1]
                    equal(toggle.type, "toggle")
                    equal(toggle.w, screen[3])
                    equal(toggle.h, screen[4])
                    equal(input.h, toggle.h)
                    equal(toggle.x, math.floor((caption.w - toggle.w) / 2))
                    equal(toggle.y, 0)
                    assert(toggle.x >= 0 and toggle.x + toggle.w <= input.w)
                else
                    equal(input.type, "slider")
                end
            end
        end
    end
end)

test("Three-position groups select stable protocol states and fit wide and narrow screens", function()
    getGeneralSettings = function() return {language = "DE"} end
    local data = config.defaults()
    data.header.autoSave = 0
    data.controls = {data.controls[1], data.controls[2], data.controls[3]}
    data.controls[1].type, data.controls[3].type = 3, 5
    data.controls[1].leftText, data.controls[1].rightText = "Save", "Inputs"
    finish(storage.save("model.a.lua", data, 1), storage.stepSave)
    local app = appInstance()
    ready(app)
    for _, screen in ipairs({{320, 240, 204, 0}, {480, 272, 227, 0},
                            {800, 480, 412, 0}, {480, 272, 227, 30}}) do
        LCD_W, LCD_H, lvgl.PAGE_BODY_HEIGHT = screen[1], screen[2], screen[3]
        lvgl.UI_ELEMENT_HEIGHT = LCD_W == 800 and 48 or nil
        local tab = config.copy(app.tabs[1])
        tab.height = screen[4]
        assert(commit(app, "tab", tab))
        app.set(1, 0)
        local view = {zone = {w = LCD_W, h = LCD_H}, app = app, page = "control"}
        render(app, view)
        local group = view.refs.c1.definition
        equal(#group.children, 3)
        equal(group.w, view.refs.c2.definition.w)
        equal(group.h, view.refs.c2.definition.h)
        local expected = {"Save", "Aus", "Inputs"}
        local right = 0
        for index, position in ipairs({2, 0, 1}) do
            local button = group.children[index]
            equal(button, view.refs["c1p" .. position].definition)
            equal(button.text, expected[index])
            equal(button.checked, position == 0)
            equal(button.x, right + (index > 1 and (LCD_W == 800 and 3 or 2) or 0))
            assert(button.x + button.w <= group.w)
            equal(button.y, 0)
            equal(button.h, group.h)
            local _, fontHeight = lcd.sizeText("M", button.font)
            assert(fontHeight <= button.h)
            right = button.x + button.w
        end
        equal(right, group.w)
        local objects = objectCount
        for _, position in ipairs({2, 2, 1, 0}) do
            equal(view.refs["c1p" .. position].definition.press(), 1)
            equal(app.values[1], position)
            app.ui.refresh(view)
            for state = 0, 2 do equal(view.refs["c1p" .. state].definition.checked, state == position) end
        end
        equal(objectCount, objects)
        local slider = assert(find(function(item) return item.type == "slider" end))
        equal(slider.min, 0)
        equal(slider.max, 100)
        slider.set(73)
        equal(app.values[3], 73)
        equal(slider.get(), 73)
    end
end)

test("Three-position user labels survive editing, type changes, saving and another menu language", function()
    getGeneralSettings = function() return {language = "DE"} end
    local data = config.defaults()
    data.header.autoSave = 0
    finish(storage.save("model.a.lua", data, 1), storage.stepSave)
    local app = appInstance()
    ready(app)
    local view = {zone = {w = 480, h = 272}, app = app, page = "editor",
                  editKind = "control", edit = config.copy(app.controls[1]), editRevision = app.revision}
    render(app, view)
    assert(not find(function(item) return item.text == "Text links:" end))
    form("Art:").set(3)
    render(app, view)
    form("Text links:").set('Tür "links"')
    form("Text rechts:").set("Save")
    form("Art:").set(2)
    render(app, view)
    assert(not find(function(item) return item.text == "Text rechts:" end))
    form("Art:").set(3)
    render(app, view)
    equal(form("Text links:").value, 'Tür "links"')
    equal(form("Text rechts:").value, "Save")
    press("Anwenden")
    render(app, view)
    press("Bedienung")
    render(app, view)
    equal(view.refs.c1p2.definition.text, 'Tür "links"')
    equal(view.refs.c1p0.definition.text, "Aus")
    equal(view.refs.c1p1.definition.text, "Save")
    save(app)
    equal(app.saveError, nil)
    getGeneralSettings = function() return {language = "EN", voice = "de"} end
    local fresh = appInstance()
    ready(fresh)
    equal(fresh.controls[1].leftText, 'Tür "links"')
    equal(fresh.controls[1].rightText, "Save")
    local nextView = {zone = {w = 480, h = 272}, app = fresh, page = "control"}
    render(fresh, nextView)
    equal(nextView.refs.c1p2.definition.text, 'Tür "links"')
    equal(nextView.refs.c1p0.definition.text, "Off")
    equal(nextView.refs.c1p1.definition.text, "Save")
end)

test("Legacy controls receive missing label defaults but invalid explicit labels are rejected", function()
    getGeneralSettings = function() return {language = "DE"} end
    local data = config.defaults()
    data.header.autoSave = 0
    for _, control in ipairs(data.controls) do control.leftText, control.rightText = nil, nil end
    data.controls[1].type = 3
    data.controls[2].leftText, data.controls[2].rightText = "", "Keep"
    finish(storage.save("model.a.lua", data, 1), storage.stepSave)
    local app = appInstance()
    ready(app)
    equal(app.phase, "ready")
    equal(app.controls[1].leftText, "Links")
    equal(app.controls[1].rightText, "Rechts")
    equal(app.controls[2].leftText, "")
    equal(app.controls[2].rightText, "Keep")
    equal(app.data.header.version, 1)
    data.controls[1].leftText = 17
    finish(storage.save("invalid.a.lua", data, 1), storage.stepSave)
    local writes = writeCount
    local invalid = appInstance("invalid")
    ready(invalid)
    equal(invalid.phase, "error")
    contains(invalid.error, "control.leftText")
    equal(writeCount, writes)
end)

test("Physical three-position groups are read-only and keep their selection current beyond one poll batch", function()
    local data = config.defaults()
    data.header.autoSave = 0
    local control = config.newControl(9, 1, 1)
    control.address, control.type, control.switch2 = 1, 3, 20
    data.controls[9] = control
    finish(storage.save("model.a.lua", data, 1), storage.stepSave)
    local app = appInstance()
    ready(app)
    local view = {zone = {w = 480, h = 272}, app = app, page = "control"}
    render(app, view)
    for position = 0, 2 do
        local button = view.refs["c9p" .. position].definition
        assert(not button.active())
        equal(button.press(), 0)
        equal(app.values[9], 0)
    end
    for _, on in ipairs({true, false, true}) do
        switches[20] = on
        advance(app, 8)
        app.ui.refresh(view)
        app.ui.refresh(view)
        local selected = on and 2 or 0
        equal(app.values[9], selected)
        for position = 0, 2 do equal(view.refs["c9p" .. position].definition.checked, position == selected) end
    end
    control = config.copy(app.controls[9])
    control.switch = 10
    assert(commit(app, "control", control))
    switches[10] = true
    render(app, view)
    app.ui.refresh(view)
    equal(app.values[9], 1)
    equal(view.refs.c9p1.definition.checked, true)
    equal(view.refs.c9p2.definition.checked, false)
    assert(not view.refs.c9p1.definition.active())
end)

test("Group markers identify shared groups across tabs and preserve control layouts and interaction", function()
    local data = config.defaults()
    data.header.autoSave = 0
    data.tabs[2] = config.copy(data.tabs[1])
    data.tabs[2].id, data.tabs[2].address = 2, 1
    data.controls[1].group = 7
    data.controls[2].tab, data.controls[2].type, data.controls[2].group = 2, 2, 7
    data.controls[3].type, data.controls[3].group = 3, 8
    data.controls[4].type, data.controls[4].group = 4, 8
    data.controls[5].group = 9
    data.controls[6].type, data.controls[6].group = 5, 9
    data.controls[8].group, data.controls[8].visible = 10, 0
    data.controls[9] = config.newControl(9, 1, 1)
    data.controls[9].address, data.controls[9].group = 2, 10
    finish(storage.save("model.a.lua", data, 1), storage.stepSave)
    local app = appInstance()
    ready(app)
    for _, screen in ipairs({{320, 240, 204}, {480, 272, 227}, {800, 480, 412}}) do
        LCD_W, LCD_H, lvgl.PAGE_BODY_HEIGHT = screen[1], screen[2], screen[3]
        lvgl.UI_ELEMENT_HEIGHT = LCD_W == 800 and 48 or nil
        local view = {zone = {w = LCD_W, h = LCD_H}, app = app, page = "control", tab = 1}
        render(app, view)
        for id, group in pairs({[1] = 7, [3] = 8, [4] = 8, [9] = 10}) do
            local wrapper = view.refs["group" .. id].definition
            local content, marker = wrapper.children[1], view.refs["g" .. id].definition
            equal(marker.text, "G" .. group)
            assert(content.x + content.w <= marker.x)
            assert(marker.x + marker.w <= wrapper.w)
            assert(marker.y >= 0 and marker.y + marker.h <= wrapper.h)
            equal(wrapper.scrollDir, lvgl.SCROLL_OFF)
            equal(app.controls[id].name, data.controls[id].name)
        end
        for _, id in ipairs({2, 5, 6, 7, 8}) do equal(view.refs["g" .. id], nil) end
        view.refs.c4.definition.press()
        equal(app.values[4], 1)
        view.refs.c3p2.definition.press()
        equal(app.values[3], 2)
        equal(app.values[4], 0)
        view.refs.c4.definition.release()
        view.refs.c1.definition.press()
        equal(app.values[1], 1)
        view.tab, view.renderRevision = 2, nil
        render(app, view)
        equal(view.refs.g2.definition.text, "G7")
        local toggle = assert(find(function(item) return item.type == "toggle" end))
        toggle.set(1)
        equal(app.values[2], 1)
        equal(app.values[1], 0)
    end
end)

test("Group markers change only with applied membership, deletion and control type changes", function()
    local data = config.defaults()
    data.header.autoSave = 0
    data.controls[1].group, data.controls[2].group = 4, 4
    finish(storage.save("model.a.lua", data, 1), storage.stepSave)
    local app = appInstance()
    ready(app)
    local view = {zone = {w = 480, h = 272}, app = app, page = "control"}
    render(app, view)
    equal(view.refs.g1.definition.text, "G4")
    local counts = app.groupCounts
    local control = config.copy(app.controls[2])
    control.group = 0
    local job = assert(app.commit("control", control))
    advance(app, 5)
    equal(app.groupCounts, counts)
    equal(view.refs.g1.definition.text, "G4")
    app.cancelUpdate(job)
    equal(app.groupCounts, counts)
    assert(commit(app, "control", control))
    render(app, view)
    equal(view.refs.g1, nil)
    equal(view.refs.g2, nil)
    control.group = 4
    assert(commit(app, "control", control))
    render(app, view)
    equal(view.refs.g1.definition.text, "G4")
    control.type = 5
    assert(commit(app, "control", control))
    render(app, view)
    equal(view.refs.g1, nil)
    equal(view.refs.g2, nil)
    control.type = 1
    assert(commit(app, "control", control))
    assert(commit(app, "control", app.controls[2], true))
    render(app, view)
    equal(view.refs.g1, nil)
    equal(view.refs.g2, nil)
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

test("Compact widgets reserve up to two status lines above the bottom without overlapping logo or name", function()
    full = false
    for _, language in ipairs({"EN", "DE"}) do
        getGeneralSettings = function() return {language = language} end
        local app = appInstance("compact-" .. language)
        ready(app)
        local header = config.copy(app.data.header)
        header.name = "My switches"
        assert(commit(app, "config", header))
        app.error = "A long diagnostic\nwith another line\r\nand details"
        for _, zone in ipairs({{w = 200, h = 100}, {w = 150, h = 60}, {w = 90, h = 40}, {w = 90, h = 24}}) do
            local view = {zone = zone, app = app, page = "control"}
            render(app, view)
            local logo, title, status = definitions[1], definitions[2], definitions[3]
            equal(logo.type, "image")
            equal(logo.file, root .. "Logo_small_64_t.png")
            equal(logo.w, logo.h)
            equal(title.type, "label")
            equal(title.text(), "My switches")
            assert(title.x >= logo.x + logo.w)
            for _, item in ipairs(definitions) do
                assert(item.x >= 0 and item.y >= 0 and item.w > 0 and item.h > 0)
                assert(item.x + item.w <= zone.w and item.y + item.h <= zone.h)
            end
            if zone.h >= 40 then
                equal(#definitions, 3)
                equal(status.type, "label")
                equal(status.font, TINSIZE)
                local _, lineHeight = lcd.sizeText("M", status.font)
                equal(status.h, lineHeight * (zone.h >= 60 and 2 or 1))
                assert(status.y >= logo.y + logo.h and status.y >= title.y + title.h)
                contains(status.text(), "A long diagnostic with another line")
                assert(not string.find(status.text(), "[%c]"))
                app.saveError = "Later storage error"
                contains(status.text(), "Later storage error")
            else
                equal(#definitions, 2)
            end
            assert(not find(function(item) return item.type == "button" end))
        end
    end
end)

test("Early loading text stays inside one line before UI modules are available", function()
    full = false
    local main = assert(loadfile(root .. "main.lua"))()
    local view = main.create({w = 120, h = 45}, {}, root)
    main.refresh(view)
    equal(#definitions, 1)
    local label = definitions[1]
    equal(label.type, "label")
    local _, lineHeight = lcd.sizeText("M", label.font)
    equal(label.h, lineHeight)
    assert(label.x + label.w <= view.zone.w and label.y + label.h <= view.zone.h)
    contains(label.text(), "Loading:")
    view.app.error = "Loading failed\nextra details"
    equal(label.text(), "Loading failed extra details")
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
        if job.phase == "sender" and job.index == 2 then
            switches[1] = false
            app.set(3, 1)
        end
        local records = #job.state.data.tabs + #job.state.data.controls
        local bindings, off, steps = added, offCount(job.state.sender), job.steps
        advance(app)
        equal(job.steps - steps, 1)
        assert(#job.state.data.tabs + #job.state.data.controls - records <= 1)
        assert(added - bindings <= 1)
        assert(offCount(job.state.sender) - off <= 1)
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
    local pending = assert(app.sender.off[0][app.sender.offIndex[0]])
    equal(encode(pending.payload), "0,234,161,2,0,0,0")
    app.set(1, 80)
    local header = config.copy(app.data.header)
    header.destination = 55
    assert(commit(app, "config", header))
    equal(app.sender.off[0][1], pending)
    equal(offCount(app.sender), 4)
    advance(app)
    equal(app.sender.offIndex[0], 1)
    equal(encode(frames[#frames].payload), encode(pending.payload))
    blocked = false
    frames = {}
    advance(app, 3)
    equal(encode(frames[1].payload), encode(pending.payload))
    equal(#frames, 2)
    for _, frame in ipairs(frames) do equal(frame.payload[1], 0) end
    equal(offCount(app.sender), 0)
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
    equal(header.title, "Global widget settings")
    equal(header.subtitle, app.data.header.name)
    equal(header.prevButton, nil)
    equal(header.nextButton, nil)
    equal(type(header.back), "function")
end)

test("Settings page headers describe the page and identify its widget, tab or control", function()
    local data = config.defaults()
    data.header.name, data.header.autoSave = "Model switches", 0
    data.tabs[1].name, data.controls[1].name = "Exterior lights", "Landing light"
    data.tabs[2] = {kind = "tab", id = 2, name = "Auxiliary", address = 1, columns = 2, height = 0}
    finish(storage.save("model.a.lua", data, 1), storage.stepSave)
    local app = appInstance()
    ready(app)
    local view = {zone = {w = 480, h = 272}, app = app, tab = 1, page = "control"}
    local function header(title, subtitle)
        local params = view.uiJob.page.params
        equal(params.title, title)
        equal(params.subtitle, subtitle)
        equal(params.icon, root .. "Logo_40_inv.png")
    end
    render(app, view)
    header("Model switches", "Exterior lights (1/2)")
    press("Setup")
    render(app, view)
    press("Tab settings")
    render(app, view)
    header("Tab settings", "Exterior lights (1/2)")
    press("Edit tab")
    render(app, view)
    header("Edit tab", "Exterior lights")
    press("Cancel")
    render(app, view)
    press("Edit")
    render(app, view)
    header("Control settings", "Landing light")
    press("Move")
    render(app, view)
    header("Move control to another tab", "Landing light")
    press("Cancel")
    render(app, view)
    header("Control settings", "Landing light")
    press("Cancel")
    render(app, view)
    press("Control")
    render(app, view)
    press("Global")
    render(app, view)
    header("Global widget settings", "Model switches")
    press("Cancel")
    render(app, view)
    press("New tab")
    render(app, view)
    header("Tab settings", view.edit.name)
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

test("Tab list headers navigate safely and actions target the currently selected tab", function()
    local data = config.defaults()
    data.header.autoSave = 0
    data.tabs[2] = {kind = "tab", id = 7, name = "Lights", address = 1, columns = 2, height = 0}
    data.tabs[3] = {kind = "tab", id = 9, name = "Aux", address = 2, columns = 2, height = 0}
    data.controls[2].tab, data.controls[3].tab = 7, 9
    finish(storage.save("model.a.lua", data, 1), storage.stepSave)
    local app = appInstance()
    ready(app)
    local view = {zone = {w = 480, h = 272}, app = app, tab = 1, page = "tab"}
    app.ui.refresh(view)
    local partial = view.uiJob.page.params
    assert(not partial.prevButton.active() and not partial.nextButton.active())
    partial.nextButton.press()
    equal(view.tab, 1)
    render(app, view)
    local first = view.uiJob.page.params
    equal(first.title, "Tab settings")
    equal(first.subtitle, app.tabs[1].name .. " (1/3)")
    assert(not first.prevButton.active() and first.nextButton.active())
    assert(find(function(item) return item.text == app.controls[1].name end))
    assert(not find(function(item) return item.text == app.controls[2].name end))
    first.nextButton.press()
    render(app, view)
    equal(view.page, "tab")
    equal(view.tab, 7)
    local middle = view.uiJob.page.params
    equal(middle.subtitle, "Lights (2/3)")
    assert(middle.prevButton.active() and middle.nextButton.active())
    assert(not first.nextButton.active())
    first.nextButton.press()
    equal(view.tab, 7)
    assert(find(function(item) return item.text == app.controls[2].name end))
    assert(not find(function(item) return item.text == app.controls[1].name end))
    press("Edit tab")
    render(app, view)
    equal(view.edit.id, 7)
    equal(view.uiJob.page.params.prevButton, nil)
    equal(view.uiJob.page.params.nextButton, nil)
    press("Cancel")
    render(app, view)
    view.uiJob.page.params.nextButton.press()
    render(app, view)
    equal(view.tab, 9)
    local last = view.uiJob.page.params
    equal(last.subtitle, "Aux (3/3)")
    assert(last.prevButton.active() and not last.nextButton.active())
    last.nextButton.press()
    equal(view.tab, 9)
    press("Add control")
    render(app, view)
    equal(view.edit.tab, 9)
    equal(view.uiJob.page.params.prevButton, nil)
    equal(view.uiJob.page.params.nextButton, nil)
    press("Cancel")
    render(app, view)
    last = view.uiJob.page.params
    local header = config.copy(app.data.header)
    header.name = "Preparing"
    local job = assert(app.commit("config", header))
    assert(not last.prevButton.active())
    last.prevButton.press()
    equal(view.tab, 9)
    app.cancelUpdate(job)
    last.prevButton.press()
    render(app, view)
    equal(view.tab, 7)
    middle = view.uiJob.page.params
    assert(commit(app, "tab", app.tabs[7], true))
    assert(not middle.nextButton.active())
    middle.nextButton.press()
    equal(view.tab, 7)
    render(app, view)
    equal(view.tab, 1)
    equal(view.uiJob.page.params.subtitle, app.tabs[1].name .. " (1/2)")
    assert(commit(app, "tab", app.tabs[9], true))
    render(app, view)
    assert(not view.uiJob.page.params.prevButton.active() and not view.uiJob.page.params.nextButton.active())
end)

test("Tab list action bars align at viewport edges with separators and scrollable status below", function()
    getGeneralSettings = function() return {language = "DE"} end
    local app = appInstance()
    ready(app)
    for _, screen in ipairs({{320, 240, 204, 26}, {480, 272, 227, 32},
                            {800, 480, 412, 48}, {480, 800, 755, 32}}) do
        LCD_W, LCD_H = screen[1], screen[2]
        lvgl.PAGE_BODY_HEIGHT, lvgl.UI_ELEMENT_HEIGHT = screen[3], screen[4]
        local view = {zone = {w = LCD_W, h = LCD_H}, app = app, tab = 1, page = "tab"}
        render(app, view)
        local top, bottom = view.refs.tabActions.definition, view.refs.actions.definition
        local content = view.refs.settings.definition
        local topSeparator = view.refs.tabActionsSeparator.definition
        local statusSeparator, status = view.refs.statusSeparator.definition, view.refs.status.definition
        equal(view.uiJob.page.params.scrollDir, lvgl.SCROLL_VER)
        equal(view.uiJob.page.params.scrollBar, true)
        equal(view.uiJob.page.params.flexFlow, nil)
        equal(#top.children, 2)
        equal(#bottom.children, 2)
        equal(top.x, bottom.x)
        equal(top.w, bottom.w)
        equal(top.h, bottom.h)
        equal(top.children[1].text, "Tab bearbeiten")
        equal(top.children[2].text, "Element anlegen")
        equal(bottom.children[1].text, "Bedienung")
        equal(bottom.children[2].text, "Speichern")
        for index = 1, 2 do
            local upper, lower = top.children[index], bottom.children[index]
            equal(upper.x, lower.x)
            equal(upper.y, lower.y)
            equal(upper.w, lower.w)
            equal(upper.h, lower.h)
            equal(upper.w, top.children[1].w)
        end
        equal(content.scrollDir, lvgl.SCROLL_VER)
        assert(top.y + top.h <= topSeparator.y)
        assert(content.h > 0 and topSeparator.y + topSeparator.h <= content.y)
        equal(topSeparator.x, top.x)
        equal(topSeparator.w, top.w)
        assert(content.y + content.h < bottom.y)
        equal(bottom.y + bottom.h, view.uiJob.height)
        assert(statusSeparator.y >= view.uiJob.height)
        assert(status.y >= statusSeparator.y + statusSeparator.h)
        assert(status.h > 0 and status.y + status.h > view.uiJob.height)
        equal(statusSeparator.x, bottom.x)
        equal(statusSeparator.w, bottom.w)
        equal(status.text, app.footerStatus)
        assert(not find(function(item)
            return item.text == "Tab bearbeiten" or item.text == "Element anlegen" or item.name == "status"
        end, content.children))
    end
end)

test("Editors keep bottom actions at the viewport edge with scrollable status", function()
    getGeneralSettings = function() return {language = "DE"} end
    local app = appInstance()
    ready(app)
    settleAutosave(app)
    local cases = {
        {"config", app.data.header, "Widget-Einstellungen"},
        {"tab", app.tabs[1], "Tab bearbeiten"},
        {"tab", app.newTab(), "Tab-Einstellungen"},
        {"control", app.controls[1], "Element-Einstellungen"},
    }
    for _, screen in ipairs({{320, 240, 204, 26}, {480, 272, 227, 32},
                            {800, 480, 412, 48}, {480, 800, 755, 32}}) do
        LCD_W, LCD_H = screen[1], screen[2]
        lvgl.PAGE_BODY_HEIGHT, lvgl.UI_ELEMENT_HEIGHT = screen[3], screen[4]
        for _, case in ipairs(cases) do
            local view = {zone = {w = LCD_W, h = LCD_H}, app = app, page = "editor",
                          editKind = case[1], edit = app.config.copy(case[2]), editRevision = app.revision}
            render(app, view)
            equal(view.uiJob.page.params.title, case[3])
            equal(view.uiJob.page.params.scrollDir, lvgl.SCROLL_VER)
            equal(view.uiJob.page.params.scrollBar, true)
            equal(view.uiJob.page.params.prevButton, nil)
            equal(view.uiJob.page.params.nextButton, nil)
            local actions = view.refs.actions.definition
            local content, status = view.refs.settings.definition, view.refs.status.definition
            local separator = view.refs.statusSeparator.definition
            equal(#actions.children, 3)
            equal(actions.children[1].text, "Anwenden")
            equal(actions.children[2].text, "Abbrechen")
            equal(actions.children[3].text, "Speichern")
            equal(actions.y + actions.h, screen[3])
            assert(content.h > 0 and content.y + content.h < actions.y)
            assert(separator.y >= screen[3] and status.y >= separator.y + separator.h)
            equal(status.text, app.footerStatus)
            if case[1] == "control" then
                local y = actions.y
                for _, section in ipairs({"Eingänge", "Aussehen", "Allgemein"}) do
                    press(section)
                    render(app, view)
                    equal(view.refs.actions.definition.y, y)
                    equal(view.refs.status.definition.y, status.y)
                end
            end
        end
    end
end)

test("Field explanations sit beside inputs and wrap within row bounds in both menu languages", function()
    for _, language in ipairs({"EN", "DE"}) do
        getGeneralSettings = function() return {language = language} end
        for _, protocol in ipairs({0, 1, 2}) do
            local data = config.defaults()
            data.header.autoSave, data.header.protocol = 0, protocol
            local path = "inline-" .. language .. protocol
            finish(storage.save(path .. ".a.lua", data, 1), storage.stepSave)
            local app = appInstance(path)
            ready(app)
            local cases
            if protocol == 0 then
                cases = {
                    {"config", nil, {{"Button spacing:", "-1: default; 0..40 px"}, {"Interval:", "Unit: 10 ms"}}},
                    {"tab", nil, {{"Default address:", "Changes all -1 controls"}, {"Height:", "0: auto; 30..240"}}},
                    {"control", "Basic", {{"Address:", "-1: tab address"}}},
                    {"control", "Inputs", {{"Mutex group:", "0: no group"}}},
                }
            elseif protocol == 1 then
                cases = {{"config", nil, {{"App ID:", "High byte; default 81 (0x51)"}}}}
            else
                cases = {{"control", "Basic", {
                    {"Output:", "ACW: address * 8 + output; 1..255"},
                    {"On PWM:", "Off: 0; default: 255"},
                }}}
            end
            for _, screen in ipairs({{320, 240, 204, 26}, {480, 272, 227, 32},
                                    {800, 480, 412, 48}, {480, 800, 755, 32}}) do
                LCD_W, LCD_H = screen[1], screen[2]
                lvgl.PAGE_BODY_HEIGHT, lvgl.UI_ELEMENT_HEIGHT = screen[3], screen[4]
                for _, case in ipairs(cases) do
                    local record = case[1] == "config" and app.data.header
                        or case[1] == "tab" and app.tabs[1] or app.controls[1]
                    local view = {zone = {w = LCD_W, h = LCD_H}, app = app, page = "editor",
                                  editKind = case[1], edit = app.config.copy(record),
                                  editRevision = app.revision, editSection = case[2]}
                    render(app, view)
                    for _, expected in ipairs(case[3]) do
                        local row = assert(find(function(item)
                            return item.type == "box" and item.children
                                and item.children[1].text == app.t(expected[1])
                        end))
                        equal(#row.children, 3)
                        local caption, input, explanation = row.children[1], row.children[2], row.children[3]
                        equal(explanation.type, "label")
                        equal(string.gsub(explanation.text, "\n", " "), app.t(expected[2]))
                        assert(caption.x + caption.w <= input.x)
                        assert(input.x + input.w < explanation.x)
                        assert(explanation.x + explanation.w <= row.w)
                        assert(input.w > 0 and explanation.w > 0)
                        for _, item in ipairs(row.children) do
                            equal(item.y, math.floor(item.y))
                            assert(item.y >= 0 and item.y + item.h <= row.h)
                        end
                        for line in string.gmatch(explanation.text, "[^\n]+") do
                            assert(lcd.sizeText(line, explanation.font) <= explanation.w,
                                   "Inline explanation clips horizontally")
                        end
                        equal(row.scrollDir, lvgl.SCROLL_OFF)
                    end
                end
            end
        end
    end
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
        local iconFile = assert(hostIO.open(view.uiJob.page.params.icon, "rb"))
        local iconHeader = iconFile:read(24)
        iconFile:close()
        local iconWidth, iconHeight = string.unpack(">I4I4", iconHeader, 17)
        equal(iconWidth, iconHeight)
        assert(iconHeight <= LCD_H - view.uiJob.height)
        if LCD_W >= 480 then assert(iconWidth > 30, "Header logo still uses the small variant") end
        equal(view.uiJob.page.params.scrollDir, lvgl.SCROLL_VER)
        equal(view.uiJob.page.params.scrollBar, true)
        equal(view.uiJob.page.params.flexFlow, nil)
        equal(content.scrollDir, lvgl.SCROLL_VER)
        assert(content.h > 0 and content.y + content.h < actions.y)
        equal(actions.y + actions.h, screen[3])
        assert(view.refs.statusSeparator.definition.y >= screen[3])
        assert(status.y >= view.refs.statusSeparator.definition.y + 1)
        assert(not find(function(item) return item.text == "Apply" or item.text == "Cancel" end, content.children))
        local column, fields = nil, 0
        for _, item in ipairs(content.children) do
            if item.type == "box" and item.children and item.children[1].type == "label" then
                assert(#item.children == 2 or #item.children == 3)
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
        equal(fields, 7)
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

test("Legacy button spacing preserves the default layout and invalid spacing is rejected", function()
    local data = config.defaults()
    data.header.autoSave, data.header.buttonSpacing = 0, nil
    finish(storage.save("model.a.lua", data, 1), storage.stepSave)
    local app = appInstance()
    ready(app)
    equal(app.phase, "ready")
    equal(app.data.header.buttonSpacing, -1)
    local view = {zone = {w = 480, h = 272}, app = app, tab = 1, page = "control"}
    render(app, view)
    equal(view.uiJob.page.params.flexPad, 2)
    equal(view.refs.c1.definition.w, 208)
    equal(view.refs.c1.definition.h, 51)
    for _, value in ipairs({-2, 41, 0.5, "4"}) do
        local header = config.copy(app.data.header)
        header.buttonSpacing = value
        assert(not commit(app, "config", header))
        contains(app.error, "Invalid config.buttonSpacing")
        equal(app.data.header.buttonSpacing, -1)
    end
end)

test("Global button spacing uses translated editing, applies only on confirmation and persists", function()
    getGeneralSettings = function() return {language = "DE"} end
    local data = config.defaults()
    data.header.autoSave = 0
    finish(storage.save("model.a.lua", data, 1), storage.stepSave)
    local app = appInstance()
    ready(app)
    local view = {zone = {w = 480, h = 272}, app = app, tab = 1, page = "control"}
    render(app, view)
    local originalWidth = view.refs.c1.definition.w
    press("Einstellungen")
    render(app, view)
    press("Global")
    render(app, view)
    equal(form("Button-Abstand:").get(), -1)
    form("Button-Abstand:").set(40)
    equal(app.data.header.buttonSpacing, -1)
    press("Abbrechen")
    render(app, view)
    equal(view.refs.c1.definition.w, originalWidth)
    equal(app.data.header.buttonSpacing, -1)
    press("Global")
    render(app, view)
    form("Button-Abstand:").set(18)
    equal(app.data.header.buttonSpacing, -1)
    press("Anwenden")
    render(app, view)
    equal(app.data.header.buttonSpacing, 18)
    equal(view.uiJob.page.params.flexPad, 18)
    equal(view.refs.c1.definition.w, originalWidth - 8)
    save(app)
    equal(app.saveError, nil)
    local fresh = appInstance()
    ready(fresh)
    equal(fresh.data.header.buttonSpacing, 18)
end)

test("Custom spacing fits row widths, supports zero and scrolling, and applies to all tabs", function()
    for _, settings in ipairs({
        {320, 240, 4, 40, 0}, {480, 272, 2, 0, 0}, {800, 480, 3, 18, 0},
        {480, 272, 1, 40, 0}, {480, 272, 2, 18, 48},
    }) do
        LCD_W, LCD_H = settings[1], settings[2]
        lvgl.PAD_OUTLINE = LCD_W == 800 and 3 or 2
        local data = config.defaults()
        data.header.autoSave, data.header.buttonSpacing = 0, settings[4]
        data.tabs[1].columns, data.tabs[1].height = settings[3], settings[5]
        data.tabs[2] = {kind = "tab", id = 2, name = "Second", address = 1, columns = 1, height = 48}
        data.controls[9] = config.newControl(9, 2, 1)
        finish(storage.save("model.a.lua", data, 1), storage.stepSave)
        local app = appInstance()
        ready(app)
        local view = {zone = {w = LCD_W, h = LCD_H}, app = app, tab = 1, page = "control"}
        render(app, view)
        equal(view.uiJob.page.params.flexPad, settings[4])
        local rows, totalHeight = 0, 2 * lvgl.PAD_OUTLINE
        for _, item in ipairs(definitions) do
            if item.type == "box" and item.children and item.children[1].name == "c" .. (rows * settings[3] + 1) then
                equal(item.flexPad, settings[4])
                equal(item.borderPad.top, 0)
                equal(item.borderPad.bottom, 0)
                local usedWidth = 2 * lvgl.PAD_OUTLINE + (#item.children - 1) * settings[4]
                for _, child in ipairs(item.children) do
                    usedWidth = usedWidth + child.w
                    equal(child.h, item.h)
                    assert(child.w > 0 and child.h >= 30)
                    if settings[5] ~= 0 then equal(child.h, settings[5]) end
                end
                assert(usedWidth <= item.w, "Button spacing causes horizontal overflow")
                totalHeight = totalHeight + item.h + (rows > 0 and settings[4] or 0)
                rows = rows + 1
            end
        end
        equal(rows, math.ceil(8 / settings[3]))
        if settings[5] == 0 and totalHeight <= view.uiJob.height then
            equal(totalHeight, view.uiJob.height)
        end
        if settings[3] == 1 then assert(totalHeight > view.uiJob.height) end
        view.tab, view.renderRevision = 2, nil
        render(app, view)
        equal(view.uiJob.page.params.flexPad, settings[4])
        equal(view.refs.c9.definition.h, 48)
    end
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

test("Send colors now follows the LED draft immediately without applying or saving it", function()
    local app = appInstance()
    ready(app)
    settleAutosave(app)
    local view = {zone = {w = 480, h = 272}, app = app, page = "control"}
    render(app, view)
    press("Setup")
    render(app, view)
    press("Global")
    render(app, view)
    local send = assert(find(function(item) return item.type == "button" and item.text == "Send colors now" end))
    assert(not send.active())
    local revision, writes = app.revision, writeCount
    form("LED colors:").set(1)
    assert(send.active(), "Send colors now did not react to the draft")
    equal(app.data.header.sendColors, 0)
    equal(app.sender.sendColors, false)
    frames = {}
    press("Send colors now")
    advance(app, 10)
    local colors = 0
    for _, frame in ipairs(frames) do
        if frame.payload[4] == 0x0a then colors = colors + 1 end
    end
    equal(colors, 1)
    equal(app.sender.pendingColors, 0)
    equal(app.sender.sendColors, false)
    equal(app.data.header.sendColors, 0)
    equal(app.revision, revision)
    equal(writeCount, writes)
    form("LED colors:").set(0)
    assert(not send.active())
    frames = {}
    app.crsf.colors(app.sender)
    advance(app, 100)
    assert(not find(function(frame) return frame.payload[4] == 0x0a end, frames))
    press("Cancel")
    render(app, view)
    local header = config.copy(app.data.header)
    header.sendColors = 1
    assert(commit(app, "config", header))
    render(app, view)
    press("Global")
    render(app, view)
    send = assert(find(function(item) return item.type == "button" and item.text == "Send colors now" end))
    assert(send.active())
    form("LED colors:").set(0)
    assert(not send.active(), "Button still follows the applied setting")
    equal(app.sender.sendColors, true)
    equal(app.data.header.sendColors, 1)
end)

test("One-shot colors retry full queues and restart completely on a new color epoch", function()
    local data, sender = config.defaults(), crsf.new()
    data.controls = {data.controls[1], data.controls[2], data.controls[3]}
    for index, control in ipairs(data.controls) do control.address = index - 1 end
    configure(sender, data, {})
    crsf.colors(sender, true)
    sender.lane, blocked = 3, true
    crsf.tick(sender, 1)
    equal(sender.pendingColors, 3)
    contains(sender.error, "busy")
    blocked = false
    crsf.tick(sender, 2)
    equal(sender.pendingColors, 2)
    equal(encode(frames[1].payload), encode(frames[2].payload))
    crsf.colors(sender)
    equal(sender.pendingColors, 3)
    for time = 3, 40 do
        crsf.tick(sender, time)
        if sender.pendingColors == 0 then break end
    end
    equal(sender.pendingColors, 0)
    local accepted = {}
    for _, frame in ipairs(frames) do
        if frame.payload[4] == 0x0a and not frame.blocked then
            local address = frame.payload[5]
            accepted[address] = (accepted[address] or 0) + 1
        end
    end
    equal(accepted[0], 2)
    equal(accepted[1], 1)
    equal(accepted[2], 1)
    frames = {}
    crsf.colors(sender)
    for time = 100, 110 do crsf.tick(sender, time) end
    assert(not find(function(frame) return frame.payload[4] == 0x0a end, frames))
    equal(sender.sendColors, false)
end)

test("Legacy configuration headers still load and transmit through CRSF", function()
    local data = config.defaults()
    data.header.protocol, data.header.sportPhysicalId, data.header.sportAppId = nil, nil, nil
    data.header.autoSave = 0
    finish(storage.save("model.a.lua", data, 7), storage.stepSave)
    local app = appInstance()
    ready(app)
    assert(not app.error, app.error)
    equal(app.data.header.protocol, 0)
    app.set(1, 1)
    advance(app)
    equal(encode(frames[#frames].payload), "0,234,161,7,0,0,1")
    equal(#sportFrames, 0)
    local header = config.copy(app.data.header)
    header.protocol = 1
    assert(commit(app, "config", header))
    save(app)
    local fresh = appInstance()
    ready(fresh)
    equal(fresh.data.header.protocol, 1)
    equal(fresh.sender.physicalId, 0)
    equal(fresh.sender.appId, 0x51)
    equal(fresh.data.header.autoSave, 0)
end)

test("S.Port WM packs two-bit states, addresses and IDs and repeats without full invalidation", function()
    local data, sender = config.defaults(), sport.new()
    data.header.protocol, data.header.sportPhysicalId, data.header.sportAppId = 1, 0x1b, 0xff
    data.header.interval, data.tabs[1].address = 10, 255
    data.controls = {data.controls[1], data.controls[6], data.controls[8]}
    data.controls[2].address, data.controls[2].type, data.controls[3].type = 254, 3, 3
    configure(sender, data, {[1] = 1, [6] = 2, [8] = 2})
    sport.tick(sender, 1)
    sport.tick(sender, 2)
    equal(encode(sportFrames[1].payload), "27,49,65535,32769")
    equal(encode(sportFrames[2].payload), "27,49,65534,2048")
    sport.tick(sender, 3)
    equal(#sportFrames, 2)
    sport.set(sender, 1, 0)
    sport.tick(sender, 4)
    equal(encode(sportFrames[3].payload), "27,49,65535,32768")
    sport.tick(sender, 12)
    equal(encode(sportFrames[4].payload), "27,49,65534,2048")
    sport.invalidate(sender)
    sport.tick(sender, 13)
    sport.tick(sender, 14)
    sport.tick(sender, 15)
    equal(#sportFrames, 6)
    equal(sportFrames[5].payload[3], 65535)
    equal(sportFrames[6].payload[3], 65534)
    sport.tick(sender, 0)
    equal(#sportFrames, 7)
    equal(#frames, 0)
end)

test("S.Port WM preserves failed requests and explicitly reports missing APIs", function()
    local sender = sport.new()
    configure(sender, config.defaults(), {[1] = 1})
    sportBlocked = true
    sport.tick(sender, 1)
    contains(sender.error, "not accepted")
    assert(sender.groups[1].dirty)
    equal(sender.groups[1].last, -100000)
    sportBlocked = false
    sport.tick(sender, 2)
    equal(encode(sportFrames[1].payload), encode(sportFrames[2].payload))
    equal(sender.error, nil)
    local native = sportTelemetryPush
    sportTelemetryPush = function() return nil end
    sport.set(sender, 1, 0)
    sport.tick(sender, 3)
    contains(sender.error, "not accepted")
    assert(sender.groups[1].dirty)
    equal(sender.groups[1].last, 2)
    sportTelemetryPush = nil
    sport.tick(sender, 4)
    equal(sender.error, "S.Port API unavailable")
    equal(#sportFrames, 2)
    sportTelemetryPush = native
    sport.tick(sender, 5)
    equal(encode(sportFrames[3].payload), "0,49,20736,0")
    equal(sender.error, nil)
end)

test("S.Port WM schedules all addresses fairly and limits idle scans", function()
    local data, sender = config.defaults(), sport.new()
    data.header.protocol, data.header.interval, data.controls = 1, 1000, {}
    for address = 0, 255 do
        local control = config.newControl(address + 1, 1, 1)
        control.address = address
        data.controls[#data.controls + 1] = control
    end
    configure(sender, data, {})
    for time = 1, 256 do
        sport.set(sender, 1, time % 2)
        local before = #sportFrames
        sport.tick(sender, time)
        equal(#sportFrames - before, 1)
        equal(sportFrames[#sportFrames].payload[3], 0x5100 + time - 1)
    end
    sport.tick(sender, 257)
    local groups, reads = sender.groups, 0
    sender.groups = setmetatable({}, {
        __len = function() return #groups end,
        __index = function(_, index) reads = reads + 1; return groups[index] end,
    })
    local before = #sportFrames
    sport.tick(sender, 258)
    assert(reads <= 8, "Unbounded S.Port address scan")
    equal(#sportFrames, before)
end)

test("S.Port WM processes physical controls and mutex groups across tabs", function()
    local data = config.defaults()
    data.header.protocol, data.header.autoSave = 1, 0
    data.tabs[2] = config.copy(data.tabs[1])
    data.tabs[2].id, data.tabs[2].address = 2, 23
    for index = 5, 8 do data.controls[index].tab = 2 end
    data.controls[1].switch, data.controls[1].group = 19, 1
    data.controls[2].type, data.controls[2].switch, data.controls[2].switch2 = 3, 10, -10
    data.controls[6].switch, data.controls[6].group = 20, 1
    finish(storage.save("model.a.lua", data, 1), storage.stepSave)
    local app = appInstance()
    ready(app)
    switches[19], switches[-10], switches[20] = true, true, true
    advance(app, 2)
    equal(app.values[1], 0)
    equal(app.values[2], 2)
    equal(app.values[6], 1)
    equal(encode(sportFrames[1].payload), "0,49,20736,8")
    equal(encode(sportFrames[2].payload), "0,49,20759,1024")
    app.set(8, 1)
    advance(app)
    equal(sportFrames[#sportFrames].payload[4], 17408)
    local before = #sportFrames
    app.tick()
    equal(#sportFrames, before)
    equal(#frames, 0)
end)

test("S.Port WM rejects sliders without activating or saving the invalid candidate", function()
    local app = appInstance()
    ready(app)
    local control = config.copy(app.controls[1])
    control.type = 5
    assert(commit(app, "control", control))
    settleAutosave(app)
    app.set(1, 70)
    local data, sender, revision, writes = app.data, app.sender, app.revision, writeCount
    local header = config.copy(app.data.header)
    header.protocol = 1
    local job = assert(app.commit("config", header))
    finish(job, function() advance(app) end)
    assert(not job.success)
    contains(job.error, "Slider is not supported")
    equal(app.data, data)
    equal(app.sender, sender)
    equal(app.revision, revision)
    equal(app.values[1], 70)
    advance(app, 20)
    equal(writeCount, writes)
    equal(#sportFrames, 0)
    local invalid = {header = header, tabs = data.tabs, controls = data.controls}
    finish(storage.save("invalid.a.lua", invalid, 1), storage.stepSave)
    contains(finish(storage.load("invalid.a.lua"), storage.stepLoad).error, "Slider is not supported")
end)

test("S.Port WM retains pending shutdowns with their original IDs across deletion and remapping", function()
    local data = config.defaults()
    data.header.protocol, data.header.autoSave, data.tabs[1].address = 1, 0, 7
    data.tabs[2] = config.copy(data.tabs[1])
    data.tabs[2].id, data.tabs[2].address = 2, 9
    for index = 5, 8 do data.controls[index].tab = 2 end
    finish(storage.save("model.a.lua", data, 1), storage.stepSave)
    local app = appInstance()
    ready(app)
    app.set(1, 1)
    app.set(5, 1)
    advance(app, 2)
    sportBlocked = true
    assert(commit(app, "tab", config.copy(app.tabs[2]), true))
    local pending = assert(app.sender.off[1][app.sender.offIndex[1]])
    equal(encode(pending.payload), "0,49,20745,0")
    local header = config.copy(app.data.header)
    header.sportPhysicalId, header.sportAppId = 1, 0x52
    assert(commit(app, "config", header))
    equal(app.sender.off[1][1], pending)
    equal(offCount(app.sender), 2)
    advance(app)
    contains(app.status(), "Retired output pending")
    sportBlocked, sportFrames = false, {}
    advance(app, 2)
    equal(encode(sportFrames[1].payload), "0,49,20745,0")
    equal(encode(sportFrames[2].payload), "0,49,20743,0")
    equal(offCount(app.sender), 0)
    advance(app)
    equal(encode(sportFrames[3].payload), "1,49,20999,1")
    equal(#frames, 0)
end)

test("Protocol changes preserve old shutdown transport without starving new outputs", function()
    local data = config.defaults()
    data.header.protocol, data.header.autoSave = 1, 0
    finish(storage.save("model.a.lua", data, 1), storage.stepSave)
    local app = appInstance()
    ready(app)
    app.set(1, 1)
    advance(app)
    sportBlocked = true
    local header = config.copy(app.data.header)
    header.protocol = 0
    assert(commit(app, "config", header))
    sportFrames, frames = {}, {}
    for _ = 1, 6 do
        local before = #sportFrames + #frames
        advance(app)
        assert(#sportFrames + #frames - before <= 1, "Multiple transport packets in one tick")
    end
    equal(encode(frames[1].payload), "0,234,161,7,0,0,1")
    equal(encode(sportFrames[1].payload), "0,49,20736,0")
    equal(app.sender.offIndex[1], 1)
    contains(app.status(), "Retired output pending: S.Port")
    app.set(1, 0)
    advance(app, 2)
    equal(encode(frames[#frames].payload), "0,234,161,7,0,0,0")
    sportBlocked = false
    advance(app, 2)
    equal(offCount(app.sender), 0)
    equal(app.sender.offError, nil)
    app.set(1, 1)
    advance(app)
    local native = crossfireTelemetryPush
    crossfireTelemetryPush = nil
    header = config.copy(app.data.header)
    header.protocol = 1
    assert(commit(app, "config", header))
    sportFrames, frames = {}, {}
    advance(app, 2)
    contains(app.status(), "Retired output pending: CRSF API unavailable")
    equal(encode(sportFrames[1].payload), "0,49,20736,1")
    equal(#frames, 0)
    crossfireTelemetryPush = native
    advance(app)
    equal(encode(frames[1].payload), "0,234,161,7,0,0,0")
    equal(offCount(app.sender), 0)
end)

test("Unavailable CRSF shutdowns do not block later S.Port shutdowns", function()
    local data = config.defaults()
    data.header.autoSave = 0
    data.tabs[2] = config.copy(data.tabs[1])
    data.tabs[2].id, data.tabs[2].address = 2, 9
    for index = 5, 8 do data.controls[index].tab = 2 end
    finish(storage.save("model.a.lua", data, 1), storage.stepSave)
    local app = appInstance()
    ready(app)
    app.set(1, 1)
    app.set(5, 1)
    advance(app)
    crossfireTelemetryPush = nil
    local header = config.copy(app.data.header)
    header.protocol = 1
    assert(commit(app, "config", header))
    advance(app, 2)
    contains(app.status(), "Retired output pending: CRSF")
    assert(commit(app, "tab", config.copy(app.tabs[2]), true))
    equal(#app.sender.off[0], 2)
    equal(#app.sender.off[1], 1)
    sportFrames = {}
    advance(app)
    equal(encode(sportFrames[1].payload), "0,49,20745,0")
    equal(#app.sender.off[1], 0)
    equal(#app.sender.off[0], 2)
    advance(app, 2)
    contains(app.status(), "Retired output pending: CRSF")
    equal(encode(sportFrames[2].payload), "0,49,20736,1")
end)

test("Retirements already accepted during preparation are not transmitted again", function()
    local data, previous, sender = config.defaults(), crsf.new(), sport.new()
    configure(previous, data, {})
    configure(sender, data, {})
    crsf.retireGroup(previous, previous, {key = 9})
    local pending = previous.off[0][1]
    sender.off[0][1] = pending
    crsf.tick(previous, 1)
    assert(pending.done)
    equal(#frames, 1)
    sport.tick(sender, 2)
    equal(#frames, 1)
    equal(offCount(sender), 0)
    sport.tick(sender, 3)
    equal(encode(sportFrames[1].payload), "0,49,20736,0")
end)

test("Retired simulator CRSF packets keep serial framing after selecting S.Port", function()
    getVersion = function() return "3.0.0", "tx16s-simu" end
    local written = {}
    serialWrite = function(data) written[#written + 1] = data end
    crossfireTelemetryPush = function() error("Simulator shutdown must use serial CRSF") end
    local data, previous, sender = config.defaults(), crsf.new(), sport.new()
    configure(previous, data, {[1] = 1})
    crsf.tick(previous, 0)
    written = {}
    data.header.protocol = 1
    configure(sender, data, {[1] = 1})
    crsf.retireGroup(sender, previous, previous.groups[1])
    sport.tick(sender, 1)
    equal(#written, 1)
    local bytes = {string.byte(written[1], 1, #written[1])}
    equal(encode({table.unpack(bytes, 3, 10)}), "50,0,234,161,7,0,0,0")
    equal(#sportFrames, 0)
    sport.tick(sender, 2)
    equal(encode(sportFrames[1].payload), "0,49,20736,1")
    equal(offCount(sender), 0)
end)

test("Protocol editor preserves drafts and only shows supported settings and types", function()
    local app = appInstance()
    ready(app)
    settleAutosave(app)
    local view = {zone = {w = 480, h = 272}, app = app, page = "control"}
    render(app, view)
    press("Setup")
    render(app, view)
    press("Global")
    render(app, view)
    form("Name:").set("Protocol draft")
    form("Destination:").set(42)
    form("LED colors:").set(1)
    form("Protocol:").set(2)
    render(app, view)
    equal(app.sender.protocol, 0)
    assert(not find(function(item) return item.text == "LED colors:" or item.text == "Destination:" end))
    form("Physical ID:").set(10)
    form("App ID:").set(99)
    form("Protocol:").set(1)
    render(app, view)
    equal(form("Name:").value, "Protocol draft")
    equal(form("Destination:").get(), 42)
    equal(form("LED colors:").get(), 1)
    form("Protocol:").set(2)
    render(app, view)
    equal(form("Physical ID:").get(), 10)
    equal(form("App ID:").get(), 99)
    press("Apply")
    render(app, view)
    equal(app.sender.protocol, 1)
    equal(app.sender.physicalId, 10)
    equal(app.sender.appId, 99)
    settleAutosave(app)
    press("Tab settings")
    render(app, view)
    press("Edit")
    render(app, view)
    equal(#form("Type:").values, 4)
    press("Cancel")
    render(app, view)
    view.page, view.renderRevision = "control", nil
    render(app, view)
    press("Global")
    render(app, view)
    form("Protocol:").set(1)
    render(app, view)
    local send = assert(find(function(item) return item.type == "button" and item.text == "Send colors now" end))
    assert(not send.active(), "Unapplied CRSF draft must not send through S.Port")
    local before = #sportFrames + #frames
    send.press()
    equal(#sportFrames + #frames, before)
    equal(app.sender.protocol, 1)
end)

test("Legacy controls acquire ACW defaults without changing the original records", function()
    local data = config.defaults()
    data.header.protocol, data.header.autoSave = 1, 0
    for _, control in ipairs(data.controls) do
        control.sportType, control.sportOptions, control.sportPwmOn = nil, nil, nil
    end
    finish(storage.save("model.a.lua", data, 6), storage.stepSave)
    local app = appInstance()
    ready(app)
    assert(not app.error, app.error)
    equal(data.controls[1].sportPwmOn, nil)
    app.set(1, 1)
    local header = config.copy(app.data.header)
    header.protocol = 2
    assert(commit(app, "config", header))
    equal(app.values[1], 1)
    save(app)
    local fresh = appInstance()
    ready(fresh)
    equal(fresh.sender.variant, 2)
    equal(fresh.controls[1].sportType, 1)
    equal(fresh.controls[1].sportOptions, 0)
    equal(fresh.controls[1].sportPwmOn, 255)
    fresh.set(1, 1)
    sportFrames = {}
    advance(fresh)
    equal(sportFrames[1].payload[4], 0x010001ff)
end)

test("ACW 1.5 and 1.4 encode all four bytes including unsigned high-bit values", function()
    for variant = 2, 3 do
        local data, sender = config.defaults(), sport.new()
        data.header.protocol = variant
        data.controls = {data.controls[1], data.controls[7]}
        data.controls[1].sportType, data.controls[1].sportOptions, data.controls[1].sportPwmOn = 0x81, 0xaa, 99
        data.controls[2].address = 31
        data.controls[2].sportType, data.controls[2].sportOptions, data.controls[2].sportPwmOn = 255, 255, 255
        assert(config.validate(data))
        configure(sender, data, {[1] = 1, [7] = 1})
        sportFrames = {}
        sport.tick(sender, 1)
        sport.tick(sender, 2)
        local dataId = variant == 2 and 0xac00 or 0xfa07
        equal(encode(sportFrames[1].payload), encode({27, 16, dataId, 0x81aa0163}))
        equal(sportFrames[2].payload[4], 0xffffffff)
        equal(sportFrames[2].payload[3], dataId)
        sport.set(sender, 1, 0)
        sport.tick(sender, 3)
        equal(sportFrames[3].payload[4], 0x81aa0100)
        sport.tick(sender, 4)
        equal(#sportFrames, 3)
        sport.tick(sender, 103)
        sport.tick(sender, 104)
        equal(#sportFrames, 5)
        sport.invalidate(sender)
        sport.tick(sender, 105)
        sport.tick(sender, 106)
        equal(#sportFrames, 7)
        equal(#frames, 0)
    end
end)

test("ACW retains busy and unavailable requests until their exact command is accepted", function()
    for variant = 2, 3 do
        local data, sender = config.defaults(), sport.new()
        data.header.protocol, data.controls = variant, {data.controls[1]}
        data.controls[1].sportPwmOn = 37
        configure(sender, data, {[1] = 1})
        sportFrames, sportBlocked = {}, true
        sport.tick(sender, 1)
        assert(sender.props[1].dirty)
        equal(sender.props[1].last, -100000)
        contains(sender.error, "not accepted")
        sportBlocked = false
        sport.tick(sender, 2)
        equal(encode(sportFrames[1].payload), encode(sportFrames[2].payload))
        equal(sender.error, nil)
        local native = sportTelemetryPush
        sportTelemetryPush = function() return nil end
        sport.set(sender, 1, 0)
        sport.tick(sender, 3)
        contains(sender.error, "not accepted")
        assert(sender.props[1].dirty)
        equal(sender.props[1].last, 2)
        sportTelemetryPush = native
        sport.tick(sender, 4)
        equal(sportFrames[3].payload[4], 0x01000100)
        equal(sender.error, nil)
    end
end)

test("ACW schedules 255 outputs fairly with bounded scans and one command per tick", function()
    local data, sender = config.defaults(), sport.new()
    data.header.protocol, data.header.interval, data.controls = 2, 1000, {}
    for number = 1, 255 do
        local control = config.newControl(number, 1, (number - 1) % 8 + 1)
        control.address = (number - 1) // 8
        data.controls[number] = control
    end
    assert(config.validate(data))
    configure(sender, data, {})
    for time = 1, 255 do
        sport.set(sender, 1, time % 2)
        local before = #sportFrames
        sport.tick(sender, time)
        equal(#sportFrames - before, 1)
        equal((sportFrames[#sportFrames].payload[4] >> 8) & 255, time)
        equal(sportFrames[#sportFrames].payload[2], 0x10)
    end
    sport.tick(sender, 256)
    local props, reads = sender.props, 0
    sender.props = setmetatable({}, {
        __len = function() return #props end,
        __index = function(_, index) reads = reads + 1; return props[index] end,
    })
    local before = #sportFrames
    sport.tick(sender, 257)
    assert(reads <= 8, "Unbounded ACW output scan")
    equal(#sportFrames, before)
end)

test("ACW rejects unsupported types and number overflows instead of corrupting packed fields", function()
    for variant = 2, 3 do
        for _, kind in ipairs({3, 5}) do
            local data = config.defaults()
            data.header.protocol, data.controls[1].type = variant, kind
            local valid, err = config.validate(data)
            assert(not valid)
            contains(err, "not supported by S.Port ACW")
        end
        local data = config.defaults()
        data.header.protocol, data.controls[1].address, data.controls[1].output = variant, 31, 7
        assert(config.validate(data))
        data.controls[1].output = 8
        local valid, err = config.validate(data)
        assert(not valid)
        contains(err, "ACW switch number must be 1..255")
        data.tabs[1].address, data.controls[1].address = 32, -1
        valid, err = config.validate(data)
        assert(not valid)
        contains(err, "ACW switch number must be 1..255")
    end
    local app = appInstance()
    ready(app)
    local control = config.copy(app.controls[1])
    control.type = 3
    assert(commit(app, "control", control))
    settleAutosave(app)
    app.set(1, 2)
    local data, sender, revision, writes = app.data, app.sender, app.revision, writeCount
    local header = config.copy(app.data.header)
    header.protocol = 2
    local ok, err = commit(app, "config", header)
    assert(not ok)
    contains(err, "3Pos is not supported")
    equal(app.data, data)
    equal(app.sender, sender)
    equal(app.revision, revision)
    equal(app.values[1], 2)
    equal(writeCount, writes)
end)

test("ACW allocation stops at number 255 and never returns address 31 output 8", function()
    local data = config.defaults()
    data.header.protocol, data.header.autoSave, data.tabs[1].address, data.controls = 2, 0, 31, {}
    for number = 1, 254 do
        local control = config.newControl(number, 1, (number - 1) % 8 + 1)
        control.address = (number - 1) // 8
        data.controls[number] = control
    end
    finish(storage.save("model.a.lua", data, 1), storage.stepSave)
    local app = appInstance()
    ready(app)
    local control = assert(app.newControl(app.tabs[1]))
    equal(config.address(control, app.tabs[1]), 31)
    equal(control.output, 7)
    assert(commit(app, "control", control))
    assert(not app.newControl(app.tabs[1]))
    contains(app.error, "All switch outputs are assigned")
    assert(not app.newTab())
    contains(app.error, "No unused switch address")
end)

test("ACW retirements preserve old parameters and formats across edits and protocol changes", function()
    local data = config.defaults()
    data.header.protocol, data.header.autoSave, data.controls = 2, 0, {data.controls[1], data.controls[2]}
    data.controls[1].sportType, data.controls[1].sportOptions, data.controls[1].sportPwmOn = 0x81, 5, 100
    data.controls[2].sportType, data.controls[2].sportOptions, data.controls[2].sportPwmOn = 2, 9, 200
    data.controls[2].type = 2
    finish(storage.save("model.a.lua", data, 1), storage.stepSave)
    local app = appInstance()
    ready(app)
    app.set(1, 1)
    app.set(2, 1)
    advance(app, 2)
    sportBlocked = true
    local control = config.copy(app.controls[1])
    control.address = 1
    assert(commit(app, "control", control))
    app.set(1, 1)
    control = config.copy(app.controls[2])
    control.sportType, control.sportOptions, control.sportPwmOn = 3, 10, 90
    assert(commit(app, "control", control))
    equal(offCount(app.sender), 2)
    advance(app)
    contains(app.status(), "Retired output pending")
    sportBlocked, sportFrames = false, {}
    advance(app, 4)
    equal(sportFrames[1].payload[4], 0x81050100)
    equal(sportFrames[2].payload[4], 0x02090200)
    equal(sportFrames[3].payload[4], 0x81050964)
    equal(sportFrames[4].payload[4], 0x030a025a)
    for _, frame in ipairs(sportFrames) do equal(frame.payload[3], 0xac00) end
    local header = config.copy(app.data.header)
    header.protocol = 3
    assert(commit(app, "config", header))
    sportFrames = {}
    advance(app, 4)
    equal(sportFrames[1].payload[3], 0xac00)
    equal(sportFrames[3].payload[3], 0xac00)
    equal(sportFrames[1].payload[4], 0x81050900)
    equal(sportFrames[3].payload[4], 0x030a0200)
    equal(sportFrames[2].payload[3], 0xfa07)
    equal(sportFrames[4].payload[3], 0xfa07)
    equal(sportFrames[2].payload[4], 0x81050964)
    equal(sportFrames[4].payload[4], 0x030a025a)
    header = config.copy(app.data.header)
    header.protocol = 1
    assert(commit(app, "config", header))
    sportFrames = {}
    advance(app, 4)
    equal(sportFrames[1].payload[3], 0xfa07)
    equal(sportFrames[3].payload[3], 0xfa07)
    equal(sportFrames[1].payload[4] & 255, 0)
    equal(sportFrames[3].payload[4] & 255, 0)
    equal(encode(sportFrames[2].payload), "0,49,20737,1")
    equal(encode(sportFrames[4].payload), "0,49,20736,4")
    header = config.copy(app.data.header)
    header.protocol = 2
    assert(commit(app, "config", header))
    sportFrames = {}
    advance(app, 4)
    equal(encode(sportFrames[1].payload), "0,49,20737,0")
    equal(encode(sportFrames[3].payload), "0,49,20736,0")
    equal(sportFrames[2].payload[3], 0xac00)
    equal(sportFrames[4].payload[3], 0xac00)
    header = config.copy(app.data.header)
    header.protocol = 0
    assert(commit(app, "config", header))
    sportFrames, frames = {}, {}
    advance(app, 4)
    equal(#sportFrames, 2)
    equal(sportFrames[1].payload[3], 0xac00)
    equal(sportFrames[2].payload[3], 0xac00)
    equal(sportFrames[1].payload[4] & 255, 0)
    equal(sportFrames[2].payload[4] & 255, 0)
    equal(encode(frames[1].payload), "0,234,161,9,2,1,0,1,0,0,4")
    equal(offCount(app.sender), 0)
end)

test("Blocked WM retirements do not starve ACW commands or ACW retirements", function()
    local data, previous, sender = config.defaults(), sport.new(), sport.new()
    data.header.protocol, data.controls = 1, {data.controls[1]}
    configure(previous, data, {[1] = 1})
    sport.tick(previous, 0)
    sportFrames = {}
    data.header.protocol = 2
    configure(sender, data, {[1] = 1})
    sport.retireGroup(sender, previous, previous.groups[1])
    local native = sportTelemetryPush
    sportTelemetryPush = function(physicalId, primId, dataId, value)
        local queued = native(physicalId, primId, dataId, value)
        if primId == 0x31 then return false end
        return queued
    end
    sport.tick(sender, 1)
    contains(sender.offError, "not accepted")
    sport.tick(sender, 2)
    equal(sportFrames[2].payload[4], 0x010001ff)
    sport.tick(sender, 3)
    sport.set(sender, 1, 0)
    sport.tick(sender, 4)
    equal(sportFrames[4].payload[4], 0x01000100)
    sport.retireProp(sender, sender, {key = 8, prefix = 0x01000900})
    sport.tick(sender, 5)
    equal(sportFrames[5].payload[4], 0x01000900)
    equal(#sender.off[2], 0)
    equal(#sender.off[1], 1)
    contains(sender.offError, "not accepted")
    sportTelemetryPush = native
end)

test("ACW editors map Momentary correctly and retain driver settings across sections and saves", function()
    local app = appInstance()
    ready(app)
    settleAutosave(app)
    local view = {zone = {w = 480, h = 272}, app = app, page = "control"}
    render(app, view)
    press("Setup")
    render(app, view)
    press("Global")
    render(app, view)
    form("Protocol:").set(3)
    render(app, view)
    assert(not find(function(item) return item.text == "Physical ID:" or item.text == "LED colors:" end))
    equal(app.data.header.protocol, 0)
    form("Protocol:").set(4)
    render(app, view)
    assert(find(function(item) return item.text == "Data ID: 0xfa07." end))
    press("Apply")
    render(app, view)
    equal(app.sender.variant, 3)
    press("Tab settings")
    render(app, view)
    press("Edit")
    render(app, view)
    equal(#form("Type:").values, 3)
    equal(form("Type:").values[3], "Momentary")
    form("Type:").set(3)
    render(app, view)
    equal(view.edit.type, 4)
    form("ACW type:").set(7)
    form("ACW options:").set(19)
    form("On PWM:").set(123)
    press("Inputs")
    render(app, view)
    press("Basic")
    render(app, view)
    equal(form("ACW type:").get(), 7)
    equal(form("ACW options:").get(), 19)
    equal(form("On PWM:").get(), 123)
    press("Apply")
    render(app, view)
    settleAutosave(app)
    local fresh = appInstance()
    ready(fresh)
    equal(fresh.controls[1].type, 4)
    fresh.set(1, 1)
    sportFrames = {}
    advance(fresh)
    equal(sportFrames[1].payload[3], 0xfa07)
    equal(sportFrames[1].payload[4], 0x0713017b)
end)

test("Simulator CRSF roundtrips through unused S.Port modes do not retain shutdown warnings", function()
    getVersion = function() return "3.0.0", "tx16s-simu" end
    serialWrite = function() end
    sportBlocked = true
    for variant = 1, 3 do
        local data = config.defaults()
        data.header.autoSave = 0
        local path = "roundtrip" .. variant
        finish(storage.save(path .. ".a.lua", data, 1), storage.stepSave)
        local app = appInstance(path)
        ready(app)
        app.set(7, 1)
        advance(app)
        local header = config.copy(app.data.header)
        header.protocol = variant
        assert(commit(app, "config", header))
        advance(app, 12)
        header = config.copy(app.data.header)
        header.name = "Unused S.Port"
        assert(commit(app, "config", header))
        header = config.copy(app.data.header)
        header.protocol = 0
        assert(commit(app, "config", header))
        local attempts = #sportFrames
        advance(app, 12)
        equal(#sportFrames, attempts, "Unused S.Port shutdown reached the transmit API")
        equal(app.sender.offError, nil)
        equal(offCount(app.sender), 0)
        equal(app.values[7], 1)
        save(app)
        contains(app.status(), "Configuration saved")
    end
end)

test("Accepted activity survives preparation and failed zero transmissions in every protocol", function()
    for variant = 0, 3 do
        blocked, sportBlocked = false, false
        local data = config.defaults()
        data.header.protocol, data.header.autoSave = variant, 0
        local path = "activity" .. variant
        finish(storage.save(path .. ".a.lua", data, 1), storage.stepSave)
        local app = appInstance(path)
        ready(app)
        app.set(1, 1)
        advance(app, 8)
        blocked, sportBlocked = true, true
        app.set(1, 0)
        advance(app, 2)
        local header = config.copy(app.data.header)
        header.name = "Preserve accepted activity"
        assert(commit(app, "config", header))
        header = config.copy(app.data.header)
        header.protocol = variant == 0 and 1 or 0
        assert(commit(app, "config", header))
        advance(app, 3)
        contains(app.sender.offError, "Retired output pending")
        blocked, sportBlocked = false, false
        advance(app, 25)
        equal(app.sender.offError, nil)
        equal(offCount(app.sender), 0)
    end
end)

test("Already accepted ordinary zero commands satisfy retirement without another transmission", function()
    for variant = 0, 3 do
        blocked, sportBlocked = false, false
        local data = config.defaults()
        data.header.protocol, data.header.autoSave = variant, 0
        local path = "zero" .. variant
        finish(storage.save(path .. ".a.lua", data, 1), storage.stepSave)
        local app = appInstance(path)
        ready(app)
        app.set(1, 1)
        advance(app, 8)
        app.set(1, 0)
        advance(app, 8)
        local header = config.copy(app.data.header)
        header.protocol = variant == 0 and 1 or 0
        assert(commit(app, "config", header))
        if variant == 0 then blocked = true else sportBlocked = true end
        local attempts = variant == 0 and #frames or #sportFrames
        advance(app, 12)
        equal(variant == 0 and #frames or #sportFrames, attempts)
        equal(app.sender.offError, nil)
        equal(offCount(app.sender), 0)
    end
end)

test("Late accepted activity during preparation still requires a retirement command", function()
    local data = config.defaults()
    data.header.autoSave = 0
    finish(storage.save("model.a.lua", data, 1), storage.stepSave)
    local app = appInstance()
    ready(app)
    blocked = true
    app.set(1, 1)
    local header = config.copy(app.data.header)
    header.protocol = 1
    local job = assert(app.commit("config", header))
    while not job.done do
        if job.phase == "retire-sliders" then blocked = false end
        advance(app)
    end
    assert(job.success, job.error)
    blocked = true
    advance(app, 2)
    contains(app.sender.offError, "Retired output pending: CRSF")
end)

test("Input, storage and transport failures recover independently without clearing configuration errors", function()
    local data = config.defaults()
    data.header.autoSave = 0
    for id = 1, 2 do
        data.controls[id].type, data.controls[id].source = 5, id + 8
    end
    finish(storage.save("model.a.lua", data, 1), storage.stepSave)
    local app = appInstance()
    ready(app)
    advance(app, 8)
    equal(app.inputErrorCount, 2)
    assert(app.inputErrors[1] and app.inputErrors[2])
    contains(app.operationStatus(), "Source unavailable")
    equal(app.error, nil)
    blocked, writeFailure = true, true
    app.set(3, 1)
    save(app)
    contains(app.saveError, "Save failed")
    contains(app.sender.error, "busy")
    sources[9] = 512
    advance(app, 8)
    equal(app.inputErrorCount, 1)
    equal(app.inputErrors[1], nil)
    contains(app.operationStatus(), "Output 2")
    contains(app.storageStatus(), "Save failed")
    blocked = false
    advance(app, 8)
    equal(app.sender.error, nil)
    contains(app.storageStatus(), "Save failed")
    blocked = true
    app.set(3, 0)
    local header = config.copy(app.data.header)
    header.autoSave = 2
    assert(not app.commit("config", header))
    local configurationError = app.error
    writeFailure = false
    save(app)
    equal(app.saveError, nil)
    equal(app.error, configurationError)
    contains(app.operationStatus(), "busy")
    equal(app.inputErrorCount, 1)
    blocked = false
    advance(app, 8)
    equal(app.sender.error, nil)
    equal(app.error, configurationError)
    equal(app.inputErrorCount, 1)
    sources[10] = 256
    advance(app, 8)
    equal(app.inputErrorCount, 0)
    equal(app.inputErrors[2], nil)
    equal(app.error, configurationError)
    equal(app.operationStatus(), "Outputs ready")
end)

test("Source errors follow preserved inputs and late recovery during preparation", function()
    local data = config.defaults()
    data.header.autoSave = 0
    data.controls[1].type, data.controls[1].source = 5, 9
    finish(storage.save("model.a.lua", data, 1), storage.stepSave)
    local app = appInstance()
    ready(app)
    advance(app, 8)
    equal(app.inputErrorCount, 1)
    local header = config.copy(app.data.header)
    header.name = "Preserved error"
    assert(commit(app, "config", header))
    equal(app.inputErrorCount, 1)
    contains(app.operationStatus(), "Source unavailable")
    header = config.copy(app.data.header)
    header.name = "Late recovery"
    local job = assert(app.commit("config", header))
    while job.phase ~= "retire-sliders" do advance(app) end
    sources[9] = 512
    finish(job, function() advance(app) end)
    assert(job.success, job.error)
    equal(app.inputErrorCount, 0)
    equal(app.inputErrors[1], nil)
    equal(app.values[1], 50)
    data = config.copy(app.controls[1])
    sources[9], data.source = nil, 0
    advance(app, 8)
    equal(app.inputErrorCount, 1)
    assert(commit(app, "control", data))
    equal(app.inputErrorCount, 0)
end)

test("Footer shows saving and real pending shutdowns on separate lines", function()
    local data = config.defaults()
    data.header.autoSave, data.header.protocol = 0, 1
    finish(storage.save("model.a.lua", data, 1), storage.stepSave)
    local app = appInstance()
    ready(app)
    app.set(1, 1)
    advance(app)
    sportBlocked = true
    local header = config.copy(app.data.header)
    header.protocol = 0
    assert(commit(app, "config", header))
    advance(app, 2)
    contains(app.operationStatus(), "Retired output pending")
    app.save()
    local view = {zone = {w = 480, h = 272}, app = app, tab = 1, page = "control"}
    render(app, view)
    assert(app.saveJob)
    local label = assert(find(function(item) return item.text == app.footerStatus end))
    local text = label.text()
    contains(text, "Saving configuration")
    contains(text, "\n")
    contains(text, "Retired output pending")
    equal(label.h, 44)
    contains(app.status(), "Saving configuration")
    contains(app.status(), "Retired output pending")
end)

test("S.Port rejected entries stay pending without starving other entries or hiding their errors", function()
    local native = sportTelemetryPush
    for variant = 1, 3 do
        local data, sender = config.defaults(), sport.new()
        data.header.protocol, data.header.interval = variant, 1000
        local extra = data.controls[4]
        data.controls = {data.controls[1], data.controls[2], data.controls[3]}
        for index, control in ipairs(data.controls) do control.address = index - 1 end
        if variant == 1 then
            extra.address = 0
            data.controls[4] = extra
        end
        configure(sender, data, {[1] = 1, [2] = 1, [3] = 1})
        local rejecting = true
        sportTelemetryPush = function(physicalId, primId, dataId, value)
            sportBlocked = rejecting and (variant == 1 and dataId == 0x5100
                or variant >= 2 and ((value >> 8) & 255) == 1)
            local result = native(physicalId, primId, dataId, value)
            sportBlocked = false
            return result
        end
        sportFrames = {}
        for time = 1, 3 do
            local before = #sportFrames
            sport.tick(sender, time)
            equal(#sportFrames - before, 1)
        end
        assert(sportFrames[1].blocked)
        assert(not sportFrames[2].blocked and not sportFrames[3].blocked)
        local list = variant == 1 and sender.groups or sender.props
        assert(list[1].dirty)
        equal(list[1].last, -100000)
        equal(sender.failedCount, 1)
        contains(sender.error, "not accepted")
        sport.set(sender, 1, 0)
        sport.tick(sender, 4)
        assert(sportFrames[4].blocked)
        equal(sender.failedCount, 1)
        local replacement = sport.new()
        configure(replacement, data, {})
        for _, control in ipairs(data.controls) do outputs.inherit(replacement, sender, control.id) end
        equal(replacement.failedCount, 1)
        contains(replacement.error, "not accepted")
        rejecting = false
        sport.tick(sender, 5)
        equal(#sportFrames, 5)
        equal(sportFrames[5].payload[4], variant == 1 and 0 or list[1].prefix)
        equal(sender.failedCount, 0)
        equal(sender.error, nil)
        equal(list[1].dirty, false)
        equal(list[1].last, 5)
    end
    sportTelemetryPush = native
end)

test("S.Port normal retry fairness never bypasses blocked same-mode shutdowns", function()
    local native = sportTelemetryPush
    for variant = 1, 3 do
        local data, previous = config.defaults(), sport.new()
        data.header.protocol, data.controls = variant, {data.controls[1]}
        configure(previous, data, {[1] = 1})
        sport.tick(previous, 0)
        data.controls[1].address = 1
        local sender = sport.new()
        configure(sender, data, {[1] = 1})
        if variant == 1 then sport.retireGroup(sender, previous, previous.groups[1])
        else sport.retireProp(sender, previous, previous.props[1]) end
        local rejecting = true
        sportTelemetryPush = function(physicalId, primId, dataId, value)
            sportBlocked = rejecting and (variant == 1 and dataId == 0x5100
                or variant >= 2 and ((value >> 8) & 255) == 1)
            local result = native(physicalId, primId, dataId, value)
            sportBlocked = false
            return result
        end
        sportFrames = {}
        for time = 1, 3 do
            sport.tick(sender, time)
            equal(#sportFrames, time)
            assert(sportFrames[time].blocked)
        end
        contains(sender.offError, "Retired output pending")
        equal(sender.groupCursor, 1)
        rejecting = false
        sport.tick(sender, 4)
        equal(#sportFrames, 4)
        equal(offCount(sender), 0)
        sport.tick(sender, 5)
        equal(#sportFrames, 5)
        equal(sportFrames[5].payload[4], variant == 1 and 1 or sender.props[1].prefix + 255)
    end
    sportTelemetryPush = native
end)

test("Restored transport APIs clear availability errors without requiring another packet", function()
    local data = config.defaults()
    data.header.interval, data.controls = 1000, {data.controls[1]}
    local sender = crsf.new()
    configure(sender, data, {})
    crsf.tick(sender, 1)
    local native = crossfireTelemetryPush
    crossfireTelemetryPush = nil
    crsf.tick(sender, 2)
    contains(sender.error, "API unavailable")
    crossfireTelemetryPush = native
    crsf.tick(sender, 3)
    equal(sender.error, nil)
    equal(#frames, 1)
    sender = sport.new()
    configure(sender, data, {})
    sport.tick(sender, 1)
    native = sportTelemetryPush
    sportTelemetryPush = nil
    sport.tick(sender, 2)
    contains(sender.error, "API unavailable")
    sportTelemetryPush = native
    sport.tick(sender, 3)
    equal(sender.error, nil)
    equal(#sportFrames, 1)
    getVersion = function() return "3.0.0", "tx16s-simu" end
    local writes = 0
    serialWrite = function() writes = writes + 1 end
    sender = crsf.new()
    configure(sender, data, {})
    crsf.tick(sender, 1)
    native = serialWrite
    serialWrite = nil
    crsf.tick(sender, 2)
    contains(sender.error, "API unavailable")
    serialWrite = native
    crsf.tick(sender, 3)
    equal(sender.error, nil)
    equal(writes, 1)
end)

test("Shared widgets read menu language once at startup and preserve stored names and revisions", function()
    local language, reads = "DE", 0
    getGeneralSettings = function() reads = reads + 1; return {language = language, voice = "en"} end
    local main = assert(loadfile(root .. "main.lua"))()
    local a = main.create({w = 480, h = 272}, {}, root)
    local b = main.create({w = 480, h = 272}, {}, root)
    equal(a.app, b.app)
    local data = config.defaults()
    data.header.name, data.header.autoSave = "Setup", 0
    data.tabs[1].name, data.controls[1].name = "Inputs", "Save"
    finish(storage.save(a.app.path .. ".a.lua", data, 1), storage.stepSave)
    local loader = loadScript
    local calls = 0
    loadScript = function(...)
        calls = calls + 1
        return loader(...)
    end
    for _ = 1, 200 do
        now, calls = now + 1, 0
        main.background(a)
        main.background(b)
        assert(calls <= 1, "Multiple module/catalog loads in one shared tick")
        if a.app.phase == "ready" then break end
    end
    local app = a.app
    equal(app.phase, "ready")
    equal(reads, 1)
    equal(app.i18n.language, "de")
    render(app, a)
    equal(a.uiJob.page.params.title, "Setup")
    equal(a.uiJob.page.params.subtitle, "Inputs (1/1)")
    equal(a.refs.c1.definition.text, "Save")
    press("Einstellungen")
    render(app, a)
    press("Global")
    render(app, a)
    equal(a.uiJob.page.params.title, "Widget-Einstellungen")
    local revision, writes = app.revision, writeCount
    form("Name:").set("Unsaved draft")
    language = "EN"
    advance(app, 120)
    render(app, a)
    equal(reads, 1)
    equal(app.i18n.language, "de")
    equal(a.edit.name, "Unsaved draft")
    equal(app.data.header.name, "Setup")
    equal(app.revision, revision)
    equal(writeCount, writes)
    equal(app.data.header.language, nil)
    equal(app.t("An untranslated message: %s", "test"), "An untranslated message: test")
end)

test("English fallback uses menu rather than voice language and supports older missing settings APIs", function()
    for index, menu in ipairs({"EN", "FR", ""}) do
        getGeneralSettings = function() return {language = menu, voice = "de"} end
        local app = appInstance("language" .. index)
        ready(app)
        equal(app.phase, "ready")
        equal(app.i18n.language, "en")
        equal(app.t("Save"), "Save")
        settleAutosave(app)
    end
    getGeneralSettings = nil
    local app = appInstance("without-language-api")
    ready(app)
    equal(app.phase, "ready")
    equal(app.i18n.language, "en")
    equal(app.t("Save"), "Save")
end)

test("German catalog failures stop initialization explicitly before configuration or output changes", function()
    getGeneralSettings = function() return {language = "de"} end
    local loader = loadScript
    for _, failure in ipairs({"missing", "broken", "invalid"}) do
        loadScript = function(path, mode)
            if not string.find(path, "lang/de.lua", 1, true) then return loader(path, mode) end
            if failure == "missing" then return nil, "catalog missing" end
            return function()
                if failure == "broken" then error("catalog broken") end
                return "not a catalog"
            end
        end
        local app = appInstance("catalog-" .. failure)
        ready(app)
        equal(app.phase, "error")
        contains(app.error, failure == "missing" and "Cannot load language" or "Invalid language catalog")
        if failure ~= "invalid" then contains(app.error, "catalog " .. failure) end
        equal(writeCount, 0)
        equal(#frames, 0)
        equal(#sportFrames, 0)
    end
end)

test("German editors keep section and type identifiers stable and serialize only applied configuration", function()
    local data = config.defaults()
    data.header.autoSave, data.controls[1].name = 0, "My output"
    finish(storage.save("model.a.lua", data, 1), storage.stepSave)
    getGeneralSettings = function() return {language = "DE", voice = "en"} end
    local app = appInstance()
    ready(app)
    local view = {zone = {w = 480, h = 272}, app = app, page = "control"}
    render(app, view)
    press("Einstellungen")
    render(app, view)
    press("Tab Einstellungen")
    render(app, view)
    equal(view.uiJob.page.params.title, "Tab-Einstellungen")
    press("Bearbeiten")
    render(app, view)
    equal(view.uiJob.page.params.title, "Element-Einstellungen")
    equal(view.uiJob.page.params.subtitle, "My output")
    form("Name:").set("Tür links")
    equal(form("Art:").values[4], "Taster")
    form("Art:").set(4)
    render(app, view)
    equal(view.edit.type, 4)
    press("Eingänge")
    render(app, view)
    equal(view.editSection, "Inputs")
    form("Schalter:").set(23)
    press("Aussehen")
    render(app, view)
    equal(view.editSection, "Appearance")
    assert(form("Farbe:"))
    press("Allgemein")
    render(app, view)
    equal(view.editSection, "Basic")
    equal(form("Name:").value, "Tür links")
    press("Anwenden")
    render(app, view)
    equal(app.controls[1].name, "Tür links")
    equal(app.controls[1].type, 4)
    equal(app.controls[1].switch, 23)
    press("Speichern")
    finish({done = false}, function(job)
        advance(app)
        job.done = not app.saveJob
    end)
    equal(app.saveError, nil)
    contains(fs["model.b.lua"], 'kind="control"')
    local reader = storage.load("model.b.lua")
    finish(reader, storage.stepLoad)
    assert(reader.result, reader.error)
    equal(reader.result.controls[1].name, "Tür links")
    equal(reader.result.controls[1].type, 4)
    equal(reader.result.header.protocol, 0)
    equal(reader.result.header.language, nil)
end)

test("German runtime, storage and validation errors retain independent recovery", function()
    local data = config.defaults()
    data.header.autoSave = 0
    data.controls[1].type, data.controls[1].source = 5, 9
    finish(storage.save("model.a.lua", data, 1), storage.stepSave)
    getGeneralSettings = function() return {language = "DE"} end
    local app = appInstance()
    ready(app)
    advance(app, 8)
    contains(app.operationStatus(), "Quelle nicht verfügbar")
    blocked, writeFailure = true, true
    app.set(2, 1)
    save(app)
    contains(app.storageStatus(), "Speichern fehlgeschlagen")
    contains(app.operationStatus(), "CRSF-Sendewarteschlange belegt")
    sources[9] = 512
    advance(app, 8)
    equal(app.inputErrorCount, 0)
    contains(app.storageStatus(), "Speichern fehlgeschlagen")
    local control = app.config.copy(app.controls[1])
    control.output = 9
    assert(not app.commit("control", control))
    contains(app.error, "Ungültig: control.output")
    local native = crossfireTelemetryPush
    crossfireTelemetryPush = nil
    advance(app)
    equal(app.sender.error, "CRSF-API nicht verfügbar")
    crossfireTelemetryPush, blocked = native, false
    advance(app, 8)
    equal(app.sender.error, nil)
    contains(app.storageStatus(), "Speichern fehlgeschlagen")
    fs["bad.a.lua"] = "return {\n"
    local parser = app.storage.load("bad.a.lua")
    finish(parser, app.storage.stepLoad)
    contains(parser.error, "Unvollständige Konfigurationsdatei")
end)

test("German global forms anchor actions at the bottom with scrollable two-line status", function()
    getGeneralSettings = function() return {language = "DE"} end
    local app = appInstance()
    ready(app)
    settleAutosave(app)
    for _, screen in ipairs({{480, 272, 227}, {320, 240, 204}, {800, 480, 412}}) do
        LCD_W, LCD_H = screen[1], screen[2]
        lvgl.PAGE_BODY_HEIGHT = screen[3]
        if LCD_W == 800 then lvgl.UI_ELEMENT_HEIGHT = 48 else lvgl.UI_ELEMENT_HEIGHT = nil end
        local view = {zone = {w = LCD_W, h = LCD_H}, app = app, page = "editor",
                      editKind = "config", edit = app.config.copy(app.data.header), editRevision = app.revision}
        render(app, view)
        equal(view.uiJob.page.params.title, "Widget-Einstellungen")
        assert(form("Auto-Speichern:") and form("Protokoll:"))
        local content, actions, status = view.refs.settings.definition, view.refs.actions.definition, view.refs.status.definition
        assert(content.h > 0 and content.y + content.h < actions.y)
        equal(actions.y + actions.h, screen[3])
        equal(view.uiJob.page.params.scrollDir, lvgl.SCROLL_VER)
        assert(view.refs.statusSeparator.definition.y >= screen[3])
        assert(status.y >= view.refs.statusSeparator.definition.y + 1)
        contains(status.text(), "Konfiguration gespeichert")
    end
end)

test("German catalog formatting preserves source placeholders and literal percentages", function()
    getGeneralSettings = function() return {language = "DE"} end
    local i18n = assert(loadfile(root .. "i18n.lua"))({dir = root})
    assert(i18n.step())
    local catalog = assert(loadfile(root .. "lang/de.lua"))()
    for source, translation in pairs(catalog) do
        local arguments, sourceFormats, translatedFormats = {}, {}, {}
        for format in string.gmatch(source, "%%[sd]") do
            sourceFormats[#sourceFormats + 1] = format
            arguments[#arguments + 1] = format == "%d" and 3 or "value"
        end
        for format in string.gmatch(translation, "%%[sd]") do translatedFormats[#translatedFormats + 1] = format end
        equal(table.concat(sourceFormats), table.concat(translatedFormats), source)
        equal(i18n.t(source, table.unpack(arguments)), #arguments == 0 and translation
            or string.format(translation, table.unpack(arguments)), source)
    end
    equal(i18n.p("button", "Tab settings"), "Tab Einstellungen")
    equal(i18n.t("Tab settings"), "Tab-Einstellungen")
    contains(i18n.t("Source: 0..1024 = 0..100%; negative values = 0%."), "100%")
end)

local function memoryTool()
    EVT_VIRTUAL_ENTER, EVT_VIRTUAL_EXIT, EVT_VIRTUAL_NEXT, EVT_VIRTUAL_PREV = 1001, 1002, 1003, 1004
    getAvailableMemory = function() return 8 * 1024 * 1024 - collectgarbage("count") * 1024 end
    lcd.clear = function() end
    local counters = {records = 0, modules = 0, opens = 0}
    local open = io.open
    io.open = function(path, mode)
        equal(path, "/LOGS/swngmem.csv", "Diagnostic touched a configuration file")
        equal(mode, "a")
        counters.opens = counters.opens + 1
        return open(path, mode)
    end
    loadScript = function(path, mode)
        counters.modules = counters.modules + 1
        equal(mode, "tx", "Diagnostic must not generate binary cache files")
        local name = assert(string.match(path, "^/WIDGETS/lvglMultiSwNG/([%w/]+)%.lua$"))
        local chunk = assert(loadfile(root .. name .. ".lua"))
        return function(argument)
            local result = chunk(argument)
            if name == "config" then
                local append = result.append
                result.append = function(...)
                    counters.records = counters.records + 1
                    return append(...)
                end
            end
            return result
        end
    end
    crossfireTelemetryPush = function() error("Diagnostic transmitted CRSF") end
    sportTelemetryPush = function() error("Diagnostic transmitted S.Port") end
    serialWrite = function() error("Diagnostic wrote to the serial port") end
    local tool = assert(loadfile(root .. "tools/swngmem.lua"))()
    tool.init()
    local function run(event)
        counters.records, counters.modules = 0, 0
        local result = tool.run(event)
        assert(counters.records <= 1, "Diagnostic processed multiple configuration records")
        assert(counters.modules <= 1, "Diagnostic loaded multiple modules")
        return result
    end
    return tool, run, counters
end

test("On-radio memory diagnostic profiles all protocols and sizes without outputs or configuration writes", function()
    local _, run, counters = memoryTool()
    for profile = 1, 30 do
        local opens = counters.opens
        run(EVT_VIRTUAL_ENTER)
        for _ = 1, 2100 do
            if counters.opens > opens then break end
            run(0)
        end
        equal(counters.opens, opens + 1, "Diagnostic did not finish the selected profile")
        local log = fs["/LOGS/swngmem.csv"]
        contains(log, '"complete"')
        assert(not string.find(log, '"error"', 1, true), log)
        assert(not string.find(log, '"stopped"', 1, true), log)
        local _, lines = string.gsub(log, "\n", "")
        equal(lines, profile + 1, "Diagnostic overwrote previous results")
        if profile < 30 then run(EVT_VIRTUAL_NEXT) end
    end
    contains(fs["/LOGS/swngmem.csv"], '"ACW 1.4",255,32,')
    contains(fs["/LOGS/swngmem.csv"], '"CRSF sliders",256,32,')
    contains(fs["/LOGS/swngmem.csv"], '"Empty tabs",0,256,')
    equal(#frames, 0)
    equal(#sportFrames, 0)
    equal(run(EVT_VIRTUAL_EXIT), 2)
end)

test("Memory diagnostic stops at its heap reserve and records incomplete measurements explicitly", function()
    local _, run, counters = memoryTool()
    run(EVT_VIRTUAL_ENTER)
    for _ = 1, 20 do
        run(0)
        if counters.records > 0 then break end
    end
    equal(counters.records, 1)
    getAvailableMemory = function() return 1024 end
    run(0)
    equal(counters.records, 0)
    equal(counters.opens, 1)
    contains(fs["/LOGS/swngmem.csv"], '"stopped","Heap reserve reached"')
    assert(not string.find(fs["/LOGS/swngmem.csv"], '"complete"', 1, true))
    run(0)
    equal(counters.opens, 1)
    equal(run(EVT_VIRTUAL_EXIT), 2)
end)

test("Memory diagnostic surfaces module and CSV failures and supports cancellation", function()
    local _, run = memoryTool()
    loadScript = function() return nil, "missing diagnostic module" end
    run(EVT_VIRTUAL_ENTER)
    contains(fs["/LOGS/swngmem.csv"], '"error"')
    contains(fs["/LOGS/swngmem.csv"], "missing diagnostic module")
    equal(run(EVT_VIRTUAL_EXIT), 2)
    local _, nextRun, counters = memoryTool()
    local displayed = {}
    lcd.drawText = function(_, _, text) displayed[#displayed + 1] = text end
    nextRun(EVT_VIRTUAL_ENTER)
    writeFailure = true
    nextRun(EVT_VIRTUAL_EXIT)
    equal(counters.opens, 1)
    contains(table.concat(displayed, "\n"), "Cancelled by user; SD full")
    writeFailure = false
    nextRun(EVT_VIRTUAL_ENTER)
    nextRun(0)
    nextRun(EVT_VIRTUAL_EXIT)
    contains(fs["/LOGS/swngmem.csv"], '"cancelled","Cancelled by user"')
    equal(nextRun(EVT_VIRTUAL_EXIT), 2)
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
