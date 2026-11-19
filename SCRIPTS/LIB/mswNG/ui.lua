-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 Wilhelm Meier

local app = ...
local core = app.core
local M = {}
local editor, exitRow
local selected = 1
-- Virtual MENU is a BREAK event; derive its other phases from the exported ENTER phases.
local menuFirst = EVT_VIRTUAL_MENU + EVT_ENTER_FIRST - EVT_ENTER_BREAK
local menuLong = EVT_VIRTUAL_MENU + EVT_ENTER_LONG - EVT_ENTER_BREAK
local menuRepeat = EVT_VIRTUAL_MENU + EVT_ENTER_REPT - EVT_ENTER_BREAK

local function header(text)
    lcd.drawFilledRectangle(0, 0, LCD_W, 9)
    lcd.drawText(1, 0, text, SMLSIZE + INVERS)
end

local function footer(text)
    lcd.drawText(0, LCD_H - 8, string.sub(text, 1, math.floor(LCD_W / 5)), SMLSIZE)
end

local function fit(text, width)
    return string.sub(tostring(text), 1, math.max(1, math.floor(width / 5)))
end

local function status()
    return app.sender.inputError or app.sender.offError or app.sender.error
end

local function drawControls()
    local page = app.config.pages[app.page]
    local controls = page[2]
    local columns = math.max(1, math.floor(LCD_W / 64))
    local needed = math.max(1, math.ceil(#controls / columns))
    local rows = math.min(needed, math.max(1, math.floor((LCD_H - 19) / 11)))
    local cellWidth, cellHeight = math.floor(LCD_W / columns), math.floor((LCD_H - 19) / rows)
    local suffix = " " .. app.page .. "/" .. #app.config.pages .. (app.dirty and " *" or "")
    header(fit(page[3], LCD_W - 2 - #suffix * 5) .. suffix)
    local offset = math.max(0, math.floor((selected - 1) / columns) - rows + 1) * columns
    for index = offset + 1, math.min(#controls + 2, offset + rows * columns) do
        local position = index - offset - 1
        local x, y = (position % columns) * cellWidth, 10 + math.floor(position / columns) * cellHeight
        local flags = SMLSIZE
        if index == selected then
            lcd.drawFilledRectangle(x, y, cellWidth - 1, cellHeight - 1)
            flags = flags + INVERS
        else
            lcd.drawRectangle(x, y, cellWidth - 1, cellHeight - 1)
        end
        local control = controls[index]
        local text
        if control then
            text = (control[4] == 1 and "+" or "-") .. (control[6] == 1 and "T" or "") ..
                ((control[5] or 0) ~= 0 and ">" or "") .. control[1]
        else text = index == #controls + 1 and "Seite >" or "Setup" end
        lcd.drawText(x + 2, y + math.floor((cellHeight - 8) / 2), fit(text, cellWidth - 5), flags)
    end
    footer(status() or (app.config.menuAction == 1 and "ENTER +/- MENU Taster" or "ENTER +/-  PAGE >"))
end

local function drawEditor()
    header(editor.title() .. (app.dirty and " *" or ""))
    if editor.confirm then
        lcd.drawText(0, 19, fit(editor.confirm, LCD_W), SMLSIZE)
        footer("ENTER ja  EXIT nein")
        return
    end
    if editor.editing == "text" then
        lcd.drawText(0, 12, editor.textLabel .. ":", SMLSIZE)
        lcd.drawText(0, 25, string.sub(editor.value, 1, editor.position - 1), SMLSIZE)
        lcd.drawText(lcd.getLastPos(), 25,
                     string.sub(editor.value, editor.position, editor.position), SMLSIZE + INVERS)
        lcd.drawText(lcd.getLastPos(), 25, string.sub(editor.value, editor.position + 1), SMLSIZE)
        footer("Zeichen " .. editor.position .. " PAGE=OK")
        return
    end
    local visible = math.max(1, math.floor((LCD_H - 19) / 9))
    local offset = math.max(0, editor.row - visible)
    local valueX = math.floor(LCD_W * 0.53)
    for index = offset + 1, math.min(editor.count(), offset + visible) do
        local label, value = editor.item(index)
        local flags, y = SMLSIZE, 10 + (index - offset - 1) * 9
        if index == editor.row then flags = flags + INVERS end
        local valueFlags = flags
        if index == editor.row and editor.editing then
            value = editor.displayValue()
            valueFlags = valueFlags + BLINK
        end
        lcd.drawText(LCD_W - 1, y, fit(value, LCD_W - valueX - 1), valueFlags + RIGHT)
        local labelWidth = value == "" and LCD_W or lcd.getLastLeftPos() - 3
        lcd.drawText(0, y, fit(label, labelWidth), flags)
    end
    footer(status() or (editor.editing and "ENTER OK EXIT Abbruch" or "ENTER edit EXIT zurueck"))
end

local function activate(controls, viaMenu)
    local control = controls[selected]
    if control then
        if (control[5] or 0) ~= 0 then
            app.message = "Steuerung durch Schalter"
        elseif control[6] == 1 then
            if viaMenu then
                app.held, control[4] = control, 1
                core.rebuild(app.sender, app.config)
            else
                app.message = app.config.menuAction == 1 and "Taster: Menutaste nutzen"
                    or "Menutaste: Bedienung waehlen"
            end
        else
            control[4] = 1 - control[4]
            core.rebuild(app.sender, app.config)
        end
    elseif selected == #controls + 1 then
        app.page, selected = app.page % #app.config.pages + 1, 1
    else
        editor = app.load("editor", app)
    end
end

function M.run(event)
    if app.held and event ~= 0 and event ~= menuLong and event ~= menuRepeat then app.release() end
    lcd.clear()
    if app.busy then
        app.release()
        header("MultiSwitchNG")
        footer("SD laden/speichern...")
        return 0
    end
    if app.fatal then
        app.release()
        header("mswNG SD-Fehler")
        lcd.drawText(0, 19, fit(app.fatal, LCD_W), SMLSIZE)
        footer(app.telemetry and "Konfiguration pruefen" or "EXIT beendet")
        return not app.telemetry and event == EVT_VIRTUAL_EXIT and 2 or 0
    end
    if app.message then
        header("mswNG Hinweis")
        lcd.drawText(0, 19, fit(app.message, LCD_W), SMLSIZE)
        lcd.drawText(0, 28, fit(string.sub(app.message, math.floor(LCD_W / 5) + 1), LCD_W), SMLSIZE)
        footer("ENTER/EXIT weiter")
        if event == EVT_VIRTUAL_ENTER or event == EVT_VIRTUAL_EXIT then app.message = nil end
    elseif exitRow then
        header("Aenderungen speichern?")
        local options = {"Speichern/beenden", "Verwerfen/beenden", "Zurueck"}
        if event == EVT_VIRTUAL_NEXT then exitRow = exitRow % 3 + 1
        elseif event == EVT_VIRTUAL_PREV then exitRow = (exitRow - 2) % 3 + 1
        elseif event == EVT_VIRTUAL_EXIT then exitRow = nil
        elseif event == EVT_VIRTUAL_ENTER then
            local choice = exitRow
            exitRow = nil
            if choice == 1 then app.save("exit")
            elseif choice == 2 then return 2 end
        end
        for i = 1, 3 do
            lcd.drawText(0, 10 + (i - 1) * 10, options[i], SMLSIZE + (exitRow == i and INVERS or 0))
        end
    elseif editor then
        local action = editor.run(event)
        if action == "close" then editor, selected = nil, 1
        elseif action == "save" then app.save("close") end
        if editor then drawEditor() else drawControls() end
    else
        local controls = app.config.pages[app.page][2]
        if event == EVT_VIRTUAL_EXIT then
            if not app.telemetry then
                if app.dirty then exitRow = 1 else return 2 end
            end
        elseif event == EVT_VIRTUAL_NEXT_PAGE or event == EVT_VIRTUAL_PREV_PAGE then
            local delta = event == EVT_VIRTUAL_NEXT_PAGE and 1 or -1
            app.page, selected = (app.page - 1 + delta) % #app.config.pages + 1, 1
        elseif event == EVT_VIRTUAL_NEXT then selected = selected % (#controls + 2) + 1
        elseif event == EVT_VIRTUAL_PREV then selected = (selected - 2) % (#controls + 2) + 1
        elseif event == menuFirst and app.config.menuAction == 1 then
            activate(controls, true)
        elseif event == EVT_VIRTUAL_MENU then
            if app.config.menuAction == 2 then
                app.page, selected = app.page % #app.config.pages + 1, 1
            elseif app.config.menuAction == 3 then
                editor = app.load("editor", app)
            end
        elseif event == EVT_VIRTUAL_ENTER then
            activate(controls, false)
        end
        if editor then drawEditor() else drawControls() end
    end
    return 0
end

return M
