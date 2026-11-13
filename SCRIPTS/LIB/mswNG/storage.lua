-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 Wilhelm Meier

local core = ...
local M = {}

-- EdgeTX cannot preempt Lua callbacks invoked by C functions such as string.gsub.
local function hex(text)
    local result = ""
    for i = 1, #text do result = result .. string.format("%02x", string.byte(text, i)) end
    return result
end

local function unhex(text)
    local result = ""
    for i = 1, #text, 2 do
        result = result .. string.char(tonumber(string.sub(text, i, i + 1), 16))
    end
    return result
end

local function checksum(sum, text)
    for i = 1, #text do sum = (sum * 33 + string.byte(text, i)) % 65521 end
    return sum
end

local function close(job)
    if not job.file then return true end
    local ok, err = io.close(job.file)
    job.file = nil
    if ok == false or err then return nil, err or "SD: Schliessen fehlgeschlagen" end
    return true
end

local function failure(job, err)
    local _, reason = close(job)
    job.error, job.done = tostring(err) .. (reason and ("; " .. reason) or ""), true
end

function M.path()
    return "/SCRIPTS/LIB/mswNG/model-" .. hex(model.getInfo().name)
end

local function reader(path)
    local file, err, code = io.open(path, "r")
    if not file then
        local missing = code == 2 or (type(fstat) == "function" and fstat(path) == nil)
        return {done = true, missing = missing, error = err or "SD: Lesen fehlgeschlagen"}
    end
    return {file = file, buffer = "", sum = 0, phase = "header", pagesLeft = 0, controlsLeft = 0}
end

local function line(job)
    local ending = string.find(job.buffer, "\n", 1, true)
    if ending then
        local text = string.sub(job.buffer, 1, ending - 1)
        job.buffer = string.sub(job.buffer, ending + 1)
        return text
    end
    if job.eof then return nil, "Datei unvollstaendig" end
    local text, err = io.read(job.file, 96)
    if err then return nil, err end
    if not text or #text == 0 then job.eof = true else job.buffer = job.buffer .. text end
    if #job.buffer > 192 then return nil, "SD: Zeile zu lang" end
end

