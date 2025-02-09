local zone, options, name, dir, widget_id = ...
local widget = {}
widget.options = options;
widget.id = widget_id;
widget.zone = zone;
widget.name = name;

local TYPE_BUTTON    = 1;
local TYPE_TOGGLE    = 2;
local TYPE_3POS      = 3;
local TYPE_MOMENTARY = 4;
local TYPE_SLIDER    = 5;

local serialize = loadScript("/WIDGETS/" .. dir .. "/tableser.lua")();

widget.ui = nil;

local settings = {};
local state = {};
local settingsFilename = "/WIDGETS/" .. dir .. "/" .. model.getInfo().name .. "_" .. widget.options.Name .. ".lua";
local settingsVersion = 11;

local function saveSettings() 
    serialize.save(settings, settingsFilename);
end

local function resetSlider(i)
    settings.sliders[i] = { name = "VS" .. i, shm = i, vin = i, useShm = 0, width = (LCD_W - 20) / settings.numberOfSliders,
                            color = COLOR_THEME_SECONDARY3, textColor = COLOR_THEME_PRIMARY3, font = 0 };
    state.values[i] = 0;
end

local function resetButton(i) 
    settings.buttons[i] = { name = "Button" .. i, type = TYPE_BUTTON; width = (LCD_W - 20) / 4, vs = i,
    color = COLOR_THEME_SECONDARY3, textColor = COLOR_THEME_PRIMARY3, font = 0 };
    state.buttons[i] = getVirtualSwitch(settings.buttons[i].vs);
end

local function resetSettings()
    settings.version = settingsVersion;
    settings.numberOfSliders = 6;
    settings.sliders = {};
    state.values = {};
    for i = 1, settings.numberOfSliders do
        resetSlider(i);
    end
    settings.numberOfButtons = 6;
    settings.buttons = {};
    state.buttons = {};
    for i = 1, settings.numberOfButtons do
        resetButton(i);
    end
end
resetSettings();

local function askClose()
    lvgl.confirm({title="Exit", message="Really exit?", confirm=(function() saveSettings(); lvgl.exitFullScreen(); end) })
end
  
local function createSlider(i)    
    return { type = "box", flexFlow = lvgl.FLOW_COLUMN, w = settings.sliders[i].width, children = {
            { type = "label", text = settings.sliders[i].name, color = settings.sliders[i].textColor, font = settings.sliders[i].font},
            { type = "verticalSlider", min = -1024, max = 1024, h = 180,
                get = (function() if (settings.sliders[i].useShm > 0) then return getShmVar(settings.sliders[i].shm); else return state.values[i]; end; end),
                set = (function(v) if (settings.sliders[i].useShm > 0) then 
                                        setShmVar(settings.sliders[i].shm, v); 
                                    else 
                                        state.values[i] = v; 
                                        setVirtualInput(settings.sliders[i].vin, v); 
                                    end 
                                end),
                color = settings.sliders[i].color
            },
            { type = "label", text = (function() if (settings.sliders[i].useShm > 0) then return math.floor(getShmVar(i) / 10.24 + 0.5) .. "%"; else return math.floor(state.values[i] / 10.24 + 0.5) .. "%"; end; end)}
            }
        };
end

