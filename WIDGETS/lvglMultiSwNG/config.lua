-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 Wilhelm Meier

local app = ...
local t = app.t
local M = {version = 1, t = t}
M.types = {t("Button"), t("Toggle"), t("3Pos"), t("Momentary"), t("Slider")}
M.protocols = {"CRSF", "S.Port WM", "S.Port ACW 1.5", "S.Port ACW 1.4"}
M.typeIds = {[0] = {1, 2, 3, 4, 5}, [1] = {1, 2, 3, 4}, [2] = {1, 2, 4}}
M.typeIds[3] = M.typeIds[2]

local function integer(v, low, high)
    return type(v) == "number" and v == math.floor(v) and v >= low and v <= high
end

local schemas = {
    config = {
        version = {1, 1}, generation = {0, 2147483647}, name = 32,
        destination = {0, 255}, interval = {5, 1000}, sendColors = {0, 1}, autoSave = {0, 1},
        buttonSpacing = {-1, 40},
        protocol = {0, 3}, sportPhysicalId = {0, 0x1b}, sportAppId = {0, 255},
    },
    tab = {
        id = {1, 2147483647}, name = 32, address = {0, 255},
        columns = {1, 4}, height = {0, 240},
    },
    control = {
        id = {1, 2147483647}, tab = {1, 2147483647}, name = 32, leftText = 32, rightText = 32,
        type = {1, 5}, address = {-1, 255}, output = {1, 8},
        color = {-2147483648, 4294967295}, textColor = {-2147483648, 4294967295}, font = {0, 65535},
        visible = {0, 1}, switch = {-2147483648, 2147483647},
        switch2 = {-2147483648, 2147483647}, source = {-2147483648, 2147483647},
        activation = {-2147483648, 2147483647}, group = {0, 255}, image = 128,
        sportType = {0, 255}, sportOptions = {0, 255}, sportPwmOn = {0, 255},
    },
}

function M.validateRecord(record)
    if type(record) ~= "table" or not schemas[record.kind] then
        return nil, t("Unknown configuration record")
    end
    local schema = schemas[record.kind]
    for key, rule in pairs(schema) do
        local value = record[key]
        if type(rule) == "number" then
            if type(value) ~= "string" or #value > rule or string.find(value, "[%z\1-\31]") then
                return nil, t("Invalid %s.%s", record.kind, key)
            end
        elseif not integer(value, rule[1], rule[2]) then
            return nil, t("Invalid %s.%s", record.kind, key)
        end
    end
    if record.kind == "tab" and record.height > 0 and record.height < 30 then
        return nil, t("Invalid tab.height: use 0 or 30..240")
    end
    for key in pairs(record) do
        if key ~= "kind" and schema[key] == nil then
            return nil, t("Unknown property: %s", tostring(key))
        end
    end
    return true
end

function M.copy(record)
    local result = {}
    for key, value in pairs(record) do result[key] = value end
    return result
end

function M.newControl(id, tab, output)
    return {
        kind = "control", id = id, tab = tab, name = t("Output %d", output),
        leftText = t("Left"), rightText = t("Right"),
        type = 1, address = -1, output = output,
        color = COLOR_THEME_SECONDARY3, textColor = COLOR_THEME_PRIMARY3, font = 0,
        visible = 1, switch = 0, switch2 = 0, source = 0, activation = 0,
        group = 0, image = "", sportType = 1, sportOptions = 0, sportPwmOn = 255,
    }
end

function M.defaults()
    local config = {
        header = {kind = "config", version = 1, generation = 0, name = "MultiSwitch NG",
                  destination = 0, interval = 100, sendColors = 0, autoSave = 1,
                  buttonSpacing = -1,
                  protocol = 0, sportPhysicalId = 0, sportAppId = 0x51},
        tabs = {{kind = "tab", id = 1, name = t("Tab %d", 1), address = 0, columns = 2, height = 0}},
        controls = {},
    }
    for i = 1, 8 do config.controls[i] = M.newControl(i, 1, i) end
    return config
end

function M.address(control, tab)
    if control.address == -1 then return tab.address end
    return control.address
end

function M.builder()
    return {config = {tabs = {}, controls = {}}, tabs = {}, ids = {}, endpoints = {}}
end

function M.append(builder, record)
    if type(record) == "table" and record.kind == "config" then
        record = M.copy(record)
        if record.autoSave == nil then record.autoSave = 0 end
        if record.buttonSpacing == nil then record.buttonSpacing = -1 end
        if record.protocol == nil then record.protocol = 0 end
        if record.sportPhysicalId == nil then record.sportPhysicalId = 0 end
        if record.sportAppId == nil then record.sportAppId = 0x51 end
    elseif type(record) == "table" and record.kind == "control"
        and (record.sportType == nil or record.sportOptions == nil or record.sportPwmOn == nil
            or record.leftText == nil or record.rightText == nil) then
        record = M.copy(record)
        if record.sportType == nil then record.sportType = 1 end
        if record.sportOptions == nil then record.sportOptions = 0 end
        if record.sportPwmOn == nil then record.sportPwmOn = 255 end
        if record.leftText == nil then record.leftText = t("Left") end
        if record.rightText == nil then record.rightText = t("Right") end
    end
    local ok, err = M.validateRecord(record)
    if not ok then return nil, err end
    local config = builder.config
    if record.kind == "config" then
        if config.header then return nil, t("Duplicate configuration header") end
        config.header = record
    elseif not config.header then
        return nil, t("Missing configuration header")
    elseif record.kind == "tab" then
        if builder.tabs[record.id] then return nil, t("Duplicate tab ID") end
        builder.tabs[record.id] = record
        config.tabs[#config.tabs + 1] = record
    else
        if config.header.protocol == 1 and record.type == 5 then
            return nil, t("Slider is not supported by S.Port WM: %s", record.name)
        end
        if config.header.protocol >= 2 and (record.type == 3 or record.type == 5) then
            return nil, t("%s is not supported by S.Port ACW: %s", M.types[record.type], record.name)
        end
        local tab = builder.tabs[record.tab]
        if not tab then return nil, t("Control refers to unknown tab") end
        if builder.ids[record.id] then return nil, t("Duplicate control ID") end
        local endpoint = M.address(record, tab) * 8 + record.output
        if config.header.protocol >= 2 and endpoint > 255 then
            return nil, t("ACW switch number must be 1..255: %s", record.name)
        end
        if builder.endpoints[endpoint] then
            return nil, t("Address/output already assigned: %d/%d", M.address(record, tab), record.output)
        end
        builder.ids[record.id], builder.endpoints[endpoint] = true, true
        config.controls[#config.controls + 1] = record
    end
    return true
end

function M.finish(builder)
    if not builder.config.header or #builder.config.tabs == 0 then
        return nil, t("Configuration needs a header and at least one tab")
    end
    return builder.config
end

function M.validate(config)
    local builder = M.builder()
    local ok, err = M.append(builder, config.header)
    if not ok then return nil, err end
    for _, list in ipairs({config.tabs, config.controls}) do
        for _, record in ipairs(list) do
            ok, err = M.append(builder, record)
            if not ok then return nil, err end
        end
    end
    return M.finish(builder)
end

return M
