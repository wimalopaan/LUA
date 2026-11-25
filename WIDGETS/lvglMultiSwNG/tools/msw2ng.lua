-- TNS|MultiSw -> NG|TNE
-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 PiperPilot (github.com/mnorden81)
--
-- lvglMultiSw -> lvglMultiSwNG configuration converter, EdgeTX tool script.
-- https://github.com/mnorden81/lvglmultisw-to-ng
--
-- * Lists all old lvglMultiSw configurations on the SD card and the model each one belongs to.
-- * The user checks the configurations to convert and can change, per configuration, the target
--   model and tab address, and per target model the NG settings (protocol, interval, destination,
--   S.Port IDs). Defaults come from the old widget options stored in the model file.
-- * All checked configurations of one model become tabs of that model's single NG configuration,
--   written to the place the installed NG version expects. An existing NG configuration is only
--   replaced after confirmation, in the other of NG's two slots with a higher generation, so the
--   previous one stays on the card as fallback.
-- * Old files are parsed, never run as code: only literal tables pass the check before they are
--   loaded with an empty environment. Old files and model files are never modified.
-- * All work is done in small steps per frame, to stay within EdgeTX's per-call CPU limit.
--
-- Same conversion rules as the browser tool (src/core.js).

local OLD_DIR = "/WIDGETS/lvglMultiSw"
local NG_DIR = "/WIDGETS/lvglMultiSwNG"
local OLD_WIDGET = "MultiSwE/L"
local NG_WIDGET = "MultiSw NG"
local OPTION_DEFS = {
    {"CRSF", 1}, {"Address", 0}, {"Intervall", 100}, {"ShmEncoding", 0}, {"ShmVarStart", 1},
    {"ShmSync", 0}, {"SPort", 0}, {"SPortPhy", 0}, {"SPortApp", 0x51}, {"SPortProto", 1},
}
local PROTOCOLS = {[0] = "CRSF", "S.Port WM", "S.Port ACW 1.5", "S.Port ACW 1.4"}
local MAX_OLD_FILE = 96 * 1024

----------------------------------------------------------------- helpers ---
local LIST = setmetatable({}, {__mode = "k"}) -- tables that were pure lists in the old file

local function isList(v) return type(v) == "table" and LIST[v] == true end

local function trunc(v)
    local r = v >= 0 and math.floor(v) or math.ceil(v)
    return math.tointeger and math.tointeger(r) or r
end

local function int(v, def)
    if type(v) == "boolean" then return v and 1 or 0 end
    if type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge then return trunc(v) end
    return def
end

local function clamp(v, lo, hi)
    if v < lo then return lo elseif v > hi then return hi end
    return v
end

local function isInt(v) return type(v) == "number" and v == v and v % 1 == 0 end

local function fmtNum(v)
    if math.type and math.type(v) == "integer" then return string.format("%d", v) end
    return string.format("%.0f", v)
end

local function str(v)
    if type(v) == "string" then return v end
    if v == nil then return "" end
    if type(v) == "number" and isInt(v) then return fmtNum(v) end
    return tostring(v)
end

local function cutBytes(s, max)
    if #s <= max then return s end
    local n = max
    -- do not split a UTF-8 sequence: back off while the byte after the cut is a continuation byte
    while n > 0 and (string.byte(s, n + 1) or 0) >= 0x80 and (string.byte(s, n + 1) or 0) < 0xC0 do n = n - 1 end
    return string.sub(s, 1, n)
end

local function cleanString(v, max, fallback)
    local s = str(v)
    s = string.gsub(s, "[%z\1-\31\127]", " ")
    s = cutBytes(s, max)
    if s == "" and fallback ~= nil then return fallback end
    return s
end

local function toHex(s)
    return (string.gsub(s, ".", function(c) return string.format("%02x", string.byte(c)) end))
end

local function truthy(v) return v ~= nil and v ~= false and v ~= 0 and v ~= "" end

----------------------------------------------------- old config (tableser) ---
-- The old widget stores `return { {table1}, {table2}, ... }` where a value {n} refers to table n.
-- Check: with string contents and comments removed, only literal table syntax may remain (no
-- names, calls, operators or long brackets). Then the file can only build tables, so it is loaded
-- with an empty environment; compiling happens in C, which keeps the CPU cost per frame low.
local function literalOnly(text)
    local s = string.gsub(text, "\\.", "")          -- escapes (strings only in a valid file)
    s = string.gsub(s, '"[^"]*"', '""')
    if string.find(s, "'", 1, true) then return nil, "unexpected quote" end
    if string.find(s, "%[=*%[") or string.find(s, "%-%-%[=*%[") then return nil, "long brackets are not allowed" end
    s = string.gsub(s, "%-%-[^\n]*", "")
    if not string.find(s, "^%s*return%s*{") then return nil, "not a configuration file (no 'return')" end
    s = string.gsub(s, "^%s*return", "")
    s = string.gsub(s, "%f[%w_]true%f[^%w_]", "")
    s = string.gsub(s, "%f[%w_]false%f[^%w_]", "")
    s = string.gsub(s, "%f[%w_]nil%f[^%w_]", "")
    local bad = string.find(s, "[^%s%d{}%[%]=,;%.%-%+xXa-fA-F\"]")
    if bad then return nil, "unexpected character '" .. string.sub(s, bad, bad) .. "'" end
    if string.find(s, "%a[%a_]*%s*%(") then return nil, "calls are not allowed" end
    return true
end

-- Returns a job; step it with parseOldStep until job.done. Then job.result or job.error.
local function parseOldBegin(text)
    local job = {done = false}
    if not string.find(text, "%S") then job.done, job.error = true, "empty"; return job end
    local ok, err = literalOnly(text)
    if not ok then job.done, job.error = true, err; return job end
    local chunk, cerr = load(text, "=old configuration", "t", {})
    if not chunk then
        job.done = true
        job.error = (string.find(tostring(cerr), "<eof>", 1, true) or string.find(tostring(cerr), "unfinished", 1, true)) and "truncated" or ("syntax: " .. tostring(cerr))
        return job
    end
    local okRun, tables = pcall(chunk)
    if not okRun then job.done, job.error = true, tostring(tables); return job end
    if type(tables) ~= "table" or type(tables[1]) ~= "table" then job.done, job.error = true, "no tables"; return job end
    job.tables, job.index, job.key = tables, 1, nil
    job.count, job.max, job.nonInt = 0, 0, false
    return job
end

local function isRef(v)
    return type(v) == "table" and type(v[1]) == "number" and next(v, next(v)) == nil
end

-- Resolves {n} references in place, about `budget` table entries per call.
local function parseOldStep(job, budget)
    if job.done then return end
    local tables = job.tables
    while budget > 0 do
        local t = tables[job.index]
        if t == nil then
            local top = tables[1]
            job.done = true
            if isList(top) then job.error = "unexpected top-level layout" else job.result = top end
            job.tables = nil
            return
        end
        if type(t) ~= "table" then job.done, job.error = true, "invalid table " .. job.index; return end
        local k, v = next(t, job.key)
        if k == nil then
            if not job.nonInt and job.count == job.max then LIST[t] = true end
            job.index, job.key, job.count, job.max, job.nonInt = job.index + 1, nil, 0, 0, false
        else
            job.key = k
            job.count = job.count + 1
            if isInt(k) and k >= 1 then
                if k > job.max then job.max = k end
            else
                job.nonInt = true
            end
            if type(v) == "table" then
                if not isRef(v) then job.done, job.error = true, "invalid value reference in table " .. job.index; return end
                local target = v[1]
                if not isInt(target) or tables[target] == nil then job.done, job.error = true, "reference out of range"; return end
                t[k] = tables[trunc(target)]
            end
        end
        budget = budget - 1
    end
end

local function parseOldConfig(text)
    local job = parseOldBegin(text)
    while not job.done do parseOldStep(job, 100000) end
    return job.result, job.error
end