local function readStep(job)
    if job.done then return end
    if job.phase == "eof" then
        if #job.buffer > 0 then return failure(job, "Daten nach Dateiende") end
        local extra, err = io.read(job.file, 1)
        if err or (extra and #extra > 0) then return failure(job, err or "Daten nach Dateiende") end
        local ok, reason = core.validate(job.config)
        if not ok then return failure(job, reason) end
        ok, reason = close(job)
        if not ok then return failure(job, reason) end
        job.done, job.result = true, job.config
        return
    end
    local text, err = line(job)
    if err then return failure(job, err) end
    if not text then return end
    if job.phase == "header" then
        local version, generation, pages, interval = string.match(text, "^MSNG ([23]) (%d+) (%d+) (%d+)$")
        if not generation then
            local legacyDestination
            generation, pages, interval, legacyDestination =
                string.match(text, "^MSNG 1 (%d+) (%d+) (%d+) (%d+)$")
            if not legacyDestination or tonumber(legacyDestination) > 255 then
                return failure(job, "SD: Falsches Dateiformat")
            end
        end
        generation, pages = tonumber(generation), tonumber(pages)
        if not generation or generation > 2147483647 or not pages or pages < 1 or pages > 4 then
            return failure(job, "SD: Falsches Dateiformat")
        end
        job.generation, job.pagesLeft, job.version = generation, pages, tonumber(version) or 1
        job.config = {pages = {}, interval = tonumber(interval)}
        job.phase = "page"
    elseif job.phase == "page" then
        local address, count, title
        if job.version == 3 then
            address, count, title = string.match(text, "^P (%d+) (%d+) ([%x]+)$")
            if not title or #title > core.titleLength * 2 or #title % 2 ~= 0 then
                return failure(job, "SD: Ungueltiger Titel")
            end
            title = unhex(title)
        else
            address, count = string.match(text, "^P (%d+) (%d+)$")
            title = core.defaultTitle
        end
        address, count = tonumber(address), tonumber(count)
        if not address or address > 255 or not count or count > 12 then
            return failure(job, "SD: Ungueltige Seite")
        end
        job.page = {address, {}, title}
        job.config.pages[#job.config.pages + 1] = job.page
        job.pagesLeft, job.controlsLeft = job.pagesLeft - 1, count
        job.phase = count > 0 and "control" or (job.pagesLeft > 0 and "page" or "end")
    elseif job.phase == "control" then
        local address, output, id, name = string.match(text, "^S (%-?%d+) (%d+) (%-?%d+) ([%x]+)$")
        if not name or #name > 24 or #name % 2 ~= 0 then
            return failure(job, "SD: Ungueltiger Schalter")
        end
        name = unhex(name)
        job.page[2][#job.page[2] + 1] = {name, tonumber(address), tonumber(output), 0, tonumber(id)}
        job.controlsLeft = job.controlsLeft - 1
        if job.controlsLeft == 0 then job.phase = job.pagesLeft > 0 and "page" or "end" end
    else
        local sum = tonumber(string.match(text, "^E (%d+)$"))
        if sum ~= job.sum then return failure(job, "SD: Pruefsumme falsch") end
        job.phase = "eof"
        return
    end
    job.sum = checksum(job.sum, text .. "\n")
end

function M.load(path)
    return {mode = "load", path = path, slot = 1, reader = reader(path .. ".a")}
end

function M.save(path, config, slot, generation)
    if generation >= 2147483647 then return {done = true, error = "SD: Generation erschoepft"} end
    local ok, err = core.validate(config)
    if not ok then return {done = true, error = err} end
    local target = slot == 1 and 2 or 1
    local file
    file, err = io.open(path .. (target == 1 and ".a" or ".b"), "w")
    if not file then return {done = true, error = err or "SD: Schreiben fehlgeschlagen"} end
    return {mode = "save", path = path, slot = target, generation = generation + 1,
            config = config, file = file, sum = 0, page = 0, control = 0}
end

local function writeStep(job)
    local text
    if job.page == 0 then
        text = string.format("MSNG 3 %d %d %d\n", job.generation, #job.config.pages, job.config.interval)
        job.page = 1
    elseif job.page > #job.config.pages then
        text = "E " .. job.sum .. "\n"
    else
        local page = job.config.pages[job.page]
        if job.control == 0 then
            text = string.format("P %d %d %s\n", page[1], #page[2], hex(page[3]))
            job.control = 1
        else
            local control = page[2][job.control]
            local name = hex(control[1])
            text = string.format("S %d %d %d %s\n", control[2], control[3], control[5] or 0, name)
            job.control = job.control + 1
        end
        if job.control > #page[2] then job.page, job.control = job.page + 1, 0 end
    end
    local ok, err = io.write(job.file, text)
    if not ok then return failure(job, err or "SD: Schreiben fehlgeschlagen") end
    if string.sub(text, 1, 2) == "E " then
        ok, err = close(job)
        if not ok then return failure(job, err) end
        job.reader = reader(job.path .. (job.slot == 1 and ".a" or ".b"))
        job.mode = "verify"
    else
        job.sum = checksum(job.sum, text)
    end
end

function M.step(job)
    if job.done then return end
    if job.mode == "save" then return writeStep(job) end
    local r = job.reader
    readStep(r)
    if not r.done then return end
    if job.mode == "verify" then
        if r.error then return failure(job, r.error) end
        if r.sum ~= job.sum or r.generation ~= job.generation then
            return failure(job, "SD: Schreibkontrolle fehlgeschlagen")
        end
        job.done = true
        return
    end
    if r.result then
        if not job.result or r.generation > job.generation then
            job.result, job.generation, job.active = r.result, r.generation, job.slot
        end
    elseif not r.missing then
        job.warning = "SD: Defekte Konfiguration"
    end
    if job.slot == 1 then
        job.slot, job.reader = 2, reader(job.path .. ".b")
    else
        job.done, job.reader = true, nil
        job.slot = job.active or 0
        if not job.result and job.warning then job.error = job.warning end
    end
end

return M