local function createSliders() 
    local children = {};
    for i = 1, settings.numberOfSliders do
        children[#children+1] = createSlider(i);
        if (i < settings.numberOfSliders) then
            children[#children+1] = {type = "vline", h = 100, w = 1};
        end
    end
    return children;
end

local function invert(v) 
    if (v == 0) then
        return 1;
    else
        return 0;
    end    
end

local function createButton(i)
    print("createButton", i, settings.buttons[i].name);
    return {type = "button", text = settings.buttons[i].name, w = settings.buttons[i].width,
            color = settings.buttons[i].color, textColor = settings.buttons[i].textColor, font = settings.buttons[i].font,
            checked = state.buttons[i],
            press = (function() state.buttons[i] = not state.buttons[i]; setVirtualSwitch(settings.buttons[i].vs, state.buttons[i]); if (state.buttons[i]) then return 1; else return 0; end; end),
};
end

local function createButtons(row)
    print("createButtons", row);
    local children = {};
    local i1 = (row - 1) * 4 + 1;
    local i2 = math.min(row * 4, settings.numberOfButtons);
    for i = i1, i2 do
        children[#children+1] = createButton(i);
    end
    return children;
end

local function createButtonRow(r)
    print("createButtonRow", r);
    return {type = "box", flexFlow = lvgl.FLOW_ROW, children = createButtons(r)};
end

local function createButtons()
    local children = {};
    local rows = math.floor(settings.numberOfButtons / 4 + 0.9);
    print("createButtons", rows);
    for i = 1, rows do
        children[i] = createButtonRow(i);
    end
    return children;
end

function widget.controlPage()
    local page = lvgl.page({
        title = widget.name,
        subtitle = "Controls - " .. widget.options.Name,
        back = (function() askClose(); end),
    });
    local uit = {
        {type = "box", flexFlow = lvgl.FLOW_COLUMN, children = {
            {type = "box", flexFlow = lvgl.FLOW_ROW, children = createSliders()},
            {type = "hline", w = 100, h = 1},
            {type = "box", flexFlow = lvgl.FLOW_COLUMN, children = createButtons()},
            {type = "hline", w = 100, h = 1},
            {type = "box", flexFlow = lvgl.FLOW_ROW, children = {
                {type = "button", text = "Settings", press = widget.settingsPage },
                {type = "button", text = "Global", press = widget.globalsPage }
            }}
            }
        }
    };
    widget.ui = page:build(uit);
end

local function createSetting(i)
    local w = widget.zone.w / 6;
    local wmin = math.min(30, w);
    local wmax = math.max(widget.zone.w / 2, w);
    return { type = "box", flexFlow = lvgl.FLOW_ROW, children = {
            {type = "label", text = "Name: "},
            {type = "textEdit", value = settings.sliders[i].name, set = (function(v) settings.sliders[i].name = v; end), w = 100},
            {type = "label", text = "Width: "},
            {type = "numberEdit", min = wmin , max = wmax, w = 60, get = (function() return settings.sliders[i].width; end), set = (function(v) settings.sliders[i].width = v; end) }, 
            { type = "label", text = " Color:" },
            { type = "color", get = (function() return settings.sliders[i].color; end),
                              set = (function(v) settings.sliders[i].color = v; end) },
            { type = "label", text = " TextColor:" },
            { type = "color", get = (function() return settings.sliders[i].textColor; end),
                              set = (function(v) settings.sliders[i].textColor = v; end) },                                     
            { type = "label", text = " Font:" },
            { type = "font", get = (function() return settings.sliders[i].font; end),
                            set = (function(v) settings.sliders[i].font = v; end) },                                     
            { type = "label", text = " UseShm:" },
            { type = "toggle", get = (function() return settings.sliders[i].useShm; end),
                               set = (function(v) settings.sliders[i].useShm = v; end)},
            {type = "label", text = "ShmV: "},
            {type = "numberEdit", min = 1 , max = 16, w = 60, 
                    active = (function() return (settings.sliders[i].useShm > 0); end),
                    get = (function() return settings.sliders[i].shm; end), 
                    set = (function(v) settings.sliders[i].shm = v; end) },                             
            {type = "label", text = "Vin: "},
            {type = "numberEdit", min = 1 , max = 16, w = 60, 
                    active = (function() return (settings.sliders[i].useShm == 0); end),
                    get = (function() return settings.sliders[i].vin; end), 
                    set = (function(v) settings.sliders[i].vin = v; end) },                             
        }
    }
end

local function createButtonSetting(i)
    local w = widget.zone.w / 6;
    local wmin = math.min(30, w);
    local wmax = math.max(widget.zone.w / 2, w);
    return { type = "box", flexFlow = lvgl.FLOW_ROW, children = {
            {type = "label", text = "Name: "},
            {type = "textEdit", value = settings.buttons[i].name, set = (function(v) settings.buttons[i].name = v; end), w = 100},
            {type = "label", text = "Width: "},
            {type = "numberEdit", min = wmin , max = wmax, w = 60, get = (function() return settings.buttons[i].width; end), set = (function(v) settings.buttons[i].width = v; end) }, 
            { type = "label", text = " Color:" },
            { type = "color", get = (function() return settings.buttons[i].color; end),
                              set = (function(v) settings.buttons[i].color = v; end) },
            { type = "label", text = " TextColor:" },
            { type = "color", get = (function() return settings.buttons[i].textColor; end),
                              set = (function(v) settings.buttons[i].textColor = v; end) },                                     
            { type = "label", text = " Font:" },
            { type = "font", get = (function() return settings.buttons[i].font; end),
                            set = (function(v) settings.buttons[i].font = v; end) },                                     
            {type = "label", text = "VS: "},
            {type = "numberEdit", min = 1 , max = 64, w = 60, 
                    get = (function() return settings.buttons[i].vs; end), 
                    set = (function(v) settings.buttons[i].vs = v; end) },                             
        }
    }
end

local function createSettings()
    local children = {};
    for i = 1, settings.numberOfSliders do
        children[#children+1] = createSetting(i);        
    end
    children[#children+1] = {type = "hline", w = 100, h = 1};
    for i = 1, settings.numberOfButtons do
        children[#children+1] = createButtonSetting(i);        
    end
    children[#children+1] = {type = "hline", w = 100, h = 1};
    children[#children+1] = {type = "box", flexFlow = lvgl.FLOW_ROW, children = {
        {type = "button", text = "Controls", press = (function() saveSettings(); widget.controlPage(); end)},
        {type = "button", text = "Global", press = (function() saveSettings(); widget.globalsPage(); end)}
    }};
    return children;
end

function widget.settingsPage()
    local page = lvgl.page({
        title = widget.name,
        subtitle = "Settings - " .. widget.options.Name,
        back = (function() askClose(); end),
    });
    local uit = {
        {type = "box", flexFlow = lvgl.FLOW_COLUMN, children = createSettings() }
    };
    widget.ui = page:build(uit);
end

function widget.globalsPage() 
    local page = lvgl.page({
        title = widget.name,
        subtitle = "Global - " .. widget.options.Name,
        back = (function() askClose(); end),
    });
    local uit = {
        {type = "box", flexFlow = lvgl.FLOW_COLUMN, children = {
            {type = "box", flexFlow = lvgl.FLOW_ROW, children = {
                {type = "label", text = "Number of Sliders: "},
                {type = "numberEdit", min = 1, max = 8, w = 40, 
                        get = (function() return settings.numberOfSliders; end), 
                        set = (function(v) 
                            for i = 1, settings.numberOfSliders do
                                activateVirtualInput(settings.sliders[i].vin, false);
                                settings.sliders[i] = nil;
                            end
                            settings.numberOfSliders = v;
                            for i = 1, settings.numberOfSliders do
                                resetSlider(i);
                                activateVirtualInput(settings.sliders[i].vin, true);
                                settings.sliders[i].width = widget.zone.w / settings.numberOfSliders;
                            end
                        end) } 
                }
            },
            {type = "box", flexFlow = lvgl.FLOW_ROW, children = {
                {type = "label", text = "Number of buttons: "},
                {type = "numberEdit", min = 1, max = 64, w = 40, 
                        get = (function() return settings.numberOfButtons; end), 
                        set = (function(v) 
                            for i = 1, settings.numberOfButtons do
                                activateVirtualSwitch(settings.buttons[i].vs, false);
                                settings.buttons[i] = nil;
                            end
                            settings.numberOfButtons = v;
                            for i = 1, settings.numberOfButtons do
                                resetButton(i);
                                activateVirtualSwitch(settings.buttons[i].vs, true);
                            end
                        end) } 
                }
            },
            {type = "button", text = "Reset all Settings", press = (function() resetSettings() end)},
            {type = "hline", w = 100, h = 1},
            {type = "box", flexFlow = lvgl.FLOW_ROW, children = {
                {type = "button", text = "Controls", press = (function() saveSettings(); widget.controlPage(); end) },
                {type = "button", text = "Settings", press = (function() saveSettings(); widget.settingsPage(); end) }
            }}
            }
        }
    };
    widget.ui = page:build(uit);
end

function widget.widgetPage()
    lvgl.clear();
    widget.ui = lvgl.build({
        { type = "box", flexFlow = lvgl.FLOW_COLUMN, children = {
            { type = "label", text = "LVGL Controls", w = widget.zone.x, align = CENTER},
            { type = "label", text = widget.options.Name, w = widget.zone.x, align = CENTER },
        }
        }
    });
end

local function isValidSettingsTable(t) 
    if (t.version ~= nil) then
        print("valied:", t.version);
        if (t.version == settingsVersion) then
            return true;
        end
    end
    return false;
end

local initialized = false;
function widget.update()
    if (not initialized) then
        local st = serialize.load(settingsFilename);
        if (st ~= nil) then
            if (isValidSettingsTable(st)) then
                settings = st;
            else
                resetSettings();
            end
        end
        for i = 1, settings.numberOfSliders do
            state.values[i] = 0;
            activateVirtualInput(settings.sliders[i].vin, true);
        end
        for i = 1, settings.numberOfButtons do
            activateVirtualSwitch(settings.buttons[i].vs, true);
        end
        initialized = true;
    end
    if lvgl.isFullScreen() then
        widget.controlPage();
    else
        widget.widgetPage();
    end
    saveSettings();
end

function widget.background()
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
