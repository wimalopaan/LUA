-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 Wilhelm Meier
-- Host-only memory regression check: lua ../LIB/mswNG/tests/memory.lua

local root = string.match(arg[0], "^(.*)tests/") or ""
local hostIO = io
local files, fileCount = {}, 0
local core = assert(loadfile(root .. "core.lua"))()
local storage = assert(loadfile(root .. "storage.lua"))(core)
local config = core.defaults()
for _ = 1, 3 do assert(core.addPage(config)) end
for p, page in ipairs(config.pages) do
    for _ = 1, 4 do assert(core.addSwitch(config, page)) end
    for s, control in ipairs(page[2]) do
        control[2], control[5] = (p - 1) * 12 + s - 1, 1
    end
end
model = {getInfo = function() return {name = "Memory"} end}
io = {
    open = function(path, mode)
        if mode == "r" and not files[path] then return nil, "missing", 2 end
        if mode == "w" then files[path] = "" end
        fileCount = fileCount + 1
        return {path = path, mode = mode, offset = 1}
    end,
    read = function(file, size)
        local text = string.sub(files[file.path], file.offset, file.offset + size - 1)
        file.offset = file.offset + #text
        return text
    end,
    write = function(file, text)
        files[file.path] = files[file.path] .. text
        return file
    end,
    close = function() fileCount = fileCount - 1 end,
}
local job = storage.save(storage.path(), config, 0, 0)
while not job.done do storage.step(job) end
assert(not job.error)
config, job, storage, core = nil, nil, nil, nil
LCD_W, LCD_H, SMLSIZE, INVERS, BLINK = 128, 64, 1, 2, 4
RIGHT = 8
EVT_VIRTUAL_NEXT, EVT_VIRTUAL_PREV, EVT_VIRTUAL_ENTER, EVT_VIRTUAL_EXIT = 1, 2, 3, 4
EVT_VIRTUAL_NEXT_PAGE, EVT_VIRTUAL_PREV_PAGE, EVT_VIRTUAL_MENU = 5, 6, 7
local now = 0
getTime = function() now = now + 1; return now end
crossfireTelemetryPush = function() return true end
getSwitchValue = function() return true end
getSwitchName = function(id) return "S" .. id end
switches = function()
    local id = -151
    return function()
        id = id + 1
        if id <= 150 then return id end
    end
end
lcd = {clear = function() end, drawText = function() end, getLastPos = function() return 0 end,
       getLastLeftPos = function() return LCD_W - 35 end,
       drawRectangle = function() end, drawFilledRectangle = function() end}
loadScript = function(path)
    return loadfile(root .. string.match(path, "([^/]+)$"))
end
collectgarbage("collect")
local baseline = collectgarbage("count")
local tool = assert(loadfile(root .. "../../TOOLS/mswNG.lua"))()
tool.init()
for _ = 1, 400 do tool.run(0) end
collectgarbage("collect")
local running = collectgarbage("count") - baseline
tool.run(EVT_VIRTUAL_MENU)
tool.run(EVT_VIRTUAL_NEXT)
tool.run(EVT_VIRTUAL_ENTER)
tool.run(EVT_VIRTUAL_NEXT)
tool.run(EVT_VIRTUAL_NEXT)
tool.run(EVT_VIRTUAL_NEXT)
tool.run(EVT_VIRTUAL_ENTER)
for _ = 1, 3 do tool.run(EVT_VIRTUAL_NEXT) end
tool.run(EVT_VIRTUAL_ENTER)
collectgarbage("collect")
local editing = collectgarbage("count") - baseline
for _ = 1, 4 do tool.run(EVT_VIRTUAL_EXIT) end
collectgarbage("collect")
local closed = collectgarbage("count") - baseline
for _ = 1, 100 do
    tool.run(EVT_VIRTUAL_MENU)
    tool.run(EVT_VIRTUAL_EXIT)
end
for _ = 1, 10000 do tool.run(0) end
collectgarbage("collect")
local repeated = collectgarbage("count") - baseline
assert(repeated < closed + 2, "Unbounded runtime/editor retention")
assert(closed < editing - 3, "Editor was not released")
assert(fileCount == 0, "File handle leak")
tool = nil
collectgarbage("collect")
baseline = collectgarbage("count")
local telemetry = assert(loadfile(root .. "../../TELEMETRY/mswNG.lua"))()
telemetry.init()
for _ = 1, 400 do telemetry.background() end
collectgarbage("collect")
local hidden = collectgarbage("count") - baseline
telemetry.run(0)
collectgarbage("collect")
local visible = collectgarbage("count") - baseline
for _ = 1, 1000 do telemetry.background() end
collectgarbage("collect")
local hiddenAgain = collectgarbage("count") - baseline
assert(hiddenAgain < hidden + 2, "Background retained LCD state")
assert(hiddenAgain < visible - 3, "LCD module was not released")
for _ = 1, 10000 do telemetry.background() end
collectgarbage("collect")
assert(collectgarbage("count") - baseline < hiddenAgain + 2, "Unbounded background retention")
assert(fileCount == 0)
io = hostIO
print(string.format("%s, 48 switches/addresses, KiB: tool %.1f, editor+selector %.1f, closed %.1f, repeated %.1f; telemetry hidden %.1f, visible %.1f, hidden again %.1f",
                    _VERSION, running, editing, closed, repeated, hidden, visible, hiddenAgain))
