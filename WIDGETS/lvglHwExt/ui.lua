-- todo

local zone, options, name, dir = ...
local widget = {}
widget.options = options;
widget.zone = zone;
widget.name = name;

local serialize = loadScript(dir .. "tableser.lua")();

widget.ui = nil;

local settings = {}

local function switchCallback(controller, switch, on)
    print("switchCB:", controller, switch, on);
    if ((settings.controller ~= nil) and (settings.controller[controller] ~= nil)) then
        if (settings.controller[controller].switches[switch] ~= nil) then
            setVirtualSwitch(switch, on);
        end
    end
end
local function propCallback(controller, prop, value)
    print("propCB:", controller, prop, value);
end

local function activateVSwitches()
    for c = 1, #settings.controller do
        if (settings.controller[c] ~= nil) then
            for s = 1, #settings.controller[c].switches do
                if (settings.controller[c].switches[s] ~= nil) then
                    activateVirtualSwitch(settings.controller[c].switches[s], true);        
                end
            end
        end        
    end
end

local function activateVInputs()
end

local settingsVersion = 2;
local function resetSettings() 
    print("resetSettings");
    settings.version = settingsVersion;
    settings.controller = {{
        switches = {1, 2, 3, 4, 5};
        props = {};
    }};
    activateVSwitches();
    activateVInputs();
end
resetSettings();

local function isValidSettingsTable(t) 
    if (t.version ~= nil) then
        if (t.version == settingsVersion) then
            return true;
        end
    end
    return false;
end

local settingsFilename = nil;

local function updateFilename()
    local fname = dir .. model.getInfo().name .. "_" .. widget.options.Name .. ".lua";
    if (fname ~= settingsFilename) then
        settingsFilename = fname;
        return true;
    end
    return false;
end
updateFilename();

local function askClose()
    lvgl.confirm({title = "Exit", message = "Really exit?", 
                  confirm = (function() serialize.save(settings, settingsFilename); lvgl.exitFullScreen(); end),
                 })
end

local function createDisplay() 
    local children = {};
    return children;
end

function widget.displayPage()
    lvgl.clear();
    local page = lvgl.page({
        title = widget.name .. " : " .. widget.options.Name,
        subtitle = "Display",
        back = askClose,
    });
    local uit = { {
            type = "box",
            flexFlow = lvgl.FLOW_COLUMN,
            flexPad = lvgl.PAD_LARGE,
            children = createDisplay();
         }
    };
    widget.ui = page:build(uit);
end

local function createSettings() 
    local children = {};
    return children;
end

function widget.settingsPage()
    lvgl.clear();
    local page = lvgl.page({
        title = widget.name .. " : " .. widget.options.Name,
        subtitle = "Settings",
        back = askClose,
    });
    local uit = { {
            type = "box",
            flexFlow = lvgl.FLOW_COLUMN,
            flexPad = lvgl.PAD_LARGE,
            children = createSettings();
         }
    };
    widget.ui = page:build(uit);
end

function widget.widgetPage()
    lvgl.clear();
    widget.ui = lvgl.build({
        { type = "box", flexFlow = lvgl.FLOW_COLUMN, children = {
            { type = "label", text = "HW Extension", w = widget.zone.x, align = CENTER},
            { type = "label", text = widget.options.Name, w = widget.zone.x, align = CENTER },
        }
        }
    });
end

local initialized = false;
function widget.update()
    local changed = updateFilename();
    if ((not initialized) or changed) then
        setSerialBaudrate(115200);
        local st = serialize.load(settingsFilename);
        if (st ~= nil) then
            if (isValidSettingsTable(st)) then
                settings = st;
            else
                resetSettings();
            end
        else
            resetSettings();
        end
        initialized = true;
    end
    if lvgl.isFullScreen() then
        widget.displayPage();
    else
        widget.widgetPage();
    end
    serialize.save(settings, settingsFilename);
end

local fsm = loadScript(dir .. "proto.lua")(switchCallback, propCallback);

function widget.background()
    fsm.process();
end

local function fullScreenRefresh()
end

function widget.refresh(event, touchState)
    if lvgl == nil then
        lcd.drawText(widget.zone.x, widget.zone.y, "Lvgl support required", COLOR_THEME_WARNING)
    end
    if (lvgl.isFullScreen()) then
        fullScreenRefresh();
    end
    widget.background();
end

return widget;
