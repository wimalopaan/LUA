-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 Wilhelm Meier

local config = ...
local t = config.t
local M = {}
local MAX_LINE = 2048

local function recordAt(data, index, generation)
    if index == 1 then
        local header = config.copy(data.header)
        header.generation = generation
        return header
    elseif index <= #data.tabs + 1 then return data.tabs[index - 1]
    else return data.controls[index - #data.tabs - 1] end
end

local function close(job)
    if job.file then
        local ok, err = io.close(job.file)
        job.file = nil
        -- EdgeTX io.close has no return values; desktop Lua returns true on success.
        if ok == false or err then return nil, err or t("Cannot close configuration file") end
    end
    return true
end

local function fail(job, err)
    local _, closeError = close(job)
    job.error = tostring(err) .. (closeError and ("; " .. closeError) or "")
    job.done = true
end

function M.ensureDirectory(path)
    local info = type(fstat) == "function" and fstat(path)
    if info then
        if type(info.attrib) == "number" and info.attrib & 0x10 ~= 0 then return true end
        return nil, t("Not a directory: %s", path)
    end
    if type(mkdir) ~= "function" then return nil, t("Directory creation API unavailable") end
    local result = mkdir(path)
    if result ~= 0 and result ~= 8 then
        return nil, t("Cannot create directory %s: %s", path, tostring(result))
    end
    return true
end

function M.sourceName(source)
    if type(source) ~= "string" then return end
    local hex = string.match(source, "^model_([%x]+)$")
    if not hex or #hex % 2 ~= 0 then return end
    local name = {}
    for index = 1, #hex, 2 do
        local byte = tonumber(string.sub(hex, index, index + 1), 16)
        if byte < 32 or byte == 127 then return end
        name[#name + 1] = string.char(byte)
    end
    return table.concat(name)
end

local function yamlName(value)
    local quote = string.sub(value, 1, 1)
    if quote ~= '"' and quote ~= "'" then
        return string.match(string.gsub(value, "%s+#.*$", ""), "^(.-)%s*$")
    end
    local parts, index = {}, 2
    while index <= #value do
        local char = string.sub(value, index, index)
        local nextChar = string.sub(value, index + 1, index + 1)
        if char == quote then
            if quote == "'" and nextChar == "'" then
                parts[#parts + 1], index = "'", index + 2
            else
                local tail = string.sub(value, index + 1)
                if string.match(tail, "^%s*$") or string.match(tail, "^%s+#") then
                    return table.concat(parts)
                end
                return
            end
        elseif char == "\\" and quote == '"' then
            if nextChar == "x" then
                local hex = string.sub(value, index + 2, index + 3)
                if not string.match(hex, "^%x%x$") then return end
                parts[#parts + 1], index = string.char(tonumber(hex, 16)), index + 4
            elseif nextChar == '"' or nextChar == "\\" or nextChar == "/" then
                parts[#parts + 1], index = nextChar, index + 2
            else return end
        else
            parts[#parts + 1], index = char, index + 1
        end
    end
end

local function modelName(identifier)
    if not string.match(string.lower(identifier), "%.ya?ml$") then return identifier end
    local path = "/MODELS/" .. identifier
    if string.find(identifier, "[/\\]") then return nil, t("Cannot read model name from %s", path) end
    local file, err = io.open(path, "r")
    if not file then return nil, err or t("Cannot open %s", path) end
    -- EdgeTX writes header.name immediately after semver, within this bounded read.
    local data, readError = io.read(file, 512)
    local ok, closeError = close({file = file})
    if readError or not ok then
        return nil, (readError or "") .. (closeError and ("; " .. closeError) or "")
    end
    local header = false
    for line in string.gmatch(data or "", "[^\r\n]+") do
        if string.match(line, "^header:%s*$") then header = true
        elseif header then
            if string.match(line, "^[^%s#]") then break end
            local value = string.match(line, "^%s+name:%s*(.-)%s*$")
            if value then
                local name = yamlName(value)
                if name and string.find(name, "%S") and not string.find(name, "[%z\1-\31\127]") then
                    return name
                end
                break
            end
        end
    end
    return nil, t("Cannot read model name from %s", path)
end

function M.scan(directory, current)
    local job = {directory = directory, current = current and string.lower(current),
        names = {}, sources = {}, errors = {}, seen = {}}
    if type(dir) ~= "function" then
        job.done, job.error = true, t("Directory listing API unavailable")
    else
        job.iterator = dir(directory)
        if not job.iterator then job.done, job.error = true, t("Cannot list %s", directory) end
    end
    return job
end

function M.stepScan(job)
    if job.done then return end
    local entry = job.iterator()
    if not entry then
        job.done, job.iterator, job.seen = true, nil, nil
        return
    end
    local source = string.match(entry, "^(model_[%x]+)%.[ab]%.lua$")
    local name = M.sourceName(source)
    local key = source and string.lower(source)
    if name and string.lower(job.directory .. source) ~= job.current and not job.seen[key] then
        job.seen[key] = true
        local resolved, err = modelName(name)
        local index = #job.sources + 1
        job.names[index] = resolved or t("Model name unavailable: %s", name)
        job.sources[index], job.errors[index] = source, err
    end
end

function M.cancelLoad(job)
    if job.done then return true end
    local ok, err = close(job)
    job.done, job.error = true, t("Configuration update cancelled")
    if not ok then
        job.error = job.error .. "; " .. err
        return nil, err
    end
    return true
end

-- A complete file is an ordinary Lua table. Each line is a separate, bounded record.
function M.load(path, expected, generation)
    local file, err, code = io.open(path, "r")
    if not file then
        local missing = code == 2
        -- EdgeTX may report only "file error", without an ENOENT error code.
        if not missing and type(fstat) == "function" then missing = fstat(path) == nil end
        return {done = true, unavailable = true, missing = missing,
                error = err or t("Cannot open %s", path)}
    end
    return {file = file, buffer = "", builder = config.builder(), phase = "start",
            expected = expected, generation = generation, recordIndex = 0}
end

local function readLine(job)
    local newline = string.find(job.buffer, "\n", 1, true)
    if newline then
        local line = string.gsub(string.sub(job.buffer, 1, newline - 1), "\r$", "")
        job.buffer = string.sub(job.buffer, newline + 1)
        return line
    end
    if job.eof then
        if #job.buffer > 0 then
            local line = job.buffer
            job.buffer = ""
            return line
        end
        return nil, "eof"
    end
    local data, err = io.read(job.file, 512)
    if err then return nil, err end
    if not data or #data == 0 then job.eof = true else job.buffer = job.buffer .. data end
    if #job.buffer > MAX_LINE and not string.find(job.buffer, "\n", 1, true) then
        return nil, t("Configuration line exceeds %d bytes", MAX_LINE)
    end
end

local function parseRecord(line)
    if #line > MAX_LINE then return nil, t("Configuration record too long") end
    -- Only literal scalar tables are accepted, never executable configuration code.
    local outside, i = {}, 1
    while i <= #line do
        local c = string.sub(line, i, i)
        if c == '"' then
            i = i + 1
            local ended = false
            while i <= #line do
                c = string.sub(line, i, i)
                if c == "\\" then i = i + 2
                elseif c == '"' then ended = true; break
                else i = i + 1 end
            end
            if not ended then return nil, t("Unterminated configuration string") end
            outside[#outside + 1] = '""'
        else
            outside[#outside + 1] = c
        end
        i = i + 1
    end
    local text = table.concat(outside)
    if not string.match(text, "^%s*{[^{}]*}%s*,%s*$") then return nil, t("Expected a scalar Lua record") end
    text = string.gsub(string.gsub(text, '""', "0"), "[%a_][%w_]*%s*=", "")
    if string.find(text, "[^%s%d{},=%.%-]") or string.find(text, "%-%-") then
        return nil, t("Only literal configuration values are allowed")
    end
    local chunk, err = load("return " .. string.gsub(line, ",%s*$", ""), "config record", "t", {})
    if not chunk then return nil, err end
    local ok, record = pcall(chunk)
    if not ok then return nil, record end
    return record
end

function M.stepLoad(job)
    if job.done then return end
    local line, err = readLine(job)
    if not line then
        if err == "eof" then
            if job.phase ~= "end" then return fail(job, t("Incomplete configuration file")) end
            if job.expected and recordAt(job.expected, job.recordIndex + 1, job.generation) then
                return fail(job, t("Saved configuration is missing records"))
            end
            local result, reason = config.finish(job.builder)
            if not result then return fail(job, reason) end
            local ok, closeError = close(job)
            if not ok then return fail(job, closeError) end
            job.result, job.done = result, true
            job.builder = nil
        elseif err then fail(job, err) end
        return
    end
    if job.phase == "start" then
        if line ~= "return {" then return fail(job, t("Expected 'return {'")) end
        job.phase = "records"
    elseif job.phase == "end" then
        if string.match(line, "%S") then fail(job, t("Data after configuration end")) end
    elseif line == "}" then
        job.phase = "end"
    else
        local record, reason = parseRecord(line)
        if not record then return fail(job, reason) end
        job.recordIndex = job.recordIndex + 1
        if job.expected then
            local expected = recordAt(job.expected, job.recordIndex, job.generation)
            if not expected then return fail(job, t("Unexpected saved record")) end
            for key, value in pairs(expected) do
                if record[key] ~= value then return fail(job, t("Saved value differs: %s", key)) end
            end
        end
        local ok
        ok, reason = config.append(job.builder, record)
        if not ok then fail(job, reason) end
    end
end

local function serialize(record)
    local fields = {}
    for key, value in pairs(record) do
        fields[#fields + 1] = key .. "=" .. (type(value) == "string" and string.format("%q", value) or tostring(value))
    end
    table.sort(fields)
    return "{" .. table.concat(fields, ",") .. "},\n"
end

function M.save(path, data, generation)
    local file, err = io.open(path, "w")
    if not file then return {done = true, error = err or t("Cannot open %s", path)} end
    return {file = file, data = data, generation = generation, index = 0}
end

function M.stepSave(job)
    if job.done then return end
    local text
    if job.index == 0 then text = "return {\n"
    elseif job.index <= #job.data.tabs + #job.data.controls + 1 then
        text = serialize(recordAt(job.data, job.index, job.generation))
    else text = "}\n" end
    local ok, err = io.write(job.file, text)
    if not ok then return fail(job, err or t("Cannot write configuration")) end
    job.index = job.index + 1
    if job.index > #job.data.tabs + #job.data.controls + 2 then
        ok, err = close(job)
        if not ok then return fail(job, err) end
        job.done = true
        job.data = nil
    end
end

return M