---------------------------------------------------------- model YAML ---
local function unquote(v)
    v = string.match(v, "^%s*(.-)%s*$")
    local q = string.sub(v, 1, 1)
    if (q == '"' or q == "'") and #v >= 2 and string.sub(v, -1) == q then
        local body = string.sub(v, 2, -2)
        if q == "'" then return (string.gsub(body, "''", "'")) end
        if not string.find(body, "\\", 1, true) then return body end
        local parts, i = {}, 1
        while i <= #body do
            local c = string.sub(body, i, i)
            if c == "\\" and i < #body then
                local hex = string.match(body, "^x(%x%x)", i + 1)
                if hex then
                    parts[#parts + 1], i = string.char(tonumber(hex, 16)), i + 4
                else
                    parts[#parts + 1], i = string.sub(body, i + 1, i + 1), i + 2
                end
            else
                parts[#parts + 1], i = c, i + 1
            end
        end
        return table.concat(parts)
    end
    return (string.gsub(v, "%s+#.*$", ""))
end

-- EdgeTX model files use nested "key: value" maps with numeric keys. Only "header" and
-- "screenData" are kept; other top-level sections are skipped with one string search.
local KEEP = {header = true, screenData = true}

local function yamlBegin(text)
    local root = {}
    return {text = text, pos = 1, root = root, stack = {{indent = -1, obj = root}}, done = false}
end

local function yamlStep(job, lines)
    local text, stack, root = job.text, job.stack, job.root
    while lines > 0 do
        if job.pos > #text then job.done, job.text = true, nil; return end
        local nl = string.find(text, "\n", job.pos, true)
        local raw = string.sub(text, job.pos, (nl or #text + 1) - 1)
        job.pos = (nl or #text) + 1
        lines = lines - 1
        raw = string.gsub(raw, "\r$", "")
        if string.find(raw, "%S") and not string.find(raw, "^%s*#") and not string.find(raw, "^%s*%-%s") then
            local spaces, rest = string.match(raw, "^( *)(.*)$")
            -- key = text up to the first ':' that is followed by whitespace or the end of the line
            local key, value
            local from = 2
            while true do
                local c = string.find(rest, ":", from, true)
                if not c then break end
                local after = string.sub(rest, c + 1)
                if after == "" or string.find(after, "^%s") then
                    key = string.sub(rest, 1, c - 1)
                    value = string.match(after, "^%s*(.-)%s*$")
                    break
                end
                from = c + 1
            end
            if key then
                local indent = #spaces
                while #stack > 1 and stack[#stack].indent >= indent do table.remove(stack) end
                local parent = stack[#stack].obj
                key = string.match(key, "^%s*(.-)%s*$")
                key = string.gsub(string.gsub(key, "^[\"']", ""), "[\"']$", "")
                if value == "" then
                    if parent == root and not KEEP[key] then
                        -- skip the whole section up to the next top-level line
                        local nextTop = string.find(text, "\n[^%s#]", job.pos - 1)
                        job.pos = nextTop and (nextTop + 1) or (#text + 1)
                    else
                        local child = {}
                        parent[key] = child
                        stack[#stack + 1] = {indent = indent, obj = child}
                    end
                elseif parent ~= root then
                    parent[key] = unquote(value)
                end
            end
        end
    end
end

local function parseYaml(text)
    local job = yamlBegin(text)
    while not job.done do yamlStep(job, 100000) end
    return job.root
end

local function sortedKeys(obj)
    local keys = {}
    for k in pairs(obj or {}) do
        if type(k) == "string" and string.find(k, "^%d+$") then keys[#keys + 1] = k end
    end
    table.sort(keys, function(a, b) return tonumber(a) < tonumber(b) end)
    return keys
end

local function optionValue(entry)
    if type(entry) ~= "table" then return nil end
    local v = type(entry.value) == "table" and entry.value or {}
    for _, k in ipairs({"boolValue", "signedValue", "unsignedValue"}) do
        if v[k] ~= nil then return tonumber(v[k]) end
    end
    return nil
end

local function defaultOptions()
    local o = {}
    for _, def in ipairs(OPTION_DEFS) do o[def[1]] = def[2] end
    return o
end

local function findWidgets(yaml)
    local found = {}
    local screens = yaml.screenData or {}
    for _, s in ipairs(sortedKeys(screens)) do
        local layout = type(screens[s]) == "table" and screens[s].layoutData or nil
        local zones = type(layout) == "table" and type(layout.zones) == "table" and layout.zones or {}
        for _, z in ipairs(sortedKeys(zones)) do
            local zone = type(zones[z]) == "table" and zones[z] or {}
            local name = zone.widgetName
            if name == OLD_WIDGET or name == NG_WIDGET then
                local entry = {kind = name == OLD_WIDGET and "old" or "ng", screen = tonumber(s) + 1, zone = tonumber(z) + 1}
                if entry.kind == "old" then
                    local data = type(zone.widgetData) == "table" and zone.widgetData or {}
                    local opts = type(data.options) == "table" and data.options or {}
                    entry.options = {}
                    for i, def in ipairs(OPTION_DEFS) do
                        local v = optionValue(opts[tostring(i - 1)])
                        if v == nil then v = def[2] end
                        entry.options[def[1]] = v
                    end
                end
                found[#found + 1] = entry
            end
        end
    end
    return found
end

local function modelNameOf(yaml)
    return type(yaml.header) == "table" and type(yaml.header.name) == "string" and yaml.header.name or ""
end

------------------------------------------------------------ NG schema ---
local SCHEMAS = {
    config = {
        version = {1, 1}, generation = {0, 2147483647}, name = 32,
        destination = {0, 255}, interval = {5, 1000}, sendColors = {0, 1}, autoSave = {0, 1},
        buttonSpacing = {-1, 40}, protocol = {0, 3}, sportPhysicalId = {0, 0x1b}, sportAppId = {0, 255},
    },
    tab = {id = {1, 2147483647}, name = 32, address = {0, 255}, columns = {1, 4}, height = {0, 240}},
    control = {
        id = {1, 2147483647}, tab = {1, 2147483647}, name = 32, leftText = 32, rightText = 32,
        type = {1, 5}, address = {-1, 255}, output = {1, 8},
        color = {-2147483648, 4294967295}, textColor = {-2147483648, 4294967295}, font = {0, 65535},
        visible = {0, 1}, switch = {-2147483648, 2147483647}, switch2 = {-2147483648, 2147483647},
        source = {-2147483648, 2147483647}, activation = {-2147483648, 2147483647}, group = {0, 255},
        image = 128, sportType = {0, 255}, sportOptions = {0, 255}, sportPwmOn = {0, 255},
    },
}

-- Fields of newer NG versions; written only when the installed NG knows them.
local OPTIONAL = {config = {virtualSwitches = 64}, control = {localSwitch = {0, 128}}}

local function validateRecord(rec)
    local schema = SCHEMAS[rec.kind]
    if not schema then return "unknown record" end
    local optional = OPTIONAL[rec.kind] or {}
    for k, rule in pairs(optional) do
        local v = rec[k]
        if v ~= nil then
            if type(rule) == "number" then
                if type(v) ~= "string" or #v ~= rule or string.find(v, "[^01]") then return "invalid " .. rec.kind .. "." .. k end
            elseif not (isInt(v) and v >= rule[1] and v <= rule[2]) then
                return "invalid " .. rec.kind .. "." .. k
            end
        end
    end
    for k, rule in pairs(schema) do
        local v = rec[k]
        if type(rule) == "number" then
            if type(v) ~= "string" or #v > rule or string.find(v, "[%z\1-\31]") then return "invalid " .. rec.kind .. "." .. k end
        elseif not (isInt(v) and v >= rule[1] and v <= rule[2]) then
            return "invalid " .. rec.kind .. "." .. k
        end
    end
    for k in pairs(rec) do
        if k ~= "kind" and schema[k] == nil and optional[k] == nil then return "unknown property " .. k end
    end
    return nil
end

------------------------------------------------------------- convert ---
local function protoOf(o)
    if truthy(o.CRSF) then return 0 end
    if truthy(o.SPort) then return clamp(int(o.SPortProto, 1), 1, 3) end
    return 0
end

-- Header values the conversion would choose for these instances (shown as defaults in the UI).
local function headerDefaults(first)
    local o = first.options
    return {
        protocol = protoOf(o),
        interval = clamp(int(o.Intervall, 100), 5, 1000),
        destination = clamp(int(first.destination, 0), 0, 255),
        sportPhysicalId = clamp(int(o.SPortPhy, 0), 0, 0x1b),
        sportAppId = clamp(int(o.SPortApp, 0x51), 0, 255),
    }
end

-- instances: list of {address, options, settings, tabName, label} in tab order.
-- opts: {lang = "de"|"en", header = optional table of header values chosen by the user}
local function convertBegin(instances, opts)
    opts = opts or {}
    local job = {warnings = {}, skipped = {}, stats = {controls = 0, skipped = 0}, done = false}
    local function warn(level, text) job.warnings[#job.warnings + 1] = {level = level, text = text} end
    job.warn = warn
    if #instances == 0 then job.done, job.error = true, "no widgets selected"; return job end
    job.leftText = opts.lang == "de" and "Links" or "Left"
    job.rightText = opts.lang == "de" and "Rechts" or "Right"

    local first = instances[1]
    local o0 = first.options
    local override = opts.header
    local protocol = protoOf(o0)
    if override then
        protocol = override.protocol
    else
        if not truthy(o0.CRSF) and not truthy(o0.SPort) then
            warn("warn", "CRSF and S.Port were both switched off in the old widget options, so it sent nothing itself (maybe SHM/mixer script or a plain UI). NG always sends; CRSF was chosen. Check the transport before use.")
        end
        if truthy(o0.CRSF) and truthy(o0.SPort) then
            warn("warn", "The old widget sent CRSF and S.Port at the same time; NG supports one protocol per model, CRSF was chosen.")
        end
        for i = 2, #instances do
            local inst, o = instances[i], instances[i].options
            if protoOf(o) ~= protocol or (protocol > 0 and (o.SPortPhy ~= o0.SPortPhy or o.SPortApp ~= o0.SPortApp)) then
                warn("warn", inst.label .. ": other transport settings than the first widget; NG uses one protocol per model, the first widget's settings were kept.")
            end
            if o.Intervall ~= o0.Intervall then
                warn("info", inst.label .. ": different send interval; the first widget's interval was kept.")
            end
        end
    end
    local settings0 = first.settings or {}
    local destination = clamp(int(settings0.commandBroadcastAddress, 0), 0, 255)
    if not override then
        for i = 2, #instances do
            local st = instances[i].settings or {}
            if clamp(int(st.commandBroadcastAddress, 0), 0, 255) ~= destination then
                warn("warn", instances[i].label .. ": different CRSF destination; the first widget's value was kept.")
            end
        end
    end
    local anyColors, allColors = false, true
    for _, inst in ipairs(instances) do
        local c = int((inst.settings or {}).activate_color_proto, 0)
        if c > 0 then anyColors = true end
        if c == 0 then allColors = false end
    end
    if anyColors and not allColors then
        warn("info", "LED colors were enabled in only some widgets; NG has one setting for the whole model (enabled).")
    end
    local header = {
        kind = "config", version = 1, generation = 0, name = "MultiSwitch NG",
        destination = destination, interval = clamp(int(o0.Intervall, 100), 5, 1000),
        sendColors = anyColors and 1 or 0, autoSave = 1, buttonSpacing = -1, protocol = protocol,
        sportPhysicalId = clamp(int(o0.SPortPhy, 0), 0, 0x1b),
        sportAppId = clamp(int(o0.SPortApp, 0x51), 0, 255),
    }
    if override then
        for k, v in pairs(override) do header[k] = v end
    end
    job.protocol = header.protocol
    job.mapSwitch, job.usedLocal = opts.mapSwitch, {}
    job.config = {header = header, tabs = {}, controls = {}}
    job.instances, job.ti, job.bi = instances, 0, 0
    job.usedEndpoints, job.nameCount, job.controlId = {}, {}, 0
    local e = validateRecord(header)
    if e then job.done, job.error = true, "invalid settings: " .. e end
    return job
end

local function names3(a)
    local out = {}
    for i = 1, math.min(3, #a) do out[i] = a[i] end
    return table.concat(out, ", ") .. (#a > 3 and ", ..." or "")
end

local function startTab(job)
    local ti = job.ti
    local inst = job.instances[ti]
    local st = inst.settings or {}
    local address = clamp(int(inst.address, 0), 0, 255)
    local name = cleanString(inst.tabName, 32, cleanString(st.name, 32, "Tab " .. ti))
    job.nameCount[name] = (job.nameCount[name] or 0) + 1
    if job.nameCount[name] > 1 then name = cutBytes(name, 28) .. " " .. fmtNum(address) end
    local columns = int(st.columns, 2)
    if columns < 1 or columns > 4 then
        job.warn("warn", inst.label .. ": " .. fmtNum(columns) .. " columns are not possible in NG (1..4); " .. fmtNum(clamp(columns, 1, 4)) .. " used.")
        columns = clamp(columns, 1, 4)
    end
    job.tab = {kind = "tab", id = ti, name = name, address = address, columns = columns, height = 0}
    job.config.tabs[#job.config.tabs + 1] = job.tab
    job.buttons = isList(st.buttons) and st.buttons or {}
    local count = isList(st.buttons) and #st.buttons or 0
    if isList(st.buttons) then for k in pairs(st.buttons) do if type(k) == "number" and k > count then count = k end end end
    job.count, job.bi = count, 0
    job.extSwitch, job.virtInput, job.mapped = {}, {}, {}
    if count == 0 then job.warn("warn", inst.label .. ": the old configuration contains no buttons.") end
end

local function finishTab(job)
    local inst = job.instances[job.ti]
    local st = inst.settings or {}
    local warn = job.warn
    if #job.mapped > 0 then
        warn("info", inst.label .. ": " .. #job.mapped .. " button(s) set an EdgeTX switch ('external_switch'); now assigned to NG 'Set switch' (" .. names3(job.mapped) .. "). Logical switches L01..L64 must be Sticky in the model, as with the old widget.")
    end
    if #job.extSwitch > 0 then
        warn("warn", inst.label .. ": " .. #job.extSwitch .. " button(s) set an EdgeTX logical/virtual switch ('external_switch': " .. names3(job.extSwitch) .. "), which was not assigned automatically. Newer NG versions can do this ('Set switch' in the control editor); assign it there, otherwise mixes or sounds that depend on those switches will no longer be triggered.")
    end
    if #job.virtInput > 0 then
        warn("warn", inst.label .. ": " .. #job.virtInput .. " button(s) set a virtual input (" .. names3(job.virtInput) .. "). NG does not support this yet.")
    end
    local tele = 0
    if isList(st.telemActions) then
        for _, a in pairs(st.telemActions) do
            if type(a) == "table" and int(a.switch, 0) ~= 0 then tele = tele + 1 end
        end
    end
    if tele > 0 then warn("warn", inst.label .. ": " .. tele .. " telemetry action(s) are configured; NG does not support them yet (dropped).") end
    if int(st.activate_vswitches, 0) > 0 then warn("warn", inst.label .. ": virtual switches were activated; NG does not support them yet (dropped).") end
    if inst.options and truthy(inst.options.ShmEncoding) then warn("warn", inst.label .. ": SHM encoding was enabled; NG does not support it yet (dropped).") end
    if int(st.statusPassthru, 0) > 0 then warn("info", inst.label .. ": status passthrough is not supported by NG (dropped).") end
    job.tab = nil
end

local function convertButton(job, bi)
    local inst, tab, protocol = job.instances[job.ti], job.tab, job.protocol
    local address = tab.address
    local b = job.buttons[bi]
    local label = inst.label .. " / " .. ((type(b) == "table" and b.name ~= nil) and str(b.name) or ("Output " .. bi))
    local function skip(reason)
        job.skipped[#job.skipped + 1] = {label = label, reason = reason}
        job.stats.skipped = job.stats.skipped + 1
    end
    if type(b) ~= "table" then
        job.skipped[#job.skipped + 1] = {label = label, reason = "invalid button record"}
        return
    end
    local typ = int(b.type, 1)
    local output = int(b.output, ((bi - 1) % 8) + 1)
    local bAddr = int(b.address, int(inst.oldAddress, address))
    local endpoint = bAddr * 8 + output
    if typ < 1 or typ > 5 then return skip("unknown control type " .. fmtNum(typ)) end
    if protocol == 1 and typ == 5 then return skip("sliders are not supported by S.Port WM") end
    if protocol >= 2 and (typ == 3 or typ == 5) then return skip("3Pos controls and sliders are not supported by S.Port ACW") end
    if output < 1 or output > 8 then return skip("output " .. fmtNum(output) .. " is outside 1..8") end
    if bAddr < 0 or bAddr > 255 then return skip("address " .. fmtNum(bAddr) .. " is outside 0..255") end
    if protocol >= 2 and endpoint > 255 then return skip("ACW switch number " .. fmtNum(endpoint) .. " exceeds 255") end
    if job.usedEndpoints[endpoint] then
        return skip("address/output " .. fmtNum(bAddr) .. "/" .. fmtNum(output) .. " is already used by " .. job.usedEndpoints[endpoint])
    end
    job.usedEndpoints[endpoint] = label
    local sp = type(b.sport) == "table" and b.sport or {}
    job.controlId = job.controlId + 1
    local rec = {
        kind = "control", id = job.controlId, tab = tab.id,
        name = cleanString(b.name, 32, "Output " .. fmtNum(output)),
        leftText = job.leftText, rightText = job.rightText, type = typ,
        address = bAddr == address and -1 or bAddr, output = output,
        color = int(b.color, 327680), textColor = int(b.textColor, 131072),
        font = clamp(int(b.font, 0), 0, 65535),
        visible = int(b.visible, 1) ~= 0 and 1 or 0,
        switch = int(b.switch, 0), switch2 = int(b.switch2, 0), source = int(b.source, 0),
        activation = int(b.activation_switch, 0), group = clamp(int(b.exclusive_group, 0), 0, 255),
        image = cleanString(b.image, 128, ""),
        sportType = clamp(int(sp.type, 1), 0, 255), sportOptions = clamp(int(sp.options, 0), 0, 255),
        sportPwmOn = clamp(int(sp.pwm_on, 255), 0, 255),
    }
    local ext = int(b.external_switch, 0)
    if ext ~= 0 then
        local target, reason
        if ext < 0 then reason = "inverted switch"
        elseif job.mapSwitch then target, reason = job.mapSwitch(ext)
        else reason = nil end
        if target and typ == 5 then target, reason = nil, "sliders cannot set a switch in NG" end
        if target and (math.abs(rec.switch) == ext or math.abs(rec.activation) == ext or (typ == 3 and math.abs(rec.switch2) == ext)) then
            target, reason = nil, "the switch is also this button's input"
        end
        if target and job.usedLocal[target] then target, reason = nil, "already set by " .. job.usedLocal[target] end
        if target then
            rec.localSwitch = target
            job.usedLocal[target] = rec.name
            local label2 = string.format(target > 64 and "VS%02d" or "L%02d", (target - 1) % 64 + 1)
            job.mapped[#job.mapped + 1] = rec.name .. " -> " .. label2
            if target > 64 then
                local h = job.config.header
                local bits = h.virtualSwitches or string.rep("0", 64)
                h.virtualSwitches = string.sub(bits, 1, target - 65) .. "1" .. string.sub(bits, target - 63)
            end
        else
            job.extSwitch[#job.extSwitch + 1] = rec.name .. (reason and (" - " .. reason) or "")
        end
    end
    local e = validateRecord(rec)
    if e then return skip("cannot be represented in NG (" .. e .. ")") end
    if type(b.name) == "string" and rec.name ~= b.name then
        job.warn("info", label .. ": name was shortened or cleaned to fit NG limits.")
    end
    if int(b.setVirtualInput, 0) > 0 then job.virtInput[#job.virtInput + 1] = rec.name end
    job.config.controls[#job.config.controls + 1] = rec
    job.stats.controls = job.stats.controls + 1
end

-- Converts about `budget` buttons per call.
local function convertStep(job, budget)
    while not job.done and budget > 0 do
        if job.tab == nil then
            job.ti = job.ti + 1
            if job.ti > #job.instances then
                job.done = true
                for _, t in ipairs(job.config.tabs) do
                    local e = validateRecord(t)
                    if e then job.error = "internal: generated record invalid: " .. e end
                end
                job.result = {config = job.config, warnings = job.warnings, skipped = job.skipped, stats = job.stats}
                return
            end
            startTab(job)
        elseif job.bi < job.count then
            job.bi = job.bi + 1
            convertButton(job, job.bi)
            budget = budget - 1
        else
            finishTab(job)
        end
    end
end

local function convert(instances, opts)
    local job = convertBegin(instances, opts)
    while not job.done do convertStep(job, 100000) end
    if job.error then return nil, job.error end
    return job.result
end

-------------------------------------------------------------- output ---
local function luaQuote(s)
    if not string.find(s, '[%c"\\\127]') then return '"' .. s .. '"' end
    local out = {'"'}
    for i = 1, #s do
        local c = string.sub(s, i, i)
        local b = string.byte(c)
        if c == '"' then out[#out + 1] = '\\"'
        elseif c == "\\" then out[#out + 1] = "\\\\"
        elseif c == "\n" then out[#out + 1] = "\\n"
        elseif c == "\r" then out[#out + 1] = "\\r"
        elseif b == 0 then out[#out + 1] = "\\0"
        elseif b < 32 or b == 127 then out[#out + 1] = "\\" .. b
        else out[#out + 1] = c end
    end
    out[#out + 1] = '"'
    return table.concat(out)
end

-- Same layout as NG storage.lua: one line per record, fields sorted.
local function serializeRecord(rec)
    local fields = {}
    for k, v in pairs(rec) do
        fields[#fields + 1] = k .. "=" .. (type(v) == "string" and luaQuote(v) or fmtNum(v))
    end
    table.sort(fields)
    return "{" .. table.concat(fields, ",") .. "},\n"
end

local function ngRecords(config, generation)
    local header = {}
    for k, v in pairs(config.header) do header[k] = v end
    header.generation = generation
    local recs = {header}
    for _, t in ipairs(config.tabs) do recs[#recs + 1] = t end
    for _, c in ipairs(config.controls) do recs[#recs + 1] = c end
    return recs
end

local function ngFileText(config, generation)
    local parts = {"return {\n"}
    for _, r in ipairs(ngRecords(config, generation)) do parts[#parts + 1] = serializeRecord(r) end
    parts[#parts + 1] = "}\n"
    return table.concat(parts)
end

local function planWrite(textA, textB)
    local function gen(t)
        if t == nil then return -1 end
        return tonumber(string.match(string.sub(t, 1, 600), "generation=(%d+)") or "0")
    end
    local ga, gb = gen(textA), gen(textB)
    if ga < 0 and gb < 0 then return {slot = "a", generation = 1, replaces = false} end
    local max = math.max(ga, gb)
    return {slot = ga >= gb and "b" or "a", generation = max + 1, replaces = true, previous = max}
end

local Core = {
    parseOldConfig = parseOldConfig, parseYaml = parseYaml, findWidgets = findWidgets,
    modelNameOf = modelNameOf, convert = convert, ngFileText = ngFileText, planWrite = planWrite,
    toHex = toHex, validateRecord = validateRecord, isList = isList, literalOnly = literalOnly,
}

------------------------------------------------------------- file I/O ---
local function readFile(path, max)
    local f = io.open(path, "r")
    if not f then return nil, "missing" end
    local parts, size = {}, 0
    while true do
        local data = io.read(f, 4096)
        if not data or #data == 0 then break end
        size = size + #data
        if max and size > max then io.close(f); return nil, "file too large" end
        parts[#parts + 1] = data
    end
    io.close(f)
    return table.concat(parts)
end

local function readHead(path, n)
    local f = io.open(path, "r")
    if not f then return nil end
    local d = io.read(f, n) or ""
    io.close(f)
    return d
end

local function listDir(path)
    if type(dir) ~= "function" then return nil end
    local ok, iter = pcall(dir, path)
    if not ok or not iter then return nil end
    local names = {}
    for name in iter do names[#names + 1] = name end
    return names
end

local function isDirectory(path)
    if type(fstat) ~= "function" then return listDir(path) ~= nil end
    local info = fstat(path)
    return info ~= nil and type(info.attrib) == "number" and (info.attrib // 16) % 2 == 1
end

local function ensureDirectory(path)
    if isDirectory(path) then return true end
    if type(mkdir) ~= "function" then return nil, "cannot create " .. path .. " (no mkdir API)" end
    local result = mkdir(path)
    if result ~= 0 and result ~= 8 then return nil, "cannot create " .. path .. ": " .. tostring(result) end
    return true
end

-------------------------------------------------------------------- texts ---
local TEXT = {
    en = {
        title = "MultiSw -> NG converter",
        scanning = "Reading the SD card ...", scanOld = "Old configurations: %d of %d", scanModels = "Models: %d of %d",
        list = "Old configurations (check = convert)",
        selectAll = "Check all assigned", selectNone = "Uncheck all",
        convert = "Convert checked: %d file(s) -> %d model(s)",
        help = "ENTER: check   ENTER long / PAGE / tap >: settings   EXIT: quit",
        unassigned = "-> ? (no model)", unusable = "unusable", buttons = "btn",
        detail = "Settings: %s",
        include = "Convert", yes = "yes", no = "no",
        target = "Target model", none = "(none)", tabAddress = "NG tab address", oldAddress = "Old address",
        source = "Source", fromModel = "widget options of the model", fromDefaults = "defaults (widget not on the model)",
        forModel = "For all tabs of %s:", protocol = "Protocol", interval = "Interval (ms)",
        destination = "CRSF destination", sportPhy = "S.Port physical ID", sportApp = "S.Port app ID",
        detailHelp = "ENTER: change   rotary: value   EXIT: back",
        confirm = "These models already have an NG configuration:",
        confirm2 = "Replace? The previous one stays on the card in the other slot",
        confirm3 = "as fallback until NG saves again.",
        confirm4 = "ENTER: replace   EXIT: back",
        writing = "Converting %s ...", checking = "checking",
        done = "saved", failed = "FAILED", controls = "controls", tabs = "tabs", skippedN = "not taken",
        check_ok = "NG check OK", check_na = "NG check n/a", check_fail = "NG check FAILED",
        next1 = "Now place the widget 'MultiSw NG' instead of 'MultiSwE/L' in these models.",
        next2 = "If an NG widget is already on the loaded model, reload the model.",
        report = "Report (rotary scrolls):", nothing = "No configuration checked.",
        noTarget = "Choose a target model first.",
        nong = "lvglMultiSwNG is not installed (" .. NG_DIR .. ").",
        noold = "No old lvglMultiSw configuration found (" .. OLD_DIR .. ").",
        exit = "EXIT: quit",
    },
    de = {
        title = "MultiSw -> NG Konverter",
        scanning = "Lese die SD-Karte ...", scanOld = "Alte Konfigurationen: %d von %d", scanModels = "Modelle: %d von %d",
        list = "Alte Konfigurationen (Haken = umwandeln)",
        selectAll = "Alle zugeordneten anhaken", selectNone = "Alle Haken entfernen",
        convert = "Angehakte umwandeln: %d Datei(en) -> %d Modell(e)",
        help = "ENTER: Haken   ENTER lang / PAGE / > tippen: Einstellungen   EXIT: Ende",
        unassigned = "-> ? (kein Modell)", unusable = "unbrauchbar", buttons = "Btn",
        detail = "Einstellungen: %s",
        include = "Umwandeln", yes = "ja", no = "nein",
        target = "Ziel-Modell", none = "(keins)", tabAddress = "NG-Tab-Adresse", oldAddress = "Alte Adresse",
        source = "Quelle", fromModel = "Widget-Optionen des Modells", fromDefaults = "Standardwerte (Widget nicht im Modell)",
        forModel = "Fuer alle Tabs von %s:", protocol = "Protokoll", interval = "Intervall (ms)",
        destination = "CRSF-Ziel (destination)", sportPhy = "S.Port Physical ID", sportApp = "S.Port App ID",
        detailHelp = "ENTER: aendern   Drehen: Wert   EXIT: zurueck",
        confirm = "Diese Modelle haben schon eine NG-Konfiguration:",
        confirm2 = "Ersetzen? Die bisherige bleibt im anderen Slot auf der Karte,",
        confirm3 = "bis NG das naechste Mal speichert.",
        confirm4 = "ENTER: ersetzen   EXIT: zurueck",
        writing = "Wandle %s um ...", checking = "pruefe",
        done = "gespeichert", failed = "FEHLER", controls = "Controls", tabs = "Tabs", skippedN = "nicht uebernommen",
        check_ok = "NG-Pruefung OK", check_na = "NG-Pruefung n/v", check_fail = "NG-Pruefung FEHLER",
        next1 = "Jetzt in diesen Modellen das Widget 'MultiSw NG' statt 'MultiSwE/L' platzieren.",
        next2 = "Ist im geladenen Modell schon ein NG-Widget, das Modell neu laden.",
        report = "Bericht (Drehen scrollt):", nothing = "Keine Konfiguration angehakt.",
        noTarget = "Zuerst ein Ziel-Modell waehlen.",
        nong = "lvglMultiSwNG ist nicht installiert (" .. NG_DIR .. ").",
        noold = "Keine alte lvglMultiSw-Konfiguration gefunden (" .. OLD_DIR .. ").",
        exit = "EXIT: Ende",
    },
}

local S -- tool state
local L -- current texts

local function language()
    local ok, gs = pcall(function() return getGeneralSettings and getGeneralSettings() end)
    local l = ok and type(gs) == "table" and gs.language or ""
    return string.sub(string.lower(tostring(l)), 1, 2) == "de" and "de" or "en"
end

-------------------------------------------------------------- scanning ---
-- Old buttons stored an EdgeTX switch index (external_switch); newer NG versions take the
-- local switch number: 1..64 = L01..L64, 65..128 = VS01..VS64.
local function mapSwitch(index)
    if type(getSwitchName) ~= "function" then return nil, "switch names unavailable" end
    local ok, name = pcall(getSwitchName, index)
    if not ok or type(name) ~= "string" then return nil, "unknown switch " .. fmtNum(index) end
    local l = string.match(name, "^L(%d+)$")
    if l then
        local n = tonumber(l)
        if n >= 1 and n <= 64 then return n end
        return nil, name .. " is outside L01..L64"
    end
    local v = string.match(name, "^VS(%d+)$")
    if v then
        local n = tonumber(v)
        if n >= 1 and n <= 64 then return 64 + n end
        return nil, name .. " is outside VS01..VS64"
    end
    return nil, name .. " is not a logical or virtual switch"
end

-- One small piece of work per call; returns true when the scan is complete.
local function scanStep()
    local sc = S.scan
    if sc.phase == "start" then
        if not isDirectory(NG_DIR) then return nil, L.nong end
        local appLua = readFile(NG_DIR .. "/app.lua")
        local modelsDir = appLua == nil or string.find(appLua, "modelsDir", 1, true) ~= nil
        S.targetDir = modelsDir and (NG_DIR .. "/models") or NG_DIR
        local ngConfig = readFile(NG_DIR .. "/config.lua")
        S.ngLocal = ngConfig ~= nil and string.find(ngConfig, "localSwitch", 1, true) ~= nil
        ngConfig = nil
        S.files = {}
        for _, name in ipairs(listDir(OLD_DIR) or {}) do
            local base, addr = string.match(name, "^(.+)_(%d+)%.lua$")
            if base then
                S.files[#S.files + 1] = {name = name, base = base, oldAddress = tonumber(addr), tabAddress = tonumber(addr), checked = false}
            end
        end
        if #S.files == 0 then return nil, L.noold end
        table.sort(S.files, function(a, b) return string.lower(a.name) < string.lower(b.name) end)
        S.models = {}
        sc.modelFiles = {}
        for _, name in ipairs(listDir("/MODELS") or {}) do
            if string.find(string.lower(name), "%.yml$") then sc.modelFiles[#sc.modelFiles + 1] = name end
        end
        table.sort(sc.modelFiles, function(a, b) return string.lower(a) < string.lower(b) end)
        sc.phase, sc.i = "old", 0
        return false
    elseif sc.phase == "old" then
        if not sc.job then
            sc.i = sc.i + 1
            local f = S.files[sc.i]
            if not f then sc.phase, sc.i = "models", 0; return false end
            local text, err = readFile(OLD_DIR .. "/" .. f.name, MAX_OLD_FILE)
            if not text then f.error = err; return false end
            sc.job = parseOldBegin(text)
            return false -- loading costs most of a frame; resolve from the next frame on
        end
        parseOldStep(sc.job, 120)
        if sc.job.done then
            local f, job = S.files[sc.i], sc.job
            sc.job = nil
            if job.error then f.error = job.error
            elseif not isList(job.result.buttons) then f.error = "no buttons"
            else
                local st = job.result
                f.ok = true
                f.tabName = truthy(st.name) and cleanString(st.name, 32, "") or ""
                f.buttons = #st.buttons
                f.destination = int(st.commandBroadcastAddress, 0)
            end
            collectgarbage()
        end
        return false
    elseif sc.phase == "models" then
        if not sc.job then
            sc.i = sc.i + 1
            local name = sc.modelFiles[sc.i]
            if not name then sc.phase = "match"; return false end
            local text = readFile("/MODELS/" .. name)
            if not text then return false end
            sc.job, sc.jobFile = yamlBegin(text), name
        end
        yamlStep(sc.job, 80)
        if sc.job.done then
            local yaml, file = sc.job.root, sc.jobFile
            sc.job = nil
            local mname = modelNameOf(yaml)
            if mname ~= "" then
                local m = {file = file, name = mname, widgets = {}, hasNg = false}
                for _, w in ipairs(findWidgets(yaml)) do
                    if w.kind == "old" then
                        if not m.widgets[w.options.Address] then m.widgets[w.options.Address] = w.options end
                    else m.hasNg = true end
                end
                local base = S.targetDir .. "/model_" .. toHex(file)
                m.pathA, m.pathB = base .. ".a.lua", base .. ".b.lua"
                m.plan = planWrite(readHead(m.pathA, 600), readHead(m.pathB, 600))
                S.models[#S.models + 1] = m
            end
            collectgarbage()
        end
        return false
    elseif sc.phase == "match" then
        local byName = {}
        for _, m in ipairs(S.models) do
            local k = string.lower(m.name)
            if not byName[k] then byName[k] = m end
        end
        for _, f in ipairs(S.files) do
            local m = byName[string.lower(f.base)]
            f.model = m
            if m and m.widgets[f.oldAddress] then
                f.options = m.widgets[f.oldAddress]
            else
                f.options = defaultOptions()
                f.options.Address = f.oldAddress
                f.noOptions = true
            end
        end
        return true
    end
end

--------------------------------------------------------- selection model ---
local function checkedFiles(m)
    local list = {}
    for _, f in ipairs(S.files) do
        if f.checked and f.ok and f.model == m then list[#list + 1] = f end
    end
    table.sort(list, function(a, b)
        if a.tabAddress ~= b.tabAddress then return a.tabAddress < b.tabAddress end
        return string.lower(a.name) < string.lower(b.name)
    end)
    return list
end

local function selectedModels()
    local list, seen = {}, {}
    for _, f in ipairs(S.files) do
        if f.checked and f.ok and f.model and not seen[f.model] then
            seen[f.model] = true
            list[#list + 1] = f.model
        end
    end
    return list
end

local function countChecked()
    local n = 0
    for _, f in ipairs(S.files) do if f.checked and f.ok and f.model then n = n + 1 end end
    return n
end

-- Header values shown for a model: the user's choice, else what the conversion would pick.
local function modelSettings(m)
    if m.override then return m.override end
    local list = checkedFiles(m)
    local first = list[1]
    if not first then
        for _, f in ipairs(S.files) do if f.model == m and f.ok then first = f; break end end
    end
    if not first then return headerDefaults({options = defaultOptions(), destination = 0}) end
    return headerDefaults(first)
end

----------------------------------------------------------------- writing ---
local function startWrite()
    S.queue = selectedModels()
    S.qi, S.reports = 0, {}
    S.phase = "write"
end

-- Per model: load the checked files, convert, write, read back, check with the NG loader.
local function writeStep()
    local w = S.w
    if not w then
        S.qi = S.qi + 1
        local m = S.queue[S.qi]
        if not m then S.phase, S.lines = "result", nil; return end
        w = {model = m, files = checkedFiles(m), fi = 0, instances = {}, phase = "load", report = {model = m}}
        S.reports[#S.reports + 1] = w.report
        S.w = w
        return
    end
    local m, report = w.model, w.report
    local function fail(err)
        report.error = tostring(err)
        if w.file then io.close(w.file); w.file = nil end
        S.w = nil
    end
    if w.phase == "load" then
        if not w.job then
            w.fi = w.fi + 1
            local f = w.files[w.fi]
            if not f then
                w.phase = "convert"
                w.job = convertBegin(w.instances, {lang = S.lang, header = m.override, mapSwitch = S.ngLocal and mapSwitch or nil})
                return
            end
            local text, err = readFile(OLD_DIR .. "/" .. f.name, MAX_OLD_FILE)
            if not text then return fail(f.name .. ": " .. err) end
            w.job = parseOldBegin(text)
            return
        end
        parseOldStep(w.job, 120)
        if w.job.done then
            local job, f = w.job, w.files[w.fi]
            w.job = nil
            if job.error then return fail(f.name .. ": " .. job.error) end
            w.instances[#w.instances + 1] = {
                address = f.tabAddress, oldAddress = f.oldAddress, options = f.options, settings = job.result,
                tabName = f.tabName, label = "Address " .. fmtNum(f.oldAddress) .. " (" .. f.name .. ")",
            }
            if f.noOptions and not m.override then
                local wl = w.preWarnings or {}
                wl[#wl + 1] = {level = "warn", text = f.name .. ": the widget is not on the model's screens, so its options (CRSF/S.Port, interval) are unknown; defaults were used. Check the settings."}
                w.preWarnings = wl
            end
        end
    elseif w.phase == "convert" then
        convertStep(w.job, 4)
        if w.job.done then
            if w.job.error then return fail(w.job.error) end
            report.result = w.job.result
            for i, pw in ipairs(w.preWarnings or {}) do table.insert(report.result.warnings, i, pw) end
            w.job, w.instances = nil, nil
            collectgarbage()
            local ok, err = ensureDirectory(S.targetDir)
            if not ok then return fail(err) end
            w.path = m.plan.slot == "a" and m.pathA or m.pathB
            w.recs = ngRecords(report.result.config, m.plan.generation)
            w.parts, w.ri = {"return {\n"}, 0
            w.file = io.open(w.path, "w")
            if not w.file then return fail("cannot open " .. w.path) end
            if io.write(w.file, w.parts[1]) == nil then return fail("cannot write " .. w.path) end
            w.phase = "write"
        end
    elseif w.phase == "write" then
        for _ = 1, 6 do
            w.ri = w.ri + 1
            local rec = w.recs[w.ri]
            local line = rec and serializeRecord(rec) or "}\n"
            w.parts[#w.parts + 1] = line
            if io.write(w.file, line) == nil then return fail("cannot write " .. w.path) end
            if not rec then
                io.close(w.file)
                w.file = nil
                local back = readFile(w.path)
                if back ~= table.concat(w.parts) then return fail("verification failed for " .. w.path) end
                report.path = w.path
                w.parts, w.recs = nil, nil
                m.plan = planWrite(readHead(m.pathA, 600), readHead(m.pathB, 600))
                w.phase = "check"
                break
            end
        end
    elseif w.phase == "check" then
        if not w.check then
            -- the installed NG widget's own loader validates the new file
            local ok, job = pcall(function()
                local cfgChunk = loadScript(NG_DIR .. "/config.lua", "t")
                local stChunk = loadScript(NG_DIR .. "/storage.lua", "t")
                if not cfgChunk or not stChunk then return nil end
                local t = function(fmt, ...)
                    if select("#", ...) > 0 then return string.format(fmt, ...) end
                    return fmt
                end
                local storage = stChunk(cfgChunk({t = t}))
                if type(storage) ~= "table" or type(storage.load) ~= "function" or type(storage.stepLoad) ~= "function" then return nil end
                return {storage = storage, load = storage.load(report.path)}
            end)
            if not ok or not job then report.check = "na"; S.w = nil; return end
            w.check = job
            return
        end
        local c = w.check
        for _ = 1, 2 do
            if c.load.done then break end
            local ok, err = pcall(c.storage.stepLoad, c.load)
            if not ok then report.check, report.checkError = "fail", tostring(err); S.w = nil; return end
        end
        if c.load.done then
            if c.load.result then report.check = "ok"
            else report.check, report.checkError = "fail", tostring(c.load.error) end
            S.w = nil
        end
    end
end

------------------------------------------------------------------- drawing ---
local LINE = 20
local TOP = 32

local function textWidth(s)
    if lcd.sizeText then
        local w = lcd.sizeText(s, SMLSIZE)
        if type(w) == "number" then return w end
    end
    return #s * 7
end

local function wrap(s, width, out, prefix)
    prefix = prefix or ""
    local line = prefix
    for word in string.gmatch(s, "%S+") do
        local candidate = line == prefix and (prefix .. word) or (line .. " " .. word)
        if textWidth(candidate) > width and line ~= prefix then
            out[#out + 1] = line
            line = "   " .. word
        else
            line = candidate
        end
    end
    if line ~= prefix then out[#out + 1] = line end
end

local function header(title)
    lcd.clear()
    lcd.drawText(8, 4, title or L.title, BOLD)
end

local function visibleRows() return math.floor((LCD_H - TOP - 24) / LINE) end

local function drawRows(rows, selected, scroll, top)
    top = top or TOP
    local visible = math.floor((LCD_H - top - 24) / LINE)
    for i = 1, visible do
        local idx = i + scroll
        local r = rows[idx]
        if not r then break end
        lcd.drawText(8, top + (i - 1) * LINE, r, SMLSIZE + (idx == selected and INVERS or 0))
    end
end

local function keepVisible(sel, scroll, visible)
    if sel > scroll + visible then scroll = sel - visible end
    if sel <= scroll then scroll = sel - 1 end
    return math.max(0, scroll)
end

local function footer(text) lcd.drawText(8, LCD_H - 20, text, SMLSIZE) end

local function drawMessage(msg, extra)
    header()
    local out = {}
    wrap(msg, LCD_W - 24, out)
    if extra then out[#out + 1] = extra end
    for i, l in ipairs(out) do lcd.drawText(8, TOP + (i - 1) * LINE, l, SMLSIZE) end
    footer(L.exit)
end

-- list page rows: 1 = check all, 2..n+1 = files, n+2 = convert
local function listRows()
    local rows = {}
    local anyChecked = countChecked() > 0
    rows[1] = ">> " .. (anyChecked and L.selectNone or L.selectAll)
    for i, f in ipairs(S.files) do
        local mark = (f.checked and f.ok and f.model) and "[x] " or "[  ] "
        local desc
        if not f.ok then desc = L.unusable .. " (" .. tostring(f.error) .. ")"
        else
            desc = (f.model and ("-> " .. f.model.name .. " (" .. f.model.file .. ")") or L.unassigned)
                .. "  " .. (f.tabName ~= "" and f.tabName or "-") .. "  " .. f.buttons .. " " .. L.buttons
            if f.tabAddress ~= f.oldAddress then desc = desc .. "  @" .. f.tabAddress end
        end
        rows[i + 1] = mark .. f.name .. "  " .. desc
    end
    rows[#rows + 1] = ">> " .. string.format(L.convert, countChecked(), #selectedModels())
    return rows
end

local function drawList()
    header(L.list)
    S.rows = listRows()
    S.scroll = keepVisible(S.sel, S.scroll, visibleRows())
    drawRows(S.rows, S.sel, S.scroll)
    for i = 1, visibleRows() do
        local idx = i + S.scroll
        if idx >= 2 and idx <= #S.files + 1 then lcd.drawText(LCD_W - 20, TOP + (i - 1) * LINE, ">", SMLSIZE) end
    end
    footer(S.notice or L.help)
end

-- detail page fields for file f
local function detailFields(f)
    local fields = {
        {id = "include", label = L.include, value = (f.checked and L.yes or L.no)},
        {id = "model", label = L.target, value = f.model and (f.model.name .. " (" .. f.model.file .. ")") or L.none},
        {id = "tabAddress", label = L.tabAddress, value = fmtNum(f.tabAddress)},
        {id = "info", label = L.oldAddress, value = fmtNum(f.oldAddress) .. "   " .. L.source .. ": " .. (f.noOptions and L.fromDefaults or L.fromModel)},
    }
    if f.model then
        local s = modelSettings(f.model)
        fields[#fields + 1] = {id = "info", label = string.format(L.forModel, f.model.name), value = nil}
        fields[#fields + 1] = {id = "protocol", label = L.protocol, value = PROTOCOLS[s.protocol]}
        fields[#fields + 1] = {id = "interval", label = L.interval, value = fmtNum(s.interval)}
        fields[#fields + 1] = {id = "destination", label = L.destination, value = fmtNum(s.destination)}
        fields[#fields + 1] = {id = "sportPhysicalId", label = L.sportPhy, value = fmtNum(s.sportPhysicalId)}
        fields[#fields + 1] = {id = "sportAppId", label = L.sportApp, value = fmtNum(s.sportAppId)}
    end
    return fields
end

local function drawDetail()
    local f = S.files[S.fileIndex]
    header(string.format(L.detail, f.name))
    local fields = detailFields(f)
    S.fields = fields
    local rows = {}
    for i, fl in ipairs(fields) do
        rows[i] = fl.value and (fl.label .. ": " .. fl.value .. ((S.editing and i == S.dsel) and "  <>" or "")) or fl.label
    end
    S.dscroll = keepVisible(S.dsel, S.dscroll or 0, visibleRows())
    drawRows(rows, S.dsel, S.dscroll)
    footer(S.notice or L.detailHelp)
end

local function drawConfirm()
    header()
    local y = TOP
    lcd.drawText(8, y, L.confirm, SMLSIZE)
    for _, m in ipairs(selectedModels()) do
        if m.plan.replaces then
            y = y + LINE
            lcd.drawText(20, y, m.name .. " (" .. m.file .. ", generation " .. fmtNum(m.plan.previous or 0) .. ")", SMLSIZE)
        end
    end
    lcd.drawText(8, y + LINE + 8, L.confirm2, SMLSIZE)
    lcd.drawText(8, y + 2 * LINE + 8, L.confirm3, SMLSIZE)
    lcd.drawText(8, y + 3 * LINE + 16, L.confirm4, SMLSIZE + BOLD)
end

-- Report items as {text, prefix}; wrapped a few per frame (wrapping measures every word).
local function reportItems()
    local items = {}
    local function add(text, prefix) items[#items + 1] = {text, prefix} end
    for _, r in ipairs(S.reports) do
        local m = r.model
        if r.error then
            add(m.name .. ": " .. L.failed .. ": " .. r.error)
        elseif r.result then
            local res = r.result
            add(m.name .. ": " .. L.done .. " - " .. res.stats.controls .. " " .. L.controls .. ", " .. #res.config.tabs .. " " .. L.tabs
                .. ", " .. #res.skipped .. " " .. L.skippedN)
            add(r.check == "ok" and L.check_ok or r.check == "na" and L.check_na
                or r.check == "fail" and (L.check_fail .. ": " .. tostring(r.checkError)) or L.checking, "   ")
            add(r.path or "", "   ")
        end
    end
    add(L.next1)
    add(L.next2)
    local any = false
    for _, r in ipairs(S.reports) do
        local res = r.result
        if res and (#res.warnings > 0 or #res.skipped > 0) then
            if not any then add(""); add(L.report); any = true end
            add(r.model.name .. ":")
            for _, w in ipairs(res.warnings) do add(w.text, (w.level == "warn" and "! " or "i ")) end
            for _, s in ipairs(res.skipped) do add(s.label .. ": " .. s.reason, "- ") end
        end
    end
    return items
end

local function drawResult()
    header()
    if not S.lines then S.lines, S.items, S.ii = {}, reportItems(), 0 end
    for _ = 1, 6 do
        S.ii = S.ii + 1
        local it = S.items[S.ii]
        if not it then break end
        if it[1] == "" then S.lines[#S.lines + 1] = "" else wrap(it[1], LCD_W - 24, S.lines, it[2]) end
    end
    local visible = visibleRows()
    S.rscroll = clamp(S.rscroll or 0, 0, math.max(0, #S.lines - visible))
    for i = 1, visible do
        local l = S.lines[i + S.rscroll]
        if not l then break end
        lcd.drawText(8, TOP + (i - 1) * LINE, l, SMLSIZE)
    end
    footer(L.exit)
end

------------------------------------------------------------------- events ---
local function tappedRow(touchState, scroll)
    if not touchState or not touchState.y then return nil end
    local i = math.floor((touchState.y - TOP) / LINE) + 1
    if i < 1 or i > visibleRows() then return nil end
    return i + scroll
end

local function openDetail(index)
    S.fileIndex, S.dsel, S.dscroll, S.editing, S.phase = index, 1, 0, false, "detail"
end

local function toggleFile(f, index)
    if not f.ok then openDetail(index); return end
    if not f.model then openDetail(index); S.notice = L.noTarget; return end
    f.checked = not f.checked
end

local function activateListRow(sel)
    local n = #S.files
    if sel == 1 then
        local anyChecked = countChecked() > 0
        for _, f in ipairs(S.files) do f.checked = (not anyChecked) and f.ok and f.model ~= nil end
    elseif sel <= n + 1 then
        toggleFile(S.files[sel - 1], sel - 1)
    else
        if countChecked() == 0 then S.notice = L.nothing; return end
        for _, m in ipairs(selectedModels()) do
            if m.plan.replaces then S.phase = "confirm"; return end
        end
        startWrite()
    end
end

local function changeField(f, id, dir)
    if id == "model" then
        local idx = 0
        for i, m in ipairs(S.models) do if m == f.model then idx = i end end
        idx = (idx + dir) % (#S.models + 1)
        f.model = idx > 0 and S.models[idx] or nil
        if f.model then
            local o = f.model.widgets[f.oldAddress]
            f.options, f.noOptions = o or defaultOptions(), o == nil
            if not o then f.options.Address = f.oldAddress end
        else
            f.checked = false
        end
    elseif id == "tabAddress" then
        f.tabAddress = clamp(f.tabAddress + dir, 0, 255)
    elseif f.model then
        local m = f.model
        if not m.override then
            local s = modelSettings(m)
            m.override = {protocol = s.protocol, interval = s.interval, destination = s.destination,
                sportPhysicalId = s.sportPhysicalId, sportAppId = s.sportAppId}
        end
        local o = m.override
        if id == "protocol" then o.protocol = (o.protocol + dir) % 4
        elseif id == "interval" then o.interval = clamp(o.interval + dir * 5, 5, 1000)
        elseif id == "destination" then o.destination = clamp(o.destination + dir, 0, 255)
        elseif id == "sportPhysicalId" then o.sportPhysicalId = clamp(o.sportPhysicalId + dir, 0, 0x1b)
        elseif id == "sportAppId" then o.sportAppId = clamp(o.sportAppId + dir, 0, 255) end
    end
end

local function init()
    S = {phase = "scan", scan = {phase = "start"}, sel = 1, scroll = 0, rscroll = 0, lang = language()}
    L = TEXT[S.lang]
end

local function isDetailKey(event)
    return event == EVT_VIRTUAL_ENTER_LONG or (EVT_VIRTUAL_NEXT_PAGE ~= nil and event == EVT_VIRTUAL_NEXT_PAGE)
end

local function run(event, touchState)
    if S == nil then init() end
    event = event or 0
    local tap = EVT_TOUCH_TAP ~= nil and event == EVT_TOUCH_TAP
    if event == EVT_VIRTUAL_ENTER_LONG and killEvents then killEvents(event) end

    if S.phase == "scan" then
        local ok, res, err = pcall(scanStep)
        if not ok then S.phase, S.message = "message", tostring(res)
        elseif res == nil then S.phase, S.message = "message", err
        elseif res == true then S.phase = "list"; drawList(); return 0 end
        local sc = S.scan
        local progress = sc.phase == "old" and string.format(L.scanOld, sc.i, #S.files)
            or sc.phase == "models" and string.format(L.scanModels, sc.i, #(sc.modelFiles or {})) or nil
        if S.phase == "scan" then drawMessage(L.scanning, progress) end
        if event == EVT_VIRTUAL_EXIT then return 1 end
        return 0
    end
    if S.phase == "message" then
        drawMessage(S.message)
        if event == EVT_VIRTUAL_EXIT or event == EVT_VIRTUAL_ENTER or tap then return 1 end
        return 0
    end
    if S.phase == "list" then
        local rows = #S.files + 2
        if event ~= 0 then S.notice = nil end
        if event == EVT_VIRTUAL_EXIT then return 1
        elseif event == EVT_VIRTUAL_NEXT then S.sel = S.sel % rows + 1
        elseif event == EVT_VIRTUAL_PREV then S.sel = (S.sel - 2) % rows + 1
        elseif event == EVT_VIRTUAL_ENTER then activateListRow(S.sel)
        elseif isDetailKey(event) then
            if S.sel >= 2 and S.sel <= #S.files + 1 then openDetail(S.sel - 1) end
        elseif tap then
            local idx = tappedRow(touchState, S.scroll)
            if idx and idx <= rows then
                S.sel = idx
                if touchState.x and touchState.x > LCD_W - 60 and idx >= 2 and idx <= #S.files + 1 then openDetail(idx - 1)
                else activateListRow(idx) end
            end
        end
    elseif S.phase == "detail" then
        local f = S.files[S.fileIndex]
        S.fields = detailFields(f)
        local n = #S.fields
        if event ~= 0 then S.notice = nil end
        local function activate()
            local id = S.fields and S.fields[S.dsel] and S.fields[S.dsel].id
            if id == "include" then
                if not f.ok then S.notice = L.unusable .. " (" .. tostring(f.error) .. ")"
                elseif not f.model then S.notice = L.noTarget
                else f.checked = not f.checked end
            elseif id and id ~= "info" then
                S.editing = not S.editing
            end
        end
        if event == EVT_VIRTUAL_EXIT then
            if S.editing then S.editing = false else S.phase = "list" end
        elseif event == EVT_VIRTUAL_NEXT or event == EVT_VIRTUAL_PREV then
            local dir = event == EVT_VIRTUAL_NEXT and 1 or -1
            if S.editing then changeField(f, S.fields[S.dsel].id, dir)
            else S.dsel = (S.dsel - 1 + dir) % n + 1 end
        elseif event == EVT_VIRTUAL_ENTER then activate()
        elseif tap then
            local idx = tappedRow(touchState, S.dscroll or 0)
            if idx and idx <= n then S.dsel = idx; activate() end
        end
        if S.phase == "detail" then
            if S.dsel > #detailFields(f) then S.dsel = 1 end
            drawDetail()
            return 0
        end
    elseif S.phase == "confirm" then
        if event == EVT_VIRTUAL_EXIT then S.phase = "list"
        elseif event == EVT_VIRTUAL_ENTER or tap then startWrite()
        else drawConfirm(); return 0 end
    end
    if S.phase == "list" then drawList(); return 0 end
    if S.phase == "detail" then drawDetail(); return 0 end
    if S.phase == "confirm" then drawConfirm(); return 0 end
    if S.phase == "write" then
        local ok, err = pcall(writeStep)
        if not ok then
            local r = S.reports[#S.reports]
            if r then r.error = tostring(err) end
            if S.w and S.w.file then io.close(S.w.file) end
            S.w = nil
        end
        if S.phase == "write" then
            local m = S.queue[S.qi]
            drawMessage(string.format(L.writing, m and m.name or ""), m and (S.qi .. " / " .. #S.queue) or nil)
        end
        return 0
    end
    if S.phase == "result" then
        if event == EVT_VIRTUAL_EXIT then return 1
        elseif event == EVT_VIRTUAL_NEXT then S.rscroll = (S.rscroll or 0) + 1
        elseif event == EVT_VIRTUAL_PREV then S.rscroll = math.max(0, (S.rscroll or 0) - 1)
        end
        drawResult()
        return 0
    end
    return 0
end

return {name = "MultiSw -> NG", init = init, run = run, core = Core}
