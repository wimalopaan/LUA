-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 Wilhelm Meier

local models = {}
local name = "MultiSw NG"

local function modelApp(dir)
    local info = model.getInfo()
    if type(info) ~= "table" then return end
    local key = info.filename
    if type(key) ~= "string" or key == "" then key = info.name end
    if type(key) ~= "string" or key == "" then return end
    -- Hex encoding preserves distinct model names without unsafe path characters.
    local filename = string.gsub(key, ".", function(c) return string.format("%02x", string.byte(c)) end)
    local app = models[dir .. filename]
    if not app then
        app = {dir = dir, path = dir .. "model_" .. filename, phase = "boot"}
        models[dir .. filename] = app
    end
    return app
end

local function create(zone, options, dir)
    dir = dir or "/WIDGETS/lvglMultiSwNG/"
    local app = modelApp(dir) or {
        dir = dir, phase = "identity", error = "Waiting for model name or filename",
    }
    return {zone = zone, options = options, app = app, page = "control"}
end

local function background(widget)
    local app = widget.app
    if not lvgl then return end
    if app.phase == "identity" then
        local resolved = modelApp(app.dir)
        if not resolved then return end
        widget.app, app = resolved, resolved
    end
    if app.phase == "boot" then
        local script, err = loadScript(app.dir .. "app.lua", "t")
        if not script then
            app.phase, app.error = "error", "Cannot load app.lua: " .. tostring(err)
            return
        end
        local ok, result = pcall(script, app)
        if not ok then app.phase, app.error = "error", tostring(result); return end
        app.lastTick = getTime()
        return
    end
    if app.tick then app.tick() end
end

local function refresh(widget)
    if not lvgl then
        lcd.drawText(widget.zone.x, widget.zone.y, "LVGL support required", COLOR_THEME_WARNING)
        return
    end
    background(widget)
    if widget.app.ui then widget.app.ui.refresh(widget)
    elseif not widget.loading then
        lvgl.clear()
        local full = lvgl.isFullScreen() or lvgl.isAppMode()
        local width, height = full and LCD_W or widget.zone.w, full and LCD_H or widget.zone.h
        local _, lineHeight = lcd.sizeText("M", SMLSIZE)
        lvgl.build({{type = "label", x = 4, y = 4, w = math.max(1, width - 8),
            h = math.max(1, math.min(lineHeight, height - 8)), font = SMLSIZE, text = function()
            local status = widget.app.status and widget.app.status()
                or widget.app.error or "Loading MultiSwitch NG ..."
            return (string.gsub(status, "[%c]", " "))
        end}})
        widget.loading = true
    end
end

return {
    name = name, useLvgl = lvgl ~= nil, options = {},
    create = create, background = background, refresh = refresh,
    update = function(widget, options)
        widget.options, widget.renderRevision = options, nil
    end,
}
