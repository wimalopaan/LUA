-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 Wilhelm Meier
-- Run from SCRIPTS/TOOLS: lua ../LIB/mswNG/tests/run.lua

local root = string.match(arg[0], "^(.*)tests/") or ""
local hostIO = io
local stringMeta = debug.getmetatable("")
debug.setmetatable("", nil)
local core = assert(loadfile(root .. "core.lua"))()
local storage = assert(loadfile(root .. "storage.lua"))(core)
local fs, frames, now, blocked, inactive, writeError, truncate, draws, loads, lastX, handles, switchValues
local peakInstructions = 0
local rightAligned
local lastLeft, valueLeft

local function equal(actual, expected)
    assert(actual == expected, "expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

local function reset()
    fs, frames, now, draws, loads, handles = {}, {}, 0, {}, {}, 0
    blocked, inactive, writeError, truncate = false, false, false, false
    switchValues = {}
    getSwitchValue = function(id) return switchValues[id] end
    getSwitchName = function(id)
        return ({[1] = "SAup", [-1] = "!SAup", [101] = "L01", [-101] = "!L01"})[id]
    end
    switches = function()
        local ids, index = {-101, -1, 0, 1, 101}, 0
        return function() index = index + 1; return ids[index] end
    end
    io = {
        open = function(path, mode)
            if mode == "r" and not fs[path] then return nil, "file error", 2 end
            if mode == "w" then fs[path] = "" end
            handles = handles + 1
            return {path = path, mode = mode, offset = 1}
        end,
        read = function(file, size)
            assert(not file.closed and size <= 96)
            local text = string.sub(fs[file.path], file.offset, file.offset + size - 1)
            file.offset = file.offset + #text
            return text
        end,
        write = function(file, text)
            assert(not file.closed and #text < 96)
            if writeError then return nil, "SD full" end
            fs[file.path] = fs[file.path] .. text
            return file
        end,
        close = function(file)
            assert(not file.closed)
            file.closed = true
            handles = handles - 1
            if truncate and file.mode == "w" then fs[file.path] = string.sub(fs[file.path], 1, -3) end
        end,
    }
    fstat = function(path) if fs[path] then return {size = #fs[path]} end end
    model = {getInfo = function() return {name = "Model/1"} end}
    getTime = function() return now end
    crossfireTelemetryPush = function(kind, payload)
        equal(kind, 0x32)
        assert(#payload <= 59)
        local copy = {}
        for i, value in ipairs(payload) do
            assert(value >= 0 and value <= 255 and value % 1 == 0)
            copy[i] = value
        end
        frames[#frames + 1] = copy
        if inactive then return nil end
        return not blocked
    end
    loadScript = function(path)
        local name = string.match(path, "([^/]+)$")
        loads[name] = (loads[name] or 0) + 1
        return loadfile(root .. name)
    end
    EVT_ENTER_FIRST, EVT_ENTER_BREAK, EVT_ENTER_LONG, EVT_ENTER_REPT = 0x61, 0x21, 0x81, 0x41
    EVT_MENU_FIRST, EVT_MENU_BREAK, EVT_MENU_LONG, EVT_MENU_REPT = 0x62, 0x22, 0x82, 0x42
    EVT_VIRTUAL_NEXT, EVT_VIRTUAL_PREV, EVT_VIRTUAL_ENTER, EVT_VIRTUAL_EXIT = 1, 2, EVT_ENTER_BREAK, 4
    EVT_VIRTUAL_NEXT_PAGE, EVT_VIRTUAL_PREV_PAGE, EVT_VIRTUAL_MENU = 5, 6, EVT_MENU_BREAK
    SMLSIZE, INVERS, BLINK, RIGHT = 1, 2, 4, 8
    LCD_W, LCD_H = 128, 64
    lcd = {
        clear = function() draws = {}; rightAligned = {}; valueLeft = {}; lastX, lastLeft = 0, 0 end,
        drawText = function(x, y, text, flags)
            assert(x >= 0 and x <= LCD_W and y >= 0 and y + 8 <= LCD_H)
            text = tostring(text)
            local right = math.floor((flags or 0) / RIGHT) % 2 == 1
            local left = right and x - #text * 5 or x
            assert(left >= 0 and left + #text * 5 <= LCD_W, "Text overflows screen: " .. text)
            lastX, lastLeft = left + #text * 5, left
            if right and #text > 0 then
                rightAligned[text], valueLeft[y] = x, left
            elseif not right and valueLeft[y] then
                assert(lastX + 3 <= valueLeft[y], "Label overlaps value: " .. text)
            end
            draws[#draws + 1] = text
        end,
        getLastPos = function() return lastX end,
        getLastLeftPos = function() return lastLeft end,
        drawRectangle = function(x, y, w, h)
            assert(w > 0 and h > 0 and x >= 0 and y >= 0 and x + w <= LCD_W and y + h <= LCD_H)
        end,
    }
    lcd.drawFilledRectangle = lcd.drawRectangle
end

local function finish(job)
    for _ = 1, 1000 do
        if job.done then equal(handles, 0); return job end
        storage.step(job)
    end
    error("storage job never finished")
end

local function packet(...)
    local expected = {...}
    equal(#frames[#frames], #expected)
    for i, value in ipairs(expected) do equal(frames[#frames][i], value) end
end

local function tick(sender, config)
    now = now + 1
    core.tick(sender, config, now)
end

local function run(tool, event)
    local instructions = 0
    debug.sethook(function() instructions = instructions + 100 end, "", 100)
    local result = tool.run(event or 0)
    debug.sethook()
    peakInstructions = math.max(peakInstructions, instructions)
    now = now + 1
    return result
end

local function tool(telemetry)
    local entry = telemetry and "../../TELEMETRY/mswNG.lua" or "../../TOOLS/mswNG.lua"
    local t = assert(loadfile(root .. entry))()
    t.init()
    for _ = 1, 300 do run(t) end
    return t
end

local function background(t)
    local savedLCD = lcd
    lcd = setmetatable({}, {__index = function() error("LCD accessed in background") end})
    t.background()
    lcd = savedLCD
    now = now + 1
end

local function see(fragment)
    for _, text in ipairs(draws) do
        if string.find(text, fragment, 1, true) then return true end
    end
    error("not on screen: " .. fragment .. " (" .. table.concat(draws, "|") .. ")")
end

reset()
local config = core.defaults()
equal(#config.pages, 1)
equal(#config.pages[1][2], 8)
for _ = 1, 3 do assert(core.addPage(config)) end
assert(not core.addPage(config))
for p, page in ipairs(config.pages) do
    equal(page[1], p - 1)
    for _ = 1, 4 do assert(core.addSwitch(config, page)) end
    equal(#page[2], 12)
    assert(not core.addSwitch(config, page))
end
assert(core.validate(config))
local c = config.pages[1][2][1]
assert(not core.route(config, config.pages[1], c, 1, 1))
assert(not core.pageAddress(config, config.pages[1], 1))
equal(config.pages[1][1], 0)
assert(core.route(config, config.pages[1], c, 255, 8))
equal(c[4], 0)
assert(core.validate(config))
local invalid = core.defaults()
invalid.pages[1][2][1][3] = 9
assert(not core.validate(invalid))
invalid.pages[1][2][1][3] = 1
invalid.pages[1][2][1][1] = "\1"
assert(not core.validate(invalid))

reset()
config = core.defaults()
local sender = core.sender()
config.pages[1][2][1][4] = 1
config.pages[1][2][6][4] = 1
core.rebuild(sender, config)
tick(sender, config)
packet(0, 0xea, 0xa1, 0x07, 0, 4, 1)
local count = #frames
tick(sender, config)
equal(#frames, count)
now = now + config.interval
tick(sender, config)
equal(#frames, count + 1)
assert(core.addPage(config))
config.pages[2][2][8][4] = 1
core.rebuild(sender, config)
blocked = true
tick(sender, config)
packet(0, 0xea, 0xa1, 0x09, 2, 0, 4, 1, 1, 64, 0)
assert(sender.pending and sender.error)
blocked, inactive = false, true
tick(sender, config)
assert(sender.pending and sender.error == "CRSF/ELRS inaktiv")
inactive = false
tick(sender, config)
assert(not sender.pending and not sender.error)
table.remove(config.pages)
core.rebuild(sender, config)
blocked = true
tick(sender, config)
packet(0, 0xea, 0xa1, 0x09, 2, 0, 4, 1, 1, 0, 0)
equal(#sender.groups, 2)
blocked = false
tick(sender, config)
equal(#sender.groups, 1)
assert(not sender.map[1])
-- Removing one output must preserve another active output at the same address.
table.remove(config.pages[1][2], 1)
core.rebuild(sender, config)
tick(sender, config)
packet(0, 0xea, 0xa1, 0x07, 0, 4, 0)
assert(core.pageAddress(config, config.pages[1], 42))
core.rebuild(sender, config)
tick(sender, config)
packet(0, 0xea, 0xa1, 0x09, 2, 0, 0, 0, 42, 0, 0)
equal(sender.groups[1].address, 42)

-- Forty-eight addresses require three bounded packets; a full FIFO must retry the same chunk.
reset()
config = {interval = 100, pages = {}}
for p = 1, 4 do
    local page = {p - 1, {}, "mswNG"}
    config.pages[p] = page
    for s = 1, 12 do page[2][s] = {"S" .. s, (p - 1) * 12 + s - 1, 8, 1} end
end
assert(core.validate(config))
sender = core.sender()
core.rebuild(sender, config)
tick(sender, config)
equal(frames[1][5], 18)
equal(#frames[1], 59)
blocked = true
tick(sender, config)
equal(frames[2][6], 18)
equal(sender.cursor, 19)
blocked = false
tick(sender, config)
equal(frames[3][6], 18)
tick(sender, config)
equal(frames[4][5], 12)
assert(not sender.pending)
crossfireTelemetryPush = nil
tick(sender, config)
equal(sender.error, "CRSF API fehlt")

-- Physical/logical/inverted assignments follow EdgeTX, with one rebuild for a batch.
reset()
config = core.defaults()
config.pages[1][2][1][5] = 1
config.pages[1][2][2][5] = 101
config.pages[1][2][3][5] = -1
config.pages[1][2][4][4] = 1
sender = core.sender()
switchValues[1], switchValues[101], switchValues[-1] = true, false, false
local rebuild, rebuildCount = core.rebuild, 0
core.rebuild = function(...)
    rebuildCount = rebuildCount + 1
    return rebuild(...)
end
core.poll(sender, config)
equal(rebuildCount, 1)
tick(sender, config)
packet(0, 0xea, 0xa1, 0x07, 0, 0, 65)
switchValues[1], switchValues[101], switchValues[-1] = false, true, true
core.poll(sender, config)
equal(rebuildCount, 2)
tick(sender, config)
packet(0, 0xea, 0xa1, 0x07, 0, 0, 84)
core.poll(sender, config)
equal(rebuildCount, 2)
config.pages[1][2][2][5] = 999
core.poll(sender, config)
equal(config.pages[1][2][2][4], 0)
assert(sender.inputError)
getSwitchValue = nil
core.poll(sender, config)
equal(config.pages[1][2][3][4], 0)
equal(config.pages[1][2][4][4], 1)
equal(sender.inputError, "Schalter API fehlt")
core.rebuild = rebuild

-- Two independent slots, read-back verification, recovery and strict parsing.
reset()
local path = storage.path()
assert(string.find(path, "model-4d6f64656c2f31", 1, true))
local missing = finish(storage.load(path))
assert(not missing.error and not missing.result)
config = core.defaults()
config.pages[1][3] = "Deck / Licht"
config.pages[1][2][1][1] = 'Licht "A"'
config.pages[1][2][1][5] = -101
config.menuAction = 1
config.pages[1][2][2][6], config.pages[1][2][2][4] = 1, 1
local saved = finish(storage.save(path, config, 0, 0))
assert(not saved.error)
equal(saved.slot, 1)
local first = fs[path .. ".a"]
config.pages[1][2][1][1] = "Heck"
config.pages[1][3] = "Maschinenraum"
saved = finish(storage.save(path, config, saved.slot, saved.generation))
assert(not saved.error)
equal(saved.slot, 2)
equal(fs[path .. ".a"], first)
local loaded = finish(storage.load(path))
equal(loaded.result.pages[1][2][1][1], "Heck")
equal(loaded.result.pages[1][2][1][5], -101)
equal(loaded.result.pages[1][3], "Maschinenraum")
equal(loaded.result.menuAction, 1)
equal(loaded.result.pages[1][2][2][6], 1)
equal(loaded.result.pages[1][2][2][4], 0)
equal(loaded.generation, 2)
local second = fs[path .. ".b"]
fs[path .. ".b"] = string.gsub(second, "4865636b", "4865636a")
loaded = finish(storage.load(path))
assert(loaded.warning and not loaded.error)
equal(loaded.generation, 1)
fs[path .. ".b"] = second .. "unexpected\n"
loaded = finish(storage.load(path))
assert(loaded.warning and not loaded.error)
equal(loaded.generation, 1)
fs[path .. ".b"] = second
fs[path .. ".b"] = string.sub(fs[path .. ".b"], 1, -5)
loaded = finish(storage.load(path))
assert(loaded.warning and not loaded.error)
equal(loaded.result.pages[1][2][1][1], 'Licht "A"')
equal(loaded.result.pages[1][3], "Deck / Licht")
writeError = true
local failed = finish(storage.save(path, config, loaded.slot, loaded.generation))
assert(failed.error)
equal(fs[path .. ".a"], first)
writeError, truncate = false, true
failed = finish(storage.save(path, config, loaded.slot, loaded.generation))
assert(failed.error)
equal(fs[path .. ".a"], first)
truncate = false
fs[path .. ".a"], fs[path .. ".b"] = "not a config\n", string.rep("x", 400)
loaded = finish(storage.load(path))
assert(loaded.error and not loaded.result)
equal(handles, 0)

-- Force preemption in any gsub callback, reproducing EdgeTX's C-call yield boundary.
reset()
local nativeGsub = string.gsub
string.gsub = function(text, pattern, replacement)
    if type(replacement) == "function" then
        local callback = replacement
        replacement = function(...)
            coroutine.yield()
            return callback(...)
        end
    end
    return nativeGsub(text, pattern, replacement)
end
local nativeRead, nativeWrite = io.read, io.write
io.read = function(...) coroutine.yield(); return nativeRead(...) end
io.write = function(...) coroutine.yield(); return nativeWrite(...) end
local thread = coroutine.create(function()
    model.getInfo = function() return {name = "M/\195\164"} end
    local storagePath = storage.path()
    equal(storagePath, "/SCRIPTS/LIB/mswNG/model-4d2fc3a4")
    local data = core.defaults()
    data.pages[1][2][1][1] = '!"#% /9AZaz~'
    local written = finish(storage.save(storagePath, data, 0, 0))
    assert(not written.error, written.error)
    local restored = finish(storage.load(storagePath))
    assert(not restored.error, restored.error)
    equal(restored.result.pages[1][2][1][1], data.pages[1][2][1][1])
end)
while coroutine.status(thread) ~= "dead" do
    local ok, err = coroutine.resume(thread)
    assert(ok, err)
end
string.gsub = nativeGsub
equal(handles, 0)

-- Existing mswNG files keep their settings but always send to broadcast.
reset()
path = storage.path()
local legacy = "MSNG 1 7 1 100 238\nP 12 1\nS -1 8 0 4c6567616379\n"
local legacySum = 0
for i = 1, #legacy do legacySum = (legacySum * 33 + string.byte(legacy, i)) % 65521 end
fs[path .. ".a"] = legacy .. "E " .. legacySum .. "\n"
loaded = finish(storage.load(path))
assert(not loaded.error, loaded.error)
equal(loaded.result.destination, nil)
equal(loaded.result.pages[1][1], 12)
equal(loaded.result.pages[1][3], "Funktionen")
equal(loaded.result.pages[1][2][1][1], "Legacy")
loaded.result.pages[1][2][1][4] = 1
sender = core.sender()
core.rebuild(sender, loaded.result)
tick(sender, loaded.result)
packet(0x00, 0xea, 0xa1, 0x07, 12, 64, 0)
saved = finish(storage.save(path, loaded.result, loaded.slot, loaded.generation))
assert(not saved.error, saved.error)
assert(string.find(fs[path .. ".b"], "MSNG 4 8 1 100 0\n", 1, true) == 1)
loaded = finish(storage.load(path))
assert(not loaded.error, loaded.error)
equal(loaded.generation, 8)
legacy = "MSNG 2 9 1 100\nP 12 1\nS -1 8 0 4c6567616379\n"
legacySum = 0
for i = 1, #legacy do legacySum = (legacySum * 33 + string.byte(legacy, i)) % 65521 end
fs[path .. ".a"] = legacy .. "E " .. legacySum .. "\n"
loaded = finish(storage.load(path))
assert(not loaded.error, loaded.error)
equal(loaded.generation, 9)
equal(loaded.result.pages[1][3], "Funktionen")
legacy = "MSNG 3 10 1 100\nP 12 1 4465636b\nS -1 8 0 4c6567616379\n"
legacySum = 0
for i = 1, #legacy do legacySum = (legacySum * 33 + string.byte(legacy, i)) % 65521 end
fs[path .. ".b"] = legacy .. "E " .. legacySum .. "\n"
loaded = finish(storage.load(path))
assert(not loaded.error, loaded.error)
equal(loaded.result.pages[1][3], "Deck")
equal(loaded.result.menuAction, 0)
equal(loaded.result.pages[1][2][1][6], 0)

for _, fields in ipairs({{4, "0"}, {1, "2"}, {1, ""}}) do
    reset()
    local malformed = "MSNG 4 1 1 100 " .. fields[1] .. "\nP 0 1 4465636b\nS -1 1 0 " ..
        fields[2] .. " 4c69636874\n"
    local sum = 0
    for i = 1, #malformed do sum = (sum * 33 + string.byte(malformed, i)) % 65521 end
    fs[storage.path() .. ".a"] = malformed .. "E " .. sum .. "\n"
    loaded = finish(storage.load(storage.path()))
    assert(loaded.error and not loaded.result)
end

-- Editor navigation, transactional edits, names, page deletion and endpoint retirement.
reset()
local app = {core = core, config = core.defaults(), sender = core.sender(), page = 1}
local changed = 0
app.changed = function() changed = changed + 1; core.rebuild(app.sender, app.config) end
local editor = assert(loadfile(root .. "editor.lua"))(app)
editor.run(EVT_VIRTUAL_ENTER)
for _ = 1, 3 do editor.run(EVT_VIRTUAL_NEXT) end
editor.run(EVT_VIRTUAL_ENTER)
equal(#app.config.pages, 4)
editor.run(EVT_VIRTUAL_ENTER)
editor.run(EVT_VIRTUAL_PREV)
editor.run(EVT_VIRTUAL_ENTER)
assert(editor.confirm)
editor.run(EVT_VIRTUAL_EXIT)
equal(#app.config.pages, 4)
editor.run(EVT_VIRTUAL_ENTER)
editor.run(EVT_VIRTUAL_PREV)
editor.run(EVT_VIRTUAL_ENTER)
editor.run(EVT_VIRTUAL_ENTER)
equal(#app.config.pages, 3)
editor.row = 2
editor.run(EVT_VIRTUAL_ENTER)
equal(editor.screen, "page")
editor.row = 2
editor.run(EVT_VIRTUAL_ENTER)
equal(editor.length, 20)
editor.value = "Deckbeleuchtung     "
editor.run(EVT_VIRTUAL_NEXT_PAGE)
equal(app.config.pages[1][3], "Deckbeleuchtung")
editor.run(EVT_VIRTUAL_ENTER)
editor.run(EVT_VIRTUAL_NEXT)
editor.run(EVT_VIRTUAL_EXIT)
equal(app.config.pages[1][3], "Deckbeleuchtung")
editor.run(EVT_VIRTUAL_ENTER)
editor.value = string.rep(" ", 20)
editor.run(EVT_VIRTUAL_NEXT_PAGE)
equal(app.message, "Titel darf nicht leer sein")
equal(app.config.pages[1][3], "Deckbeleuchtung")
app.message = nil
editor.run(EVT_VIRTUAL_EXIT)
editor.row = 12
editor.run(EVT_VIRTUAL_ENTER)
equal(#app.config.pages[1][2], 9)
equal(editor.screen, "control")
editor.run(EVT_VIRTUAL_ENTER)
editor.run(EVT_VIRTUAL_NEXT)
editor.run(EVT_VIRTUAL_NEXT_PAGE)
equal(string.sub(app.config.pages[1][2][9][1], 1, 1), "B")
editor.row = 2
editor.run(EVT_VIRTUAL_ENTER)
editor.value = 0
editor.run(EVT_VIRTUAL_ENTER)
equal(app.message, "Adresse/Ausgang belegt")
equal(app.config.pages[1][2][9][2], 3)
app.message = nil
editor.run(EVT_VIRTUAL_EXIT)
app.config.pages[1][2][9][4] = 1
core.rebuild(app.sender, app.config)
tick(app.sender, app.config)
editor.row = 6
editor.run(EVT_VIRTUAL_ENTER)
editor.run(EVT_VIRTUAL_ENTER)
equal(#app.config.pages[1][2], 8)
tick(app.sender, app.config)
assert(not app.sender.map[3])
assert(changed > 0)

editor.screen, editor.row, editor.control = "control", 4, 1
editor.run(EVT_VIRTUAL_ENTER)
equal(editor.editing, "switch")
for _ = 1, 3 do editor.run(EVT_VIRTUAL_NEXT) end
equal(editor.displayValue(), "SAup")
editor.run(EVT_VIRTUAL_ENTER)
equal(app.config.pages[1][2][1][5], 1)
editor.run(EVT_VIRTUAL_ENTER)
editor.run(EVT_VIRTUAL_NEXT)
equal(editor.displayValue(), "L01")
editor.run(EVT_VIRTUAL_EXIT)
equal(app.config.pages[1][2][1][5], 1)
editor.run(EVT_VIRTUAL_ENTER)
for _ = 1, 3 do editor.run(EVT_VIRTUAL_PREV) end
editor.run(EVT_VIRTUAL_ENTER)
equal(app.config.pages[1][2][1][5], 0)
local nativeSwitches = switches
switches = nil
editor.run(EVT_VIRTUAL_ENTER)
equal(app.message, "Schalterauswahl fehlt")
app.message, switches = nil, nativeSwitches

editor.screen, editor.row = "global", 3
editor.run(EVT_VIRTUAL_ENTER)
editor.run(EVT_VIRTUAL_NEXT)
editor.run(EVT_VIRTUAL_ENTER)
equal(app.config.interval, 105)
editor.row = 4
editor.run(EVT_VIRTUAL_ENTER)
equal(editor.displayValue(), "Aus")
for _, label in ipairs({"Bedienung", "Naechste Seite", "Setup"}) do
    editor.run(EVT_VIRTUAL_NEXT)
    equal(editor.displayValue(), label)
end
editor.run(EVT_VIRTUAL_EXIT)
equal(app.config.menuAction, 0)
editor.run(EVT_VIRTUAL_ENTER)
editor.run(EVT_VIRTUAL_NEXT)
editor.run(EVT_VIRTUAL_ENTER)
equal(app.config.menuAction, 1)
editor.screen, editor.row = "control", 5
editor.run(EVT_VIRTUAL_ENTER)
editor.run(EVT_VIRTUAL_NEXT)
equal(editor.displayValue(), "Taster")
editor.run(EVT_VIRTUAL_ENTER)
equal(app.config.pages[1][2][1][6], 1)
editor.run(EVT_VIRTUAL_ENTER)
editor.run(EVT_VIRTUAL_PREV)
editor.run(EVT_VIRTUAL_EXIT)
equal(app.config.pages[1][2][1][6], 1)
editor.screen, editor.row = "global", 5
equal(editor.run(EVT_VIRTUAL_ENTER), "save")
local changesBeforeVersion = changed
editor.run(EVT_VIRTUAL_NEXT)
equal(editor.run(EVT_VIRTUAL_ENTER), nil)
equal(editor.editing, nil)
equal(changed, changesBeforeVersion)
editor.run(EVT_VIRTUAL_NEXT)
equal(editor.run(EVT_VIRTUAL_ENTER), "close")
editor.run(EVT_VIRTUAL_NEXT)
equal(editor.row, 1)

-- A completely empty page remains editable and receives output 1 when adding again.
app.config.pages[1][2] = {}
editor.screen, editor.row = "page", 4
editor.run(EVT_VIRTUAL_ENTER)
equal(#app.config.pages[1][2], 1)
equal(app.config.pages[1][2][1][3], 1)

-- Tool lifecycle on small/wide/tall LCDs, lazy editor, persistence and failure dialogs.
for _, size in ipairs({{128, 64}, {212, 64}, {128, 96}, {212, 96}}) do
    reset()
    LCD_W, LCD_H = size[1], size[2]
    local t = tool()
    equal(loads["editor.lua"], nil)
    see("Funktionen 1/1")
    run(t, EVT_VIRTUAL_ENTER)
    equal(frames[#frames][7], 1)
    for _ = 1, 9 do run(t, EVT_VIRTUAL_NEXT) end
    run(t, EVT_VIRTUAL_ENTER)
    equal(loads["editor.lua"], 1)
    see("Einstellungen")
    see("Seite bearbeiten")
    equal(rightAligned["1"], LCD_W - 1)
    equal(rightAligned["1000"], LCD_W - 1)
    for _ = 1, 5 do run(t, EVT_VIRTUAL_NEXT) end
    see("Softwareversion")
    equal(rightAligned["5"], LCD_W - 1)
    run(t, EVT_VIRTUAL_ENTER)
    see("Softwareversion")
    for _ = 1, 5 do run(t, EVT_VIRTUAL_PREV) end
    run(t, EVT_VIRTUAL_ENTER)
    for _ = 1, 3 do run(t, EVT_VIRTUAL_NEXT) end
    equal(rightAligned["4"], LCD_W - 1)
    run(t, EVT_VIRTUAL_ENTER)
    run(t, EVT_VIRTUAL_NEXT)
    run(t, EVT_VIRTUAL_ENTER)
    run(t, EVT_VIRTUAL_NEXT)
    run(t, EVT_VIRTUAL_NEXT)
    run(t, EVT_VIRTUAL_NEXT)
    run(t, EVT_VIRTUAL_ENTER)
    run(t, EVT_VIRTUAL_ENTER)
    run(t, EVT_VIRTUAL_NEXT)
    run(t, EVT_VIRTUAL_NEXT_PAGE)
    run(t, EVT_VIRTUAL_EXIT)
    run(t, EVT_VIRTUAL_EXIT)
    for _ = 1, 3 do run(t, EVT_VIRTUAL_NEXT) end
    run(t, EVT_VIRTUAL_ENTER)
    for _ = 1, 300 do run(t) end
    see("Funktionen 1/4")
    run(t, EVT_VIRTUAL_NEXT_PAGE)
    see("Funktionen 2/4")
    run(t, EVT_VIRTUAL_PREV_PAGE)
    see("Funktionen 1/4")
    equal(run(t, EVT_VIRTUAL_EXIT), 2)
    t = tool()
    see("Funktionen 1/4")
    equal(frames[#frames][8], 0) -- runtime switch states are never restored from disk
    equal(handles, 0)
end

-- MENU actions are disabled by default and only affect the control screen.
reset()
local input = assert(loadfile(root .. "app.lua"))(true)
input.init()
for _ = 1, 300 do run(input) end
assert(core.addPage(input.config))
input.changed()
for _, event in ipairs({EVT_MENU_FIRST, EVT_MENU_LONG, EVT_MENU_REPT, EVT_VIRTUAL_MENU}) do run(input, event) end
equal(input.config.pages[1][2][1][4], 0)
equal(input.page, 1)
equal(loads["editor.lua"], nil)
input.config.menuAction = 2
run(input, EVT_MENU_FIRST)
equal(input.page, 1)
run(input, EVT_VIRTUAL_MENU)
equal(input.page, 2)
run(input, EVT_VIRTUAL_MENU)
equal(input.page, 1)
input.config.menuAction = 3
run(input, EVT_VIRTUAL_MENU)
see("Einstellungen")
input.config.menuAction = 2
run(input, EVT_VIRTUAL_MENU)
equal(input.page, 1)
see("Einstellungen")
run(input, EVT_VIRTUAL_EXIT)
input.config.menuAction = 1
for _ = 1, 9 do run(input, EVT_VIRTUAL_NEXT) end
run(input, EVT_MENU_FIRST)
see("Einstellungen")
run(input, EVT_VIRTUAL_MENU)
see("Einstellungen")

-- The physical key behind virtual MENU varies; every phase must follow that key.
for _, menuBreak in ipairs({0x22, 0x29, 0x2a, 0x2b}) do
    reset()
    EVT_VIRTUAL_MENU = menuBreak
    local first, long, repeated = menuBreak + 0x40, menuBreak + 0x60, menuBreak + 0x20
    input = assert(loadfile(root .. "app.lua"))(true)
    input.init()
    for _ = 1, 300 do run(input) end
    input.config.menuAction = 1
    local controls = input.config.pages[1][2]
    controls[2][6] = 1
    input.changed()
    run(input, first)
    equal(controls[1][4], 1)
    run(input, long)
    run(input, repeated)
    run(input, menuBreak)
    equal(controls[1][4], 1)
    run(input, EVT_VIRTUAL_ENTER)
    equal(controls[1][4], 0)
    run(input, EVT_VIRTUAL_NEXT)
    run(input, EVT_VIRTUAL_ENTER)
    equal(controls[2][4], 0)
    run(input)
    see("Menutaste nutzen")
    run(input, EVT_VIRTUAL_EXIT)
    run(input, first)
    equal(controls[2][4], 1)
    packet(0, 0xea, 0xa1, 0x07, 0, 0, 4)
    run(input, long)
    for _ = 1, 8 do
        now = now + 40
        run(input, repeated)
        background(input)
        run(input)
        equal(controls[2][4], 1)
    end
    -- Some keys (notably SHIFT) produce no REPT events while held.
    for _ = 1, 8 do
        now = now + 40
        run(input)
        background(input)
        equal(controls[2][4], 1)
    end
    run(input, menuBreak)
    equal(controls[2][4], 0)
    packet(0, 0xea, 0xa1, 0x07, 0, 0, 0)
    run(input, first)
    run(input, EVT_VIRTUAL_PREV)
    equal(controls[2][4], 0)
    run(input, menuBreak)
    equal(controls[1][4], 0)
    run(input, EVT_VIRTUAL_ENTER)
    run(input, EVT_VIRTUAL_NEXT)
    run(input, first)
    blocked = true
    run(input, menuBreak)
    equal(controls[2][4], 0)
    assert(input.sender.pending)
    blocked = false
    run(input)
    packet(0, 0xea, 0xa1, 0x07, 0, 0, 1)
    run(input, first)
    now = now + 98
    background(input)
    equal(controls[2][4], 1)
    background(input)
    equal(controls[2][4], 0)
    equal(controls[1][4], 1)
    packet(0, 0xea, 0xa1, 0x07, 0, 0, 1)
    run(input, menuBreak)
    equal(controls[2][4], 0)
    run(input, EVT_VIRTUAL_NEXT)
    run(input, first)
    run(input, EVT_VIRTUAL_EXIT)
    equal(controls[2][4], 0)
    run(input, first)
    run(input, EVT_VIRTUAL_NEXT_PAGE)
    equal(controls[2][4], 0)
    run(input, EVT_VIRTUAL_NEXT)
    run(input, first)
    equal(controls[2][4], 1)
    input.save("close")
    equal(controls[2][4], 0)
    for _ = 1, 300 do run(input) end
    controls[1][5] = 1
    switchValues[1] = true
    run(input, first)
    run(input, menuBreak)
    equal(controls[1][4], 1)
    see("Steuerung durch")
    run(input, EVT_VIRTUAL_EXIT)
    run(input, EVT_VIRTUAL_NEXT)
    run(input, first)
    equal(controls[2][4], 1)
    now = -1
    background(input)
    equal(controls[2][4], 0)
end

-- Long titles persist and reserve room for the page number and unsaved marker.
for _, size in ipairs({{128, 64}, {212, 64}}) do
    reset()
    LCD_W, LCD_H = size[1], size[2]
    local titled = assert(loadfile(root .. "app.lua"))(true)
    titled.init()
    for _ = 1, 300 do run(titled) end
    titled.config.pages[1][3] = "ABCDEFGHIJKLMNOPQRST"
    assert(core.addPage(titled.config))
    titled.config.pages[2][3] = "Deck"
    titled.changed()
    run(titled)
    see(LCD_W == 128 and "ABCDEFGHIJKLMNOPQRS 1/2 *" or "ABCDEFGHIJKLMNOPQRST 1/2 *")
    titled.save("close")
    for _ = 1, 300 do run(titled) end
    see("ABCDEFGHIJKLMNOPQRST 1/2")
    local reopened = tool(true)
    see("ABCDEFGHIJKLMNOPQRST 1/2")
    run(reopened, EVT_VIRTUAL_NEXT_PAGE)
    see("Deck 2/2")
    run(reopened, EVT_VIRTUAL_PREV_PAGE)
    see("ABCDEFGHIJKLMNOPQRST 1/2")
    local invalidTitle = core.defaults()
    invalidTitle.pages[1][3] = string.rep("X", 21)
    assert(not core.validate(invalidTitle))
end

for _, size in ipairs({{128, 64}, {212, 64}, {128, 96}}) do
    reset()
    LCD_W, LCD_H = size[1], size[2]
    config = core.defaults()
    for _ = 1, 3 do assert(core.addPage(config)) end
    for _, page in ipairs(config.pages) do
        for _ = 1, 4 do assert(core.addSwitch(config, page)) end
    end
    config.pages[4][2] = {}
    saved = finish(storage.save(storage.path(), config, 0, 0))
    assert(not saved.error)
    loaded = finish(storage.load(storage.path()))
    equal(#loaded.result.pages[1][2], 12)
    equal(#loaded.result.pages[4][2], 0)
    local fullTool = tool()
    for _ = 1, 13 do run(fullTool, EVT_VIRTUAL_NEXT) end
    see("Setup")
    run(fullTool, EVT_VIRTUAL_ENTER)
    see("Einstellungen")
    run(fullTool, EVT_VIRTUAL_EXIT)
    run(fullTool, EVT_VIRTUAL_PREV_PAGE)
    see("Funktionen 4/4")
    see("Seite >")
    run(fullTool, EVT_VIRTUAL_NEXT)
    run(fullTool, EVT_VIRTUAL_ENTER)
    see("Einstellungen")
end

-- Telemetry loads and operates without ever opening the LCD, including hidden pages.
reset()
config = core.defaults()
for _ = 1, 3 do assert(core.addPage(config)) end
config.pages[1][2][1][5] = 1
config.pages[4][2][8][5] = 101
config.pages[2][2][1][5] = -1
saved = finish(storage.save(storage.path(), config, 0, 0))
assert(not saved.error)
switchValues[1], switchValues[101], switchValues[-1] = true, true, false
local telemetry = assert(loadfile(root .. "../../TELEMETRY/mswNG.lua"))()
telemetry.init()
for _ = 1, 300 do background(telemetry) end
equal(loads["ui.lua"], nil)
equal(loads["editor.lua"], nil)
equal(frames[1][8], 1) -- no initial off pulse for an already active physical switch
packet(0, 0xea, 0xa1, 0x09, 4, 0, 0, 1, 1, 0, 0, 2, 0, 0, 3, 64, 0)
switchValues[1], switchValues[101], switchValues[-1] = false, false, true
background(telemetry)
packet(0, 0xea, 0xa1, 0x09, 4, 0, 0, 0, 1, 0, 1, 2, 0, 0, 3, 0, 0)
run(telemetry)
see("Funktionen 1/4")
run(telemetry, EVT_VIRTUAL_ENTER)
run(telemetry)
see("Steuerung durch Schalter")
equal(frames[#frames][8], 0)
run(telemetry, EVT_VIRTUAL_EXIT)
run(telemetry, EVT_VIRTUAL_NEXT)
run(telemetry, EVT_VIRTUAL_ENTER) -- manual output 2 remains on when hidden
for _ = 1, 150 do background(telemetry) end
packet(0, 0xea, 0xa1, 0x09, 4, 0, 0, 4, 1, 0, 1, 2, 0, 0, 3, 0, 0)
local uiLoads = loads["ui.lua"]
run(telemetry)
equal(loads["ui.lua"], uiLoads + 1)
for _ = 1, 9 do run(telemetry, EVT_VIRTUAL_NEXT) end
run(telemetry, EVT_VIRTUAL_ENTER)
background(telemetry)
run(telemetry, EVT_VIRTUAL_ENTER) -- foreground editor survives interleaved background calls
background(telemetry)
run(telemetry, EVT_VIRTUAL_PREV)
background(telemetry)
run(telemetry, EVT_VIRTUAL_ENTER)
see("Seiten loeschen?")
run(telemetry, EVT_VIRTUAL_EXIT)
run(telemetry, EVT_VIRTUAL_EXIT)
run(telemetry, EVT_VIRTUAL_EXIT)
local before = #frames
now = now + config.interval
background(telemetry)
assert(#frames > before, "EXIT must not terminate telemetry output")

-- A background save completes with switch evaluation still running.
local live = assert(loadfile(root .. "app.lua"))(true)
live.init()
for _ = 1, 300 do background(live) end
live.config.pages[1][2][2][5] = 1
live.changed()
live.save("close")
switchValues[1] = true
for _ = 1, 300 do background(live) end
assert(not live.busy and not live.dirty)
equal(live.config.pages[1][2][2][4], 1)
loaded = finish(storage.load(storage.path()))
equal(loaded.result.pages[1][2][2][5], 1)
equal(loaded.result.pages[1][2][2][4], 0)
equal(handles, 0)

reset()
local t = tool()
for _ = 1, 9 do run(t, EVT_VIRTUAL_NEXT) end
run(t, EVT_VIRTUAL_ENTER)
run(t, EVT_VIRTUAL_ENTER)
run(t, EVT_VIRTUAL_NEXT)
run(t, EVT_VIRTUAL_ENTER)
run(t, EVT_VIRTUAL_EXIT)
run(t, EVT_VIRTUAL_EXIT)
run(t)
see("Aenderungen speichern?")
writeError = true
run(t, EVT_VIRTUAL_ENTER)
for _ = 1, 10 do run(t) end
see("Speichern:")
equal(handles, 0)
run(t, EVT_VIRTUAL_EXIT)
run(t, EVT_VIRTUAL_EXIT)
run(t, EVT_VIRTUAL_NEXT)
equal(run(t, EVT_VIRTUAL_ENTER), 2)

reset()
fs[storage.path() .. ".a"] = "broken\n"
t = tool()
see("SD-Fehler")
equal(#frames, 0)
equal(run(t, EVT_VIRTUAL_EXIT), 2)

io = hostIO
debug.setmetatable("", stringMeta)
print("MultiSwitchNG tests passed; peak call instructions (host): " .. peakInstructions)
