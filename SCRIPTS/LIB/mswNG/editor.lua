-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 Wilhelm Meier

local app = ...
local core = app.core
local M = {screen = "global", row = 1, control = 1}
local chars = " ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_."

local function page()
    return app.config.pages[app.page]
end

local function control()
    return page()[2][M.control]
end

function M.count()
    if M.screen == "global" then return 7 end
    if M.screen == "page" then return #page()[2] + 5 end
    return 7
end

function M.title()
    return M.screen == "global" and "Einstellungen"
        or (M.screen == "page" and ("Seite " .. app.page) or ("Schalter " .. M.control))
end

function M.item(index)
    if M.screen == "global" then
        if index == 1 then return "Seiten", #app.config.pages end
        if index == 2 then return "Seite bearbeiten", app.page end
        if index == 3 then return "Intervall ms", app.config.interval * 10 end
        if index == 4 then return "Menutaste", core.menuActions[(app.config.menuAction or 0) + 1] end
        if index == 5 then return "Speichern/zurueck", "" end
        if index == 6 then return "Softwareversion", app.version end
        return "Zurueck", ""
    elseif M.screen == "page" then
        if index == 1 then return "Seite", app.page end
        if index == 2 then return "Titel", page()[3] end
        if index == 3 then return "Standardadresse", page()[1] end
        if index <= #page()[2] + 3 then return page()[2][index - 3][1], ">" end
        if index == #page()[2] + 4 then return "Schalter neu", #page()[2] .. "/12" end
        return "Zurueck", ""
    else
        if index == 1 then return "Name", control()[1] end
        if index == 2 then
            return "Adresse", control()[2] == -1 and ("Seite:" .. page()[1]) or control()[2]
        end
        if index == 3 then return "Ausgang", control()[3] end
        if index == 4 then
            local id = control()[5] or 0
            if id == 0 then return "Steuerung", "Manuell" end
            local name = type(getSwitchName) == "function" and getSwitchName(id)
            return "Steuerung", name or ("Fehlt:" .. id)
        end
        if index == 5 then return "Typ", core.controlTypes[(control()[6] or 0) + 1] end
        if index == 6 then return "Loeschen", "" end
        return "Zurueck", ""
    end
end

local function number(value, low, high, step)
    M.editing, M.value, M.low, M.high, M.step = "number", value, low, high, step or 1
end

