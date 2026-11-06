-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 Wilhelm Meier

local app = ...
local M = {}

local function release(view)
    if view.held then app.set(view.held, 0); view.held = nil end
end

local function navigate(view, page)
    release(view)
    view.page, view.renderRevision = page, nil
end

local function commit(view, kind, record, remove, accepted)
    local job = app.commit(kind, record, remove, function(ok)
        view.pending, view.renderRevision = nil, nil
        if ok and accepted then accepted() end
    end)
    if job then view.pending, view.renderRevision = job, nil end
end

local function button(text, press, active)
    return {type = "button", text = text, press = press, active = active}
end

local function row(children, width)
    return {type = "box", flexFlow = lvgl.FLOW_ROW, w = width, children = children}
end

local function scaled(value)
    -- Legacy EdgeTX versions do not export the native layout dimensions.
    if LCD_W > LCD_H and LCD_W == 320 then return math.floor((value * 4 + 3) / 5) end
    if LCD_W > LCD_H and LCD_W == 800 then return math.floor((value * 3 + 1) / 2) end
    return value
end

local function actionRow(items, width)
    local height, gap = lvgl.UI_ELEMENT_HEIGHT or scaled(32), scaled(8)
    local itemWidth = math.floor((width - gap * (#items + 1)) / #items)
    for index, item in ipairs(items) do
        item.x, item.y, item.w, item.h = gap + (index - 1) * (itemWidth + gap), gap / 2, itemWidth, height
    end
    return {type = "box", w = width, h = height + gap, scrollBar = false,
            scrollDir = lvgl.SCROLL_OFF, children = items}
end

local function field(caption, input, width)
    local height = lvgl.UI_ELEMENT_HEIGHT or scaled(32)
    local captionWidth, gap = math.floor(width * 0.45), scaled(8)
    input.x, input.y = captionWidth + gap, gap / 2
    input.w, input.h = math.min(input.w or scaled(180), width - captionWidth - gap), height
    return {type = "box", w = width, h = height + gap, scrollBar = false,
            scrollDir = lvgl.SCROLL_OFF, children = {
                {type = "label", text = caption, x = 0, y = gap / 2, w = captionWidth,
                 h = height, align = LEFT | VCENTER},
                input,
            }}
end

local function heading(text, width)
    return {type = "label", text = text, w = width, h = scaled(26), font = BOLD}
end

local function hint(text, width)
    return {type = "label", text = text, w = width, font = SMLSIZE}
end

local function unchanged(revision)
    if app.revision ~= revision then
        app.error = "Configuration changed in another view; cancel and reopen editor"
        return false
    end
    return true
end

local function number(record, key, low, high)
    return {type = "numberEdit", min = low, max = high, w = scaled(88),
            get = function() return record[key] end,
            set = function(value) record[key] = value end}
end

local function text(record, key, length)
    return {type = "textEdit", value = record[key], length = length, w = scaled(180),
            set = function(value) record[key] = value end}
end

local function toggle(record, key)
    return {type = "toggle", get = function() return record[key] end,
            set = function(value) record[key] = value end}
end

local function edit(view, kind, record)
    view.edit, view.editKind = app.config.copy(record), kind
    view.editRevision, view.editSection, view.editReturn = app.revision, "Basic", view.page
    navigate(view, "editor")
end

local function selectTab(view, id)
    release(view)
    view.tab, view.renderRevision = id, nil
end

local function controlWidget(view, control, width, height)
    local id = control.id
    local function active()
        return app.active(control) and (control.type == 5 and control.source == 0
                                       or control.type ~= 5 and control.switch == 0)
    end
    local function set(value)
        if active() then app.set(id, value) end
    end
    local common = {
        type = control.type == 4 and "momentaryButton" or "button",
        name = "c" .. id, text = control.name, w = width, h = height,
        color = control.color, textColor = control.textColor, font = control.font,
        active = active,
    }
    if control.type == 1 then
        common.checked = app.values[id] ~= 0
        common.press = function()
            set(app.values[id] == 0 and 1 or 0)
            return app.values[id]
        end
    elseif control.type == 4 then
        common.cornerRadius = math.floor(math.min(width, height) / 2)
        common.press = function() release(view); view.held = id; set(1) end
        common.release = function() if view.held == id then release(view) end end
    else
        local input = {type = control.type == 2 and "toggle" or "slider", w = width - 8,
                       h = math.max(20, height - 24), color = control.color, active = active}
        if control.type == 3 then
            input.min, input.max = -1, 1
            input.get = function() return app.values[id] == 2 and -1 or app.values[id] end
            input.set = function(value) set(value == -1 and 2 or value) end
        else
            input.min, input.max = 0, control.type == 5 and 100 or 1
            input.get = function() return app.values[id] end
            input.set = set
        end
        return {type = "box", w = width, h = height, flexFlow = lvgl.FLOW_COLUMN,
                children = {{type = "label", text = control.name, font = control.font,
                             color = control.textColor, w = width - 8}, input}}
    end
    if control.image ~= "" then
        common.children = {{type = "image", file = "/IMAGES/" .. control.image,
                            x = 0, y = 0, w = height - 8, h = height - 8}}
    end
    return common
end

local function controlFooter(view, width)
    local children = {}
    children[#children + 1] = {type = "hline", w = width, h = 1}
    children[#children + 1] = button(view.setupOpen and "Hide setup" or "Setup", function()
        view.setupOpen = not view.setupOpen
        view.renderRevision = nil
    end)
    if view.setupOpen then
        children[#children + 1] = row({
            button("Tab settings", function() navigate(view, "tab") end),
            button("New tab", function()
                local new = app.newTab()
                if new then edit(view, "tab", new) end
            end),
            button("Global", function() edit(view, "config", app.data.header) end),
        }, width)
    end
    return children
end

local function tabPage(view, width)
    local tab = app.tabs[view.tab]
    local children = {
        actionRow({
            button("Edit tab", function() edit(view, "tab", tab) end),
            button("Add control", function()
                local control = app.newControl(tab)
                if control then edit(view, "control", control) end
            end),
        }, width),
    }
    return children
end

local function tabControlRow(view, width, control)
    local tab = app.tabs[view.tab]
    local height, gap = lvgl.UI_ELEMENT_HEIGHT or scaled(32), scaled(8)
    local editWidth, addressWidth = scaled(88), scaled(84)
    local addressX = width - editWidth - gap - addressWidth
    local editButton = button("Edit", function() edit(view, "control", control) end)
    editButton.x, editButton.y, editButton.w, editButton.h = width - editWidth, gap / 2, editWidth, height
    return {type = "box", w = width, h = height + gap, scrollBar = false, scrollDir = lvgl.SCROLL_OFF,
            children = {
                {type = "label", x = 0, y = gap / 2, w = addressX - gap, h = height,
                 text = control.name, align = LEFT | VCENTER},
                {type = "label", x = addressX, y = gap / 2, w = addressWidth, h = height,
                 text = app.config.address(control, tab) .. " / " .. control.output, align = LEFT | VCENTER},
                editButton,
            }}
end

local function movePage(view, width, targets)
    local control = view.moveControl
    local names, ids = targets.names, targets.ids
    if not view.moveTarget then view.moveTarget = ids[1] end
    local children = {heading("Move " .. control.name, width)}
    if #ids > 0 then
        children[#children + 1] = field("Target tab:", {
            type = "choice", values = names, w = 180,
            get = function()
                return targets.positions[view.moveTarget] or 1
            end,
            set = function(value) view.moveTarget = ids[value] end,
        }, width)
        children[#children + 1] = hint(function()
            local target = app.tabs[view.moveTarget]
            if not target then return "Target tab no longer exists" end
            if control.address == -1 then
                return "Inherited address: " .. view.moveAddress .. " -> " .. target.address ..
                       "; output: " .. control.output
            end
            return "Explicit address stays " .. control.address .. "; output: " .. control.output
        end, width)
    else children[#children + 1] = hint("No other tab available", width) end
    children[#children + 1] = hint("Moving also applies the current editor draft.", width)
    return children
end

local function switchPicker(record, key)
    local filter = lvgl.SW_SWITCH | lvgl.SW_TRIM | lvgl.SW_LOGICAL_SWITCH | lvgl.SW_CLEAR
    if lvgl.SW_VIRTUAL then filter = filter | lvgl.SW_VIRTUAL end
    return {type = "switch", filter = filter, w = scaled(150),
            get = function() return record[key] end,
            set = function(value) record[key] = value end}
end

local function typePicker(view, record)
    local ids, names, positions = {}, {}, {}
    for index, id in ipairs(app.config.typeIds[app.data.header.protocol]) do
        ids[index], names[index], positions[id] = id, app.config.types[id], index
    end
    if not positions[record.type] then
        ids[#ids + 1], names[#names + 1] = record.type, app.config.types[record.type]
        positions[record.type] = #ids
    end
    return {type = "choice", values = names, w = scaled(180),
        get = function() return positions[record.type] end,
        set = function(value) record.type = ids[value]; view.renderRevision = nil end}
end

local function editorPage(view, width)
    local record, kind = view.edit, view.editKind
    local children = {}
    local function section(title) children[#children + 1] = heading(title, width) end
    local function add(caption, input) children[#children + 1] = field(caption, input, width) end
    if kind == "config" then
        section("General")
        add("Name:", text(record, "name", 32))
        add("Auto-Save:", toggle(record, "autoSave"))
        add("Protocol:", {type = "choice", values = app.config.protocols, w = scaled(180),
            get = function() return record.protocol + 1 end,
            set = function(value) record.protocol = value - 1; view.renderRevision = nil end})
        section(app.config.protocols[record.protocol + 1])
        add("Interval:", number(record, "interval", 5, 1000))
        children[#children + 1] = hint("Interval unit: 10 ms.", width)
        if record.protocol == 1 then
            add("Physical ID:", number(record, "sportPhysicalId", 0, 0x1b))
            add("App ID:", number(record, "sportAppId", 0, 255))
            children[#children + 1] = hint("App ID is the high byte; default: 81 (0x51).", width)
            children[#children + 1] = hint("S.Port WM: no sliders or LED color transmission.", width)
            children[#children + 1] = hint("Do not register the addressed device as a telemetry sensor.", width)
        elseif record.protocol >= 2 then
            children[#children + 1] = hint("Physical ID: 27 (0x1b), frame: 0x10.", width)
            children[#children + 1] = hint(record.protocol == 2 and "Data ID: 0xac00." or "Data ID: 0xfa07.", width)
            children[#children + 1] = hint("ACW: no 3Pos, sliders or LED color transmission.", width)
            children[#children + 1] = hint("Type, options and on-PWM are set per control.", width)
        else
            add("Destination:", number(record, "destination", 0, 255))
            add("LED colors:", toggle(record, "sendColors"))
            children[#children + 1] = actionRow({
                button("Send colors now", function() app.backend.colors(app.sender, true) end,
                    function() return record.protocol == 0 and app.sender.protocol == 0
                        and record.sendColors == 1 end),
            }, width)
            if app.sender.protocol ~= 0 then
                children[#children + 1] = hint("Apply CRSF before sending colors.", width)
            end
        end
    elseif kind == "tab" then
        section("General")
        add("Name:", text(record, "name", 32))
        add("Default address:", number(record, "address", 0, 255))
        children[#children + 1] = hint("Address changes affect all inheriting controls.", width)
        section("Layout")
        add("Columns:", number(record, "columns", 1, 4))
        add("Height:", number(record, "height", 0, 240))
        children[#children + 1] = hint("Height: 0 = fit eight controls; otherwise 30..240.", width)
        if app.tabs[record.id] then
            section("Management")
            local revision = view.editRevision
            children[#children + 1] = actionRow({
                button("Delete tab", function()
                    if not unchanged(revision) then return end
                    lvgl.confirm({title = "Delete tab", message = "Delete this tab and all its controls?",
                        confirm = function()
                            if not unchanged(revision) then return end
                            commit(view, "tab", record, true, function()
                                view.tab = app.data.tabs[1].id
                                navigate(view, "control")
                            end)
                        end})
                end, function() return #app.data.tabs > 1 end),
            }, width)
        end
    elseif view.editSection == "Inputs" then
        section("Physical inputs")
        if record.type == 5 then
            add("Source:", {type = "source", w = scaled(180),
                get = function() return record.source end, set = function(value) record.source = value end})
            children[#children + 1] = hint("Source: 0..1024 = 0..100%; negative values = 0%.", width)
        else
            add("Switch:", switchPicker(record, "switch"))
            if record.type == 3 then add("Switch 2:", switchPicker(record, "switch2")) end
        end
        add("Activation:", switchPicker(record, "activation"))
        if record.type ~= 5 then
            section("Exclusive group")
            add("Mutex group:", number(record, "group", 0, 255))
            children[#children + 1] = hint("Group 0: no mutual exclusion.", width)
        end
    elseif view.editSection == "Appearance" then
        section("Appearance")
        add("Visible:", toggle(record, "visible"))
        add("Color:", {type = "color",
            get = function() return record.color end, set = function(value) record.color = value end})
        add("Text color:", {type = "color",
            get = function() return record.textColor end, set = function(value) record.textColor = value end})
        add("Font:", {type = "font", w = scaled(100),
            get = function() return record.font end, set = function(value) record.font = value end})
        if record.type == 1 or record.type == 4 then
            add("Image:", {type = "file", folder = "/IMAGES", title = "Button image",
                get = function() return record.image end, set = function(value) record.image = value end})
            children[#children + 1] = actionRow({
                button("Clear image", function() record.image = ""; view.renderRevision = nil end,
                    function() return record.image ~= "" end),
            }, width)
        end
    else
        section("Basic")
        add("Name:", text(record, "name", 32))
        add("Type:", typePicker(view, record))
        add("Address:", number(record, "address", -1, 255))
        add("Output:", number(record, "output", 1, 8))
        children[#children + 1] = hint("Address -1: inherit the tab address.", width)
        if app.data.header.protocol >= 2 then
            children[#children + 1] = hint("ACW number = address * 8 + output; range: 1..255.", width)
            section("ACW output")
            add("ACW type:", number(record, "sportType", 0, 255))
            add("ACW options:", number(record, "sportOptions", 0, 255))
            add("On PWM:", number(record, "sportPwmOn", 0, 255))
            children[#children + 1] = hint("Off PWM: 0; on-PWM default: 255.", width)
        end
        if app.controls[record.id] then
            section("Management")
            local revision = view.editRevision
            children[#children + 1] = actionRow({
                button("Move", function()
                    if not unchanged(revision) then return end
                    view.moveControl = app.config.copy(record)
                    view.moveRevision, view.moveTarget = revision, nil
                    view.moveAddress = app.config.address(record, app.tabs[record.tab])
                    navigate(view, "move")
                end, function() return #app.data.tabs > 1 end),
                button("Delete control", function()
                    if not unchanged(revision) then return end
                    lvgl.confirm({title = "Delete control", message = "Delete " .. record.name .. "?",
                        confirm = function()
                            if not unchanged(revision) then return end
                            commit(view, "control", record, true, function() navigate(view, "tab") end)
                        end})
                end),
            }, width)
        end
    end
    return children
end

local function editorActions(view)
    local record, kind = view.edit, view.editKind
    return {
        button("Apply", function()
            if not unchanged(view.editRevision) then return end
            commit(view, kind, record, false, function()
                if kind == "tab" then view.tab = record.id end
                if kind == "control" then view.tab = record.tab end
                navigate(view, kind == "config" and "control" or "tab")
            end)
        end),
        button("Cancel", function() navigate(view, view.editReturn or "control") end),
    }
end

local function moveActions(view)
    local control = view.moveControl
    return {
        button("Move", function()
            if app.revision ~= view.moveRevision then
                app.error = "Configuration changed in another view; cancel and reopen move"
                return
            end
            local moved = app.config.copy(control)
            moved.tab = view.moveTarget
            commit(view, "control", moved, false, function()
                view.tab = moved.tab
                navigate(view, "tab")
            end)
        end, function() return app.tabs[view.moveTarget] ~= nil and view.moveTarget ~= control.tab end),
        button("Cancel", function() navigate(view, "editor") end),
    }
end

local function exit(view)
    release(view)
    if app.dirty and app.data.header.autoSave == 1 then
        app.save()
        lvgl.exitFullScreen()
    elseif app.dirty then
        lvgl.confirm({title = "Save configuration", message = "Save changes before closing?",
            confirm = function() app.save(); lvgl.exitFullScreen() end,
            cancel = function() lvgl.exitFullScreen() end})
    else lvgl.exitFullScreen() end
end

local interactive = {
    button = true, momentaryButton = true, toggle = true, slider = true,
    textEdit = true, numberEdit = true, choice = true, switch = true,
    source = true, color = true, font = true, file = true,
}

local function beginBuild(view, full)
    release(view)
    lvgl.clear()
    if app.phase == "ready" and not app.tabs[view.tab] then view.tab = app.data.tabs[1].id end
    view.refs, view.checked, view.pollIndex, view.uiReady = {}, {}, 1, false
    view.full, view.renderRevision, view.renderPhase = full, app.revision, app.phase
    view.buildJob = {phase = "shell", width = LCD_W - 24, index = 1, objects = 0}
    local job = view.buildJob
    job.height = lvgl.PAGE_BODY_HEIGHT or LCD_H - scaled(45)
    job.pad = lvgl.PAD_OUTLINE or scaled(2)
    job.fixed = app.phase == "ready" and view.page ~= "control" and not view.pending
    if job.fixed then
        job.footerHeight = (lvgl.UI_ELEMENT_HEIGHT or scaled(32)) + scaled(44)
        job.toolbarHeight = view.page == "editor" and view.editKind == "control"
            and (lvgl.UI_ELEMENT_HEIGHT or scaled(32)) + scaled(8) or 0
    end
    view.uiJob = view.buildJob
end

local function pageHeader(view, job)
    local params = {
        title = app.data and app.data.header.name or "MultiSwitch NG",
        subtitle = view.page, back = function() exit(view) end,
        flexFlow = lvgl.FLOW_COLUMN, flexPad = job.pad,
    }
    if job.fixed then
        params.flexFlow, params.scrollBar, params.scrollDir = nil, false, lvgl.SCROLL_OFF
    end
    if app.phase == "ready" and view.page == "control" and not view.pending then
        local tabs, selected = app.data.tabs, app.tabOrder[view.tab]
        params.subtitle = tabs[selected].name .. " (" .. selected .. "/" .. #tabs .. ")"
        local function navigation(offset)
            local target = selected + offset
            local function active()
                return view.uiReady and view.uiJob == job and view.renderRevision == app.revision
                    and app.phase == "ready" and not app.prepare and view.page == "control"
                    and target >= 1 and target <= #tabs
            end
            return {
                active = active,
                press = function()
                    if active() then selectTab(view, tabs[target].id) end
                    return 0
                end,
            }
        end
        params.prevButton, params.nextButton = navigation(-1), navigation(1)
    end
    return params
end

local function buildOne(view, job, parent, definition)
    local node = {}
    for key, value in pairs(definition) do
        if key ~= "children" and key ~= "allowBusy" then node[key] = value end
    end
    node.name = node.name or "_node"
    if interactive[node.type] then
        local active = node.active
        local function allowed()
            return view.uiReady and view.uiJob == job and view.renderRevision == app.revision
                and (definition.allowBusy or not app.prepare) and (not active or active())
        end
        node.active = allowed
        for _, key in ipairs({"press", "set"}) do
            local callback = node[key]
            if callback then
                node[key] = function(...)
                    if allowed() then return callback(...) end
                    return 0
                end
            end
            local callback = node.release
            if callback then
                node.release = function(...)
                    if view.uiJob == job then return callback(...) end
                end
            end
        end
    end
    local refs
    if parent then refs = lvgl.build(parent, {node})
    else refs = lvgl.build({node}) end
    if type(refs) ~= "table" or not refs[node.name] then
        app.error, job.failed = "LVGL object creation failed: " .. node.type, true
        return
    end
    job.objects = job.objects + 1
    job.batchObjects = job.batchObjects + 1
    if node.type == "image" then job.pause = true end
    if definition.name then view.refs[definition.name] = refs[node.name] end
    return refs[node.name]
end

local function nodes(job, items, parent, after)
    job.stack = {{items = items, parent = parent, index = 1}}
    job.phase, job.after = "nodes", after
end

local function stepNodes(view, job)
    local frame = job.stack[#job.stack]
    while frame and frame.index > #frame.items do
        job.stack[#job.stack] = nil
        frame = job.stack[#job.stack]
    end
    if not frame then job.phase = job.after; return end
    local definition = frame.items[frame.index]
    if definition.type == "image" and job.batchObjects > 0 then
        job.pause = true
        return
    end
    frame.index = frame.index + 1
    local ref = buildOne(view, job, frame.parent, definition)
    if ref and definition.children then
        job.stack[#job.stack + 1] = {items = definition.children, parent = ref, index = 1}
    end
end

local function stepBuild(view)
    local job = view.buildJob
    local width = job.fixed and job.width - scaled(16) or job.width
    if job.phase == "shell" then
        if view.full then
            job.page = lvgl.page(pageHeader(view, job))
            if not job.page then app.error, job.failed = "Cannot create LVGL page", true end
            job.objects, job.batchObjects, job.pause = job.objects + 1, job.batchObjects + 1, true
            job.phase = "progress"
        else
            nodes(job, {
                {type = "label", x = 4, y = 4, w = view.zone.w - 8,
                 text = app.data and app.data.header.name or "MultiSwitch NG"},
                {type = "label", x = 4, y = 30, w = view.zone.w - 8, text = app.status},
                {type = "label", x = 4, y = 60, w = view.zone.w - 8, text = "Open full screen to control"},
            }, nil, "finish")
        end
    elseif job.phase == "progress" then
        buildOne(view, job, job.page, {
            type = "label", x = job.fixed and 12 or 0,
            y = job.fixed and job.height - scaled(26) or 0,
            w = job.width, visible = function() return not view.uiReady end,
            text = function() return "Building " .. view.page .. ": " .. job.index ..
                (job.list and ("/" .. #job.list) or "") .. " (" .. job.objects .. " objects)" end,
        })
        job.phase = "layout"
    elseif job.phase == "layout" then
        if job.fixed then
            job.content = buildOne(view, job, job.page, {
                type = "box", name = "settings", x = 12, y = job.toolbarHeight + scaled(4),
                w = job.width, h = job.height - job.toolbarHeight - job.footerHeight - scaled(8),
                flexFlow = lvgl.FLOW_COLUMN, flexPad = scaled(4),
                scrollBar = true, scrollDir = lvgl.SCROLL_VER,
            })
            job.phase = "toolbar"
        else job.content, job.phase = job.page, "prefix" end
    elseif job.phase == "toolbar" then
        if job.toolbarHeight > 0 then
            local items = {}
            for _, section in ipairs({"Basic", "Inputs", "Appearance"}) do
                local item = button(section, function()
                    view.editSection, view.renderRevision = section, nil
                end)
                item.checked = (view.editSection or "Basic") == section
                items[#items + 1] = item
            end
            local toolbar = actionRow(items, job.width)
            toolbar.name, toolbar.x, toolbar.y = "sections", 12, 0
            nodes(job, {toolbar}, job.page, "prefix")
        else job.phase = "prefix" end
    elseif job.phase == "prefix" then
        if view.pending and not view.pending.done then
            local cancel = button("Cancel update", function() app.cancelUpdate(view.pending) end,
                function() return app.prepare == view.pending end)
            cancel.allowBusy = true
            nodes(job, {{type = "label", w = width, text = app.status}, cancel}, job.content, "finish")
        elseif app.phase ~= "ready" then
            local items = {{type = "label", w = width, text = app.status}}
            if app.phase == "error" then
                items[#items + 1] = button("Retry loading", function()
                    app.error, app.phase = nil, "files"
                    app.loads = {a = app.storage.load(app.path .. ".a.lua"), b = app.storage.load(app.path .. ".b.lua")}
                end)
                items[#items + 1] = button("Create default configuration", function()
                    lvgl.confirm({title = "Reset configuration", message = "Start with one tab and eight buttons?",
                                  confirm = app.reset})
                end)
            end
            nodes(job, items, job.content, "finish")
        else
            if not app.tabs[view.tab] then view.tab = app.data.tabs[1].id end
            if view.page == "editor" then nodes(job, editorPage(view, width), job.content, "footer")
            elseif view.page == "move" then
                job.targets = {names = {}, ids = {}, positions = {}}
                job.phase = "targets"
            elseif view.page == "tab" then
                job.list = app.tabControls[view.tab]
                nodes(job, tabPage(view, width), job.content, "list")
            else
                job.list = app.visibleControls[view.tab]
                local tab = app.tabs[view.tab]
                job.rowIndex = 0
                if tab.height == 0 then
                    local rows = math.ceil(8 / tab.columns)
                    local available = job.height - 2 * job.pad - (rows - 1) * job.pad - rows * 2 * job.pad
                    job.autoHeight, job.extra = math.floor(available / rows), available % rows
                end
                job.phase = "controls"
            end
        end
    elseif job.phase == "targets" then
        local tab = app.data.tabs[job.index]
        if tab then
            if tab.id ~= view.moveControl.tab then
                local targets = job.targets
                targets.names[#targets.names + 1] = tab.name
                targets.ids[#targets.ids + 1] = tab.id
                targets.positions[tab.id] = #targets.ids
            end
            job.index = job.index + 1
        else nodes(job, movePage(view, width, job.targets), job.content, "footer") end
    elseif job.phase == "controls" then
        local control, tab = job.list[job.index], app.tabs[view.tab]
        if not control then
            nodes(job, controlFooter(view, width), job.content, "footer")
        elseif not job.row then
            job.rowIndex = job.rowIndex + 1
            job.buttonHeight = tab.height ~= 0 and tab.height
                or job.autoHeight + (job.rowIndex <= job.extra and 1 or 0)
            job.row = buildOne(view, job, job.content, {
                type = "box", w = width, h = job.buttonHeight + 2 * job.pad,
                flexFlow = lvgl.FLOW_ROW, flexPad = job.pad, scrollBar = false, scrollDir = lvgl.SCROLL_OFF,
            })
            job.column = 0
        else
            nodes(job, {controlWidget(view, control, math.floor((width - 16) / tab.columns) - 12, job.buttonHeight)},
                job.row, "next-control")
        end
    elseif job.phase == "next-control" then
        job.index, job.column = job.index + 1, job.column + 1
        if job.column == app.tabs[view.tab].columns then job.row = nil end
        job.phase = "controls"
    elseif job.phase == "list" then
        local control = job.list[job.index]
        if control then nodes(job, {tabControlRow(view, width, control)}, job.content, "next-row")
        else job.phase = "footer" end
    elseif job.phase == "next-row" then
        job.index, job.phase = job.index + 1, "list"
    elseif job.phase == "footer" then
        if job.fixed then
            local actions
            if view.page == "editor" then actions = editorActions(view)
            elseif view.page == "move" then actions = moveActions(view)
            else actions = {button("Control", function() navigate(view, "control") end)} end
            actions[#actions + 1] = button("Save", app.save, function() return app.dirty and not app.saveJob end)
            local bar = actionRow(actions, job.width)
            bar.name, bar.x, bar.y = "actions", 12, job.height - job.footerHeight + scaled(4)
            nodes(job, {
                {type = "hline", x = 12, y = job.height - job.footerHeight, w = job.width, h = 1},
                bar,
                {type = "label", name = "status", x = 12, y = job.height - scaled(26),
                 w = job.width, h = scaled(22), font = SMLSIZE, text = app.status},
            }, job.page, "finish")
        elseif view.setupOpen then
            nodes(job, {row({
                button("Save", app.save, function() return app.dirty and not app.saveJob end),
                {type = "label", w = width - 90, text = app.status},
            }, width)}, job.content, "finish")
        else nodes(job, {{type = "label", w = width, text = app.status}}, job.content, "finish") end
    elseif job.phase == "nodes" then stepNodes(view, job)
    elseif job.phase == "finish" then
        view.uiReady, view.buildJob = true, nil
    end
    if job.failed then view.buildJob = nil end
end

function M.refresh(view)
    local full = lvgl.isFullScreen() or lvgl.isAppMode()
    if view.full and not full then
        release(view)
        view.page, view.setupOpen = "control", false
    end
    if view.full ~= full or view.renderRevision ~= app.revision or view.renderPhase ~= app.phase then
        beginBuild(view, full)
    end
    if view.buildJob then
        local job = view.buildJob
        job.batchObjects, job.pause = 0, false
        for _ = 1, 16 do
            if view.buildJob ~= job or job.batchObjects >= 4 or job.pause then break end
            stepBuild(view)
        end
        return
    end
    if view.uiReady and full and view.page == "control" and app.data then
        local list = app.visibleControls[view.tab]
        for _ = 1, math.min(8, #list) do
            if view.pollIndex > #list then view.pollIndex = 1 end
            local control = list[view.pollIndex]
            local value, ref = app.values[control.id] ~= 0, view.refs["c" .. control.id]
            if ref and control.type == 1 and view.checked[control.id] ~= value then
                ref:set({checked = value})
                view.checked[control.id] = value
            end
            view.pollIndex = view.pollIndex + 1
        end
    end
end

return M
