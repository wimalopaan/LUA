-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 Wilhelm Meier

local M = {maxPages = 4, maxSwitches = 12, nameLength = 12, titleLength = 20, defaultTitle = "Funktionen"}
M.menuActions = {"Aus", "Bedienung", "Naechste Seite", "Setup"}
M.controlTypes = {"Schalter", "Taster"}

-- Page: {default address, controls, title}.
-- Control: {name, address (-1 inherits), output, state, EdgeTX switch ID, type (0: toggle, 1: momentary)}.
function M.address(page, control)
    return control[2] == -1 and page[1] or control[2]
end

function M.used(config, address, output, except)
    for _, page in ipairs(config.pages) do
        for _, control in ipairs(page[2]) do
            if control ~= except and M.address(page, control) == address and control[3] == output then
                return true
            end
        end
    end
end

function M.free(config, first)
    local endpoints = {}
    for _, page in ipairs(config.pages) do
        for _, control in ipairs(page[2]) do endpoints[M.address(page, control) * 8 + control[3]] = true end
    end
    for offset = 0, 255 do
        local address = (first + offset) % 256
        for output = 1, 8 do
            if not endpoints[address * 8 + output] then return address, output end
        end
    end
end

function M.addPage(config)
    if #config.pages >= M.maxPages then return nil, "Max. 4 Seiten" end
    local addresses = {}
    for _, page in ipairs(config.pages) do
        for _, control in ipairs(page[2]) do addresses[M.address(page, control)] = true end
    end
    local address = 0
    while addresses[address] do address = address + 1 end
    if address == 256 then return nil, "Keine freie Adresse" end
    local page = {address, {}, M.defaultTitle}
    for output = 1, 8 do page[2][output] = {"Ausgang " .. output, -1, output, 0, 0, 0} end
    config.pages[#config.pages + 1] = page
    return true
end

function M.defaults()
    local config = {pages = {}, interval = 100, menuAction = 0}
    M.addPage(config)
    return config
end

local function integer(value, low, high)
    return type(value) == "number" and value == math.floor(value) and value >= low and value <= high
end

local function validText(value, length)
    return type(value) == "string" and #value >= 1 and #value <= length and not string.find(value, "[^ -~]")
end

function M.validate(config)
    if type(config) ~= "table" or not integer(config.interval, 5, 1000)
        or not integer(config.menuAction or 0, 0, 3) or type(config.pages) ~= "table"
        or #config.pages < 1 or #config.pages > M.maxPages then
        return nil, "Ungueltige Einstellungen"
    end
    local endpoints = {}
    for _, page in ipairs(config.pages) do
        if type(page) ~= "table" or not integer(page[1], 0, 255)
            or type(page[2]) ~= "table" or #page[2] > M.maxSwitches
            or not validText(page[3], M.titleLength) then
            return nil, "Ungueltige Seite"
        end
        for _, control in ipairs(page[2]) do
            if type(control) ~= "table" or not validText(control[1], M.nameLength)
                or not integer(control[2], -1, 255) or not integer(control[3], 1, 8)
                or not integer(control[5] or 0, -32767, 32767)
                or not integer(control[6] or 0, 0, 1) then
                return nil, "Ungueltiger Schalter"
            end
            local key = M.address(page, control) * 8 + control[3]
            if endpoints[key] then return nil, "Adresse/Ausgang belegt" end
            endpoints[key] = true
        end
    end
    return true
end

function M.addSwitch(config, page)
    if #page[2] >= M.maxSwitches then return nil, "Max. 12 Schalter" end
    local address, output = M.free(config, page[1])
    if not address then return nil, "Kein freier Ausgang" end
    page[2][#page[2] + 1] = {"Ausgang " .. output, address == page[1] and -1 or address, output, 0, 0, 0}
    return true
end

function M.route(config, page, control, address, output)
    if control[2] == address and control[3] == output then return true end
    local actual = address == -1 and page[1] or address
    if M.used(config, actual, output, control) then return nil, "Adresse/Ausgang belegt" end
    control[2], control[3], control[4] = address, output, 0
    return true
end

function M.pageAddress(config, page, address)
    local previous = page[1]
    if previous == address then return true end
    page[1] = address
    local ok, err = M.validate(config)
    if not ok then page[1] = previous; return nil, err end
    for _, control in ipairs(page[2]) do
        if control[2] == -1 then control[4] = 0 end
    end
    return true
end

function M.sender()
    return {groups = {}, map = {}, cursor = 1, last = -1000, pending = true, payload = {}}
end

function M.rebuild(sender, config)
    for _, group in ipairs(sender.groups) do group.used, group.value = false, 0 end
    for _, page in ipairs(config.pages) do
        for _, control in ipairs(page[2]) do
            local address = M.address(page, control)
            local found = sender.map[address]
            if not found then
                found = {address = address, value = 0}
                sender.groups[#sender.groups + 1] = found
                sender.map[address] = found
            end
            found.used = true
            found.value = found.value + (control[4] or 0) * 4 ^ (control[3] - 1)
        end
    end
    -- Keep removed addresses until an all-off packet has entered the transmit FIFO.
    sender.cursor, sender.pending = 1, true
end

function M.poll(sender, config)
    local changed, reason = false
    for _, page in ipairs(config.pages) do
        for _, control in ipairs(page[2]) do
            local id = control[5] or 0
            if id ~= 0 then
                local value
                if type(getSwitchValue) == "function" then value = getSwitchValue(id)
                else reason = reason or "Schalter API fehlt" end
                if value == nil then reason = reason or ("Schalter fehlt: " .. control[1]) end
                local state = value == true and 1 or 0
                if state ~= control[4] then control[4], changed = state, true end
            end
        end
    end
    sender.inputError = reason
    if changed then M.rebuild(sender, config) end
end

function M.tick(sender, config, now)
    if type(crossfireTelemetryPush) ~= "function" then
        sender.error = "CRSF API fehlt"
        return
    end
    if not sender.pending and now >= sender.last and now - sender.last < config.interval then return end
    local groups, payload = sender.groups, sender.payload
    if #groups == 0 then sender.error = nil; return end
    local count = math.min(18, #groups - sender.cursor + 1)
    for i = #payload, 1, -1 do payload[i] = nil end
    payload[1], payload[2], payload[3] = 0x00, 0xea, 0xa1
    payload[4] = count == 1 and 0x07 or 0x09
    if count > 1 then payload[5] = count end
    for i = sender.cursor, sender.cursor + count - 1 do
        local group = groups[i]
        payload[#payload + 1] = group.address
        payload[#payload + 1] = math.floor(group.value / 256)
        payload[#payload + 1] = group.value % 256
    end
    local queued = crossfireTelemetryPush(0x32, payload)
    if not queued then
        sender.error = queued == nil and "CRSF/ELRS inaktiv" or "CRSF FIFO belegt"
        return
    end
    sender.error = nil
    sender.cursor = sender.cursor + count
    if sender.cursor > #groups then
        for i = #groups, 1, -1 do
            if not groups[i].used then
                sender.map[groups[i].address] = nil
                table.remove(groups, i)
            end
        end
        sender.cursor, sender.last, sender.pending = 1, now, false
    else
        sender.pending = true
    end
end

return M
