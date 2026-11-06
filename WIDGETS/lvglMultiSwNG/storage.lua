-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 Wilhelm Meier

local config = ...
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
        if ok == false or err then return nil, err or "Cannot close configuration file" end
    end
    return true
end

local function fail(job, err)
    local _, closeError = close(job)
    job.error = tostring(err) .. (closeError and ("; " .. closeError) or "")
    job.done = true
end

-- A complete file is an ordinary Lua table. Each line is a separate, bounded record.
function M.load(path, expected, generation)
    local file, err, code = io.open(path, "r")
    if not file then
        local missing = code == 2
        -- EdgeTX may report only "file error", without an ENOENT error code.
        if not missing and type(fstat) == "function" then missing = fstat(path) == nil end
        return {done = true, unavailable = true, missing = missing,
                error = err or "Cannot open " .. path}
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
        return nil, "Configuration line exceeds " .. MAX_LINE .. " bytes"
    end
end

local function parseRecord(line)
    if #line > MAX_LINE then return nil, "Configuration record too long" end
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
            if not ended then return nil, "Unterminated configuration string" end
            outside[#outside + 1] = '""'
        else
            outside[#outside + 1] = c
        end
        i = i + 1
    end
    local text = table.concat(outside)
    if not string.match(text, "^%s*{[^{}]*}%s*,%s*$") then return nil, "Expected a scalar Lua record" end
    text = string.gsub(string.gsub(text, '""', "0"), "[%a_][%w_]*%s*=", "")
    if string.find(text, "[^%s%d{},=%.%-]") or string.find(text, "%-%-") then
        return nil, "Only literal configuration values are allowed"
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
            if job.phase ~= "end" then return fail(job, "Incomplete configuration file") end
            if job.expected and recordAt(job.expected, job.recordIndex + 1, job.generation) then
                return fail(job, "Saved configuration is missing records")
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
        if line ~= "return {" then return fail(job, "Expected 'return {'") end
        job.phase = "records"
    elseif job.phase == "end" then
        if string.match(line, "%S") then fail(job, "Data after configuration end") end
    elseif line == "}" then
        job.phase = "end"
    else
        local record, reason = parseRecord(line)
        if not record then return fail(job, reason) end
        job.recordIndex = job.recordIndex + 1
        if job.expected then
            local expected = recordAt(job.expected, job.recordIndex, job.generation)
            if not expected then return fail(job, "Unexpected saved record") end
            for key, value in pairs(expected) do
                if record[key] ~= value then return fail(job, "Saved value differs: " .. key) end
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
    if not file then return {done = true, error = err or "Cannot open " .. path} end
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
    if not ok then return fail(job, err or "Cannot write configuration") end
    job.index = job.index + 1
    if job.index > #job.data.tabs + #job.data.controls + 2 then
        ok, err = close(job)
        if not ok then return fail(job, err) end
        job.done = true
        job.data = nil
    end
end

return M
