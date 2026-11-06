-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 Wilhelm Meier

local app = ...
local settings = type(getGeneralSettings) == "function" and getGeneralSettings() or nil
local language = type(settings) == "table" and settings.language
language = type(language) == "string" and string.lower(language) or "en"
local M = {language = language == "de" and "de" or "en"}
M.ready = M.language == "en"
local texts = {}

local function format(message, ...)
    if select("#", ...) == 0 then return message end
    return string.format(message, ...)
end

function M.t(message, ...)
    return format(texts[message] or message, ...)
end

function M.p(context, message, ...)
    return format(texts[context .. ":" .. message] or texts[message] or message, ...)
end

function M.step(mode)
    if M.ready then return true end
    local script, err = loadScript(app.dir .. "lang/" .. M.language .. ".lua", mode or "t")
    if not script then return nil, "Cannot load language: " .. tostring(err) end
    local ok, result = pcall(script)
    if not ok or type(result) ~= "table" then return nil, "Invalid language catalog: " .. tostring(result) end
    texts, M.ready = result, true
    return true
end

return M
