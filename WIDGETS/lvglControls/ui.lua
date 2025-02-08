local zone, options, name, dir, widget_id = ...
local widget = {}
widget.options = options;
widget.id = widget_id;
widget.zone = zone;
widget.name = name;

local serialize = loadScript("/WIDGETS/" .. dir .. "/tableser.lua")();

widget.ui = nil;

local settings = {};
local state = {};
local settingsFilename = "/WIDGETS/" .. dir .. "/" .. model.getInfo().name .. "_" .. widget.options.Name .. ".lua";

local function resetSettings()
    settings.version = settingsVersion;
    settings.numberOfSliders = 6;
    settings.sliders = {};
    state.values = {};
    for i = 1, 16 do
        settings.sliders[i] = { name = "VS" .. i, shm = i, vin = i, useShm = 0, width = (LCD_W - 20) / settings.numberOfSliders,
        color = COLOR_THEME_SECONDARY3, textColor = COLOR_THEME_PRIMARY3, font = 0 };
        state.values[i] = 0;
    end
end
resetSettings();

local function askClose()
    lvgl.confirm({title="Exit", message="Really exit?", confirm=(function() lvgl.exitFullScreen(); end) })
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
                                        print("set", settings.sliders[i].vin, v);
                                    end; 
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

local function createSettings()
    local children = {};
    for i = 1, settings.numberOfSliders do
        children[#children+1] = createSetting(i);        
    end
    children[#children+1] = {type = "hline", w = 100, h = 1};
    children[#children+1] = {type = "box", flexFlow = lvgl.FLOW_ROW, children = {
        {type = "button", text = "Controls", press = widget.controlPage},
        {type = "button", text = "Global", press = widget.globalsPage}
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
                        set = (function(v) settings.numberOfSliders = v;
                            for i = 1, settings.numberOfSliders do
                                settings.sliders[i].width = widget.zone.w / settings.numberOfSliders;
                            end
                        end) } 
                }
            },
            {type = "button", text = "Reset all Settings", press = (function() resetSettings() end)},
            {type = "hline", w = 100, h = 1},
            {type = "box", flexFlow = lvgl.FLOW_ROW, children = {
                {type = "button", text = "Controls", press = widget.controlPage },
                {type = "button", text = "Settings", press = widget.settingsPage }
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

local settingsVersion = 9;
local function isValidSettingsTable(t) 
    if (t.version ~= nil) then
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
        initialized = true;
    end
    if lvgl.isFullScreen() then
        widget.controlPage();
    else
        widget.widgetPage();
    end
    serialize.save(settings, settingsFilename);
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