local function text(value, length, label)
    M.editing, M.value, M.position = "text", value .. string.rep(" ", length - #value), 1
    M.length, M.textLabel = length, label
end

local function choice(value, labels)
    number(value, 0, #labels - 1)
    M.editing, M.labels = "choice", labels
end

function M.displayValue()
    if M.editing == "choice" then return M.labels[M.value + 1] end
    if M.editing ~= "switch" then return M.value end
    local id = M.switches[M.value]
    return id == 0 and "Manuell" or getSwitchName(id) or ("Fehlt:" .. id)
end

local function switchEdit()
    if type(switches) ~= "function" or type(getSwitchName) ~= "function" then
        app.message = "Schalterauswahl fehlt"
        return
    end
    M.switches = {0}
    local selected, current = 1, control()[5] or 0
    for id in switches() do
        if id ~= 0 then
            M.switches[#M.switches + 1] = id
            if id == current then selected = #M.switches end
        end
    end
    number(selected, 1, #M.switches)
    M.editing = "switch"
end

local function apply()
    local config, ok, err = app.config, true
    if M.editing == "text" then
        local value = string.gsub(M.value, "%s+$", "")
        if #value == 0 then
            ok, err = nil, M.textLabel .. " darf nicht leer sein"
        elseif M.screen == "page" then page()[3] = value
        else control()[1] = value end
    elseif M.screen == "global" then
        if M.row == 1 then
            if M.value < #config.pages and not M.confirm then
                M.confirm = "Seiten loeschen?"
                return
            end
            while #config.pages > M.value do table.remove(config.pages) end
            while #config.pages < M.value do
                ok, err = core.addPage(config)
                if not ok then break end
            end
            app.page = math.min(app.page, #config.pages)
        elseif M.row == 3 then
            config.interval = M.value / 10
        else
            config.menuAction = M.value
        end
    elseif M.screen == "page" then
        if M.row == 1 then
            app.page = M.value
            M.editing = nil
            return
        end
        ok, err = core.pageAddress(config, page(), M.value)
    else
        local c = control()
        if M.row == 2 then
            ok, err = core.route(config, page(), c, M.value, c[3])
        elseif M.row == 3 then
            ok, err = core.route(config, page(), c, c[2], M.value)
        elseif M.row == 4 then
            c[5], c[4] = M.switches[M.value], 0
        else
            c[6], c[4] = M.value, 0
        end
    end
    if ok then app.changed(); M.editing, M.confirm = nil, nil else app.message = err end
end

local function enter()
    local config = app.config
    if M.screen == "global" then
        if M.row == 1 then number(#config.pages, 1, 4)
        elseif M.row == 2 then M.screen, M.row = "page", 1
        elseif M.row == 3 then number(config.interval * 10, 50, 10000, 50)
        elseif M.row == 4 then choice(config.menuAction or 0, core.menuActions)
        elseif M.row == 5 then return "save"
        elseif M.row == 7 then return "close" end
    elseif M.screen == "page" then
        if M.row == 1 then number(app.page, 1, #config.pages)
        elseif M.row == 2 then text(page()[3], core.titleLength, "Titel")
        elseif M.row == 3 then number(page()[1], 0, 255)
        elseif M.row <= #page()[2] + 3 then
            M.control, M.screen, M.row = M.row - 3, "control", 1
        elseif M.row == #page()[2] + 4 then
            local ok, err = core.addSwitch(config, page())
            if ok then
                app.changed()
                M.control, M.screen, M.row = #page()[2], "control", 1
            else app.message = err end
        else M.screen, M.row = "global", 2 end
    else
        local c = control()
        if M.row == 1 then
            text(c[1], core.nameLength, "Name")
        elseif M.row == 2 then number(c[2], -1, 255)
        elseif M.row == 3 then number(c[3], 1, 8)
        elseif M.row == 4 then switchEdit()
        elseif M.row == 5 then choice(c[6] or 0, core.controlTypes)
        elseif M.row == 6 then M.confirm = "Schalter loeschen?"
        else M.screen, M.row = "page", M.control + 3 end
    end
end

function M.run(event)
    if M.confirm then
        if event == EVT_VIRTUAL_EXIT then M.confirm, M.editing = nil, nil
        elseif event == EVT_VIRTUAL_ENTER then
            if M.screen == "control" then
                table.remove(page()[2], M.control)
                app.changed()
                M.screen, M.row, M.confirm = "page", 3, nil
            else apply() end
        end
        return
    end
    if M.editing then
        if event == EVT_VIRTUAL_EXIT then M.editing = nil
        elseif event == EVT_VIRTUAL_ENTER then
            if M.editing == "text" and M.position < M.length then M.position = M.position + 1
            else apply() end
        elseif M.editing == "text" and event == EVT_VIRTUAL_NEXT_PAGE then apply()
        elseif M.editing == "text" and event == EVT_VIRTUAL_PREV_PAGE then
            M.position = math.max(1, M.position - 1)
        elseif event == EVT_VIRTUAL_NEXT or event == EVT_VIRTUAL_PREV then
            local delta = event == EVT_VIRTUAL_NEXT and 1 or -1
            if M.editing ~= "text" then
                M.value = math.max(M.low, math.min(M.high, M.value + delta * M.step))
            else
                local c = string.sub(M.value, M.position, M.position)
                local index = string.find(chars, c, 1, true) or 1
                index = (index - 1 + delta) % #chars + 1
                M.value = string.sub(M.value, 1, M.position - 1) .. string.sub(chars, index, index) ..
                    string.sub(M.value, M.position + 1)
            end
        end
        return
    end
    if event == EVT_VIRTUAL_EXIT then
        if M.screen == "global" then return "close"
        elseif M.screen == "page" then M.screen, M.row = "global", 2
        else M.screen, M.row = "page", M.control + 3 end
    elseif event == EVT_VIRTUAL_NEXT then M.row = M.row % M.count() + 1
    elseif event == EVT_VIRTUAL_PREV then M.row = (M.row - 2) % M.count() + 1
    elseif event == EVT_VIRTUAL_ENTER then return enter() end
end

return M
