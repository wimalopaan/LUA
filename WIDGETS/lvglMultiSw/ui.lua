-- todo
-- autoconf fsm
-- control page: column width
-- global page: nicer (rectangle for line heigth and column width, columns)

local zone, options, name, dir, widget_id = ...
local widget = {}
widget.options = options;
widget.id = widget_id;
widget.zone = zone;
widget.name = name;

local serialize = loadScript("/WIDGETS/" .. dir .. "/tableser.lua")();
local util      = loadScript("/WIDGETS/" .. dir .. "/util.lua")();

local PAGE_CONTROL  = 1;
local PAGE_SETTINGS = 2;
local PAGE_GLOBALS  = 3;

widget.ui = nil;
widget.activePage = PAGE_CONTROL;

local TYPE_BUTTON    = 1;
local TYPE_TOGGLE    = 2;
local TYPE_3POS      = 3;
local TYPE_MOMENTARY = 4;
local TYPE_SLIDER    = 5;

local settings = {}
local state = {};

local crsf  = loadScript("/WIDGETS/" .. dir .. "/crsf.lua")(state, widget, widget_id, dir);
local fsm   = loadScript("/WIDGETS/" .. dir .. "/fsm.lua")(crsf);

local settingsVersion = 5;
local function resetSettings() 
--    print("reset settings")
    settings.version = settingsVersion;
    settings.name = "Beleuchtung";
    settings.line_height = 45;
    settings.momentaryButton_radius = 20;
    settings.buttons = {};
    state.buttons = {};
    for i = 1, 8 do
        settings.buttons[i] = {name = "Output " .. i, type = TYPE_BUTTON, switch = 0, source = 0, visible = 1, 
                                color = COLOR_THEME_SECONDARY3, textColor = COLOR_THEME_PRIMARY3, font = 0 };
        state.buttons[i] = { value = 0 };
    end
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
local settingsFilename = "/WIDGETS/" .. dir .. "/" .. model.getInfo().name .. "_" .. widget.options.Address .. ".lua";

local function bool2int(v)
    if (v) then return 1; end
    return 0;
end

local function setButton(btnstate, v)
    if (v ~= nil) then
        local vv = bool2int(v);
        if (vv ~= btnstate.value) then
            btnstate.value = vv;
            fsm.update();
            return true;
        end
    end                    
    return false;
end

local function readPhysical() 
    for i, btn in ipairs(settings.buttons) do
        local btnstate = state.buttons[i];
        if (btn.type == TYPE_SLIDER) then
            if (btn.source > 0) then
             local v = getSourceValue(btn.source) / 10.24;
                if (v ~= nil) then
                    btnstate.value = v;
                end
            end
        else
            if (btn.switch > 0) then
                local v = getSwitchValue(btn.switch);
                if (setButton(btnstate, v)) then
                    if (widget.ui ~= nil) then
                        -- todo: caching ref
                        local b = widget.ui["b" .. i];
                        if (b ~= nil) then
                           b:set({checked = v});
                        end
                    end        
                end
            end
        end      
--        print("b", i, btnstate.value, btn.switch);
    end
end

function widget.switchPage(id)
--    print("switchUI", id);
    lvgl.clear()
    if (id == PAGE_CONTROL) then
        widget.controlPage()
    elseif (id == PAGE_SETTINGS) then
        widget.settingsPage()
    elseif (id == PAGE_GLOBALS) then
        widget.globalsPage()
    else
        print("unknown id:", id)
    end
    widget.activePage = id
    serialize.save(settings, settingsFilename);
end

local function invert(v) 
    if (v == 0) then
        return 1;
    else
        return 0;
    end    
end

local function createButton(i, width)
    if (settings.buttons[i].type == TYPE_BUTTON) then
        return { type = "button", name = "b" .. i, text = settings.buttons[i].name, w = width, h = settings.line_height, 
                 color = settings.buttons[i].color, textColor = settings.buttons[i].textColor, font = settings.buttons[i].font,
                 press = (function() state.buttons[i].value = invert(state.buttons[i].value); fsm.update(); return state.buttons[i].value; end),
                 active = (function() if (settings.buttons[i].switch > 0) then return false; else return true; end; end)
            };
    elseif (settings.buttons[i].type == TYPE_MOMENTARY) then
        return { type = "momentaryButton", text = settings.buttons[i].name, w = width, h = settings.line_height, cornerRadius = settings.momentaryButton_radius, -- color = COLOR_THEME_SECONDARY2,
        press = (function() state.buttons[i].value = 1; fsm.update(); end),
        release = (function() state.buttons[i].value = 0; fsm.update(); end),
        active = (function() if (settings.buttons[i].switch > 0) then return false; else return true; end; end)
    };
    elseif (settings.buttons[i].type == TYPE_3POS) then
        return {type = "box", flexFlow = lvgl.FLOW_ROW, children = {
            { type = "label", text = settings.buttons[i].name, w = width / 2 },
            { type = "slider", min = -1, max = 1, 
                                get = (function() local v = state.buttons[i].value; if (v <= 1) then return v; else return -1; end; end), 
                                set = (function(v) if (v == -1) then state.buttons[i].value = 2; else state.buttons[i].value = v; end; fsm.update(); end), 
                                w = width / 2 }
        }};
    elseif (settings.buttons[i].type == TYPE_TOGGLE) then
        return {type = "box", flexFlow = lvgl.FLOW_ROW, children = {
            { type = "label", text = settings.buttons[i].name, w = width / 2 },
            { type = "toggle", get = (function() if (state.buttons[i].value ~= 0) then return 1; else return 0; end; end), 
                               set = (function(v) state.buttons[i].value = v; fsm.update(); end), w = width / 2 ,
                               active = (function() if (settings.buttons[i].switch > 0) then return false; else return true; end; end) }
        }};
    elseif (settings.buttons[i].type == TYPE_SLIDER) then
        return {type = "box", flexFlow = lvgl.FLOW_ROW, children = {
            { type = "label", text = settings.buttons[i].name, w = width / 3, color = COLOR_THEME_PRIMARY3},
            { type = "slider", min = -100, max = 100, get = (function() return state.buttons[i].value; end),
                                                      set = (function(v) state.buttons[i].value = v; crsf.sendProp(i, v); end), w = (2 * width) / 3,
                                                      active = (function() if (settings.buttons[i].source > 0) then return false; else return true; end; end)
                                                    }
        }};
    end
end

local function askClose()
    lvgl.confirm({title="Exit", message="Really exit?", confirm=(function() lvgl.exitFullScreen(); end) })
end
  

function widget.globalsPage() 
    local page = lvgl.page({
        title = widget.name .. "@" .. widget.options.Address .. " : " .. settings.name ,
        subtitle = "Global-Settings",
        back = (function() askClose(); end),
    });
    local uit = {{
            type = "box",
            w = widget.zone.w, 
            flexFlow = lvgl.FLOW_COLUMN,
            children = {
                {type = "box", flexFlow = lvgl.FLOW_ROW, flexPad = lvgl.PAD_LARGE, children = {
                    {type = "label", text = "Name: "},
                    {type = "textEdit", value = settings.name, w = 150, maxLen = 16, set = (function(s) settings.name = s; end) } 
                }
                },
                {type = "box", flexFlow = lvgl.FLOW_ROW, flexPad = lvgl.PAD_LARGE, children = {
                    {type = "label", text = "Line Height: "},
                    {type = "numberEdit", min = 30, max = 60, w = 40, get = (function() return settings.line_height; end), set = (function(v) settings.line_height = v; end) } 
                }
                },
                {type = "box", flexFlow = lvgl.FLOW_ROW, flexPad = lvgl.PAD_LARGE, children = {
                    {type = "label", text = "Radius momentary Button: "},
                    {type = "numberEdit", min = 10, max = 30, w = 40, get = (function() return settings.momentaryButton_radius; end), set = (function(v) settings.momentaryButton_radius = v; end) } 
                }
                },
                {type = "button", text = "Reset all Settings", press = (function() resetSettings() end)},
                { type = "hline", w = widget.zone.w / 2, h = 1 },
                { type = "box", flexFlow = lvgl.FLOW_ROW, children = {
                        {type = "button", text = "Settings", press = (function() widget.switchPage(PAGE_SETTINGS); end)},
                        {type = "button", text = "Control", press = (function() widget.switchPage(PAGE_CONTROL); end)} }
                }                        
            }}};
    widget.ui = page:build(uit);
end

function widget.controlPage()
--    print("controlPage");
    local page = lvgl.page({
        title = widget.name .. "@" .. widget.options.Address .. " : " ..settings.name ,
        subtitle = "Control",
        back = (function() askClose(); end),
    });

    local column_width = widget.zone.w / 2 - 10;
    local button_width = widget.zone.w / 2 - 40;

    local children1 = {};
    local children2 = {};
    for index, btn in ipairs(settings.buttons) do
        if (btn.visible > 0) then
            if (#children1 < 4) then
                children1[#children1+1] = createButton(index, button_width);
            else
                children2[#children2+1] = createButton(index, button_width);
            end
        end        
    end

    local uit = {{ type = "box", flexFlow = lvgl.FLOW_COLUMN, children = {
        { type = "box",
            flexFlow = lvgl.FLOW_ROW,
            children = { {
                    type = "box",
                    w = column_width,
                    flexFlow = lvgl.FLOW_COLUMN,
                    flexPad = lvgl.PAD_LARGE,
                    children = children1,
                }, {
                    type = "box",
                    w = column_width,
                    flexFlow = lvgl.FLOW_COLUMN,
                    flexPad = lvgl.PAD_LARGE,
                    children = children2,
                },
            }
        },
        { type = "hline", w = widget.zone.w / 2, h = 1 },
        { type = "box", flexFlow = lvgl.FLOW_ROW, children = {
                {type = "button", text = "Settings", press = (function() widget.switchPage(PAGE_SETTINGS); end)},
                {type = "button", text = "Global", press = (function() widget.switchPage(PAGE_GLOBALS); end)} }
        }
    }}};
    widget.ui = page:build(uit);
end

local function createSettingsRow(i, edit_width, maxLen)
    return {
        type = "box",
        flexFlow = lvgl.FLOW_ROW,
        children = {
            { type = "label", text = "Output " .. i, font = BOLD },
            { type = "label", text = " Name:"},
            { type = "textEdit", value = settings.buttons[i].name, w = edit_width, maxLen = maxLen, set = (function(s) settings.buttons[i].name = s; end) },
            { type = "label", text = " Visible:" },
            { type = "toggle", get = (function() return settings.buttons[i].visible; end),
                               set = (function(v) settings.buttons[i].visible = v; end) },
            { type = "label", text = " Type:" },
            { type = "choice", title = "Type", values = {"Button", "Toggle", "3-Pos", "Momentary", "Slider"}, get = (function() return settings.buttons[i].type; end), set = (function(t) settings.buttons[i].type = t; end) }, 
            { type = "label", text = " Switch:" },
            { type = "switch", filter = lvgl.SW_SWITCH | lvgl.SW_TRIM | lvgl.SW_LOGICAL_SWITCH, active = (function() if (settings.buttons[i].type == TYPE_SLIDER) then return false; else return true; end; end), get = (function() return settings.buttons[i].switch; end), set = (function(s) settings.buttons[i].switch = s; end) },
            { type = "label", text = " Source:" },
            { type = "source", active = (function() if (settings.buttons[i].type ~= TYPE_SLIDER) then return false; else return true; end; end), 
                               get = (function() return settings.buttons[i].source; end), 
                               set = (function(s) settings.buttons[i].source = s; end) },
            { type = "label", text = " Color:" },
            { type = "color", get = (function() return settings.buttons[i].color; end),
                              set = (function(v) settings.buttons[i].color = v; end) },
            { type = "label", text = " TextColor:" },
            { type = "color", get = (function() return settings.buttons[i].textColor; end),
                              set = (function(v) settings.buttons[i].textColor = v; end) },                                     
            { type = "label", text = " Font:" },
            { type = "font", get = (function() return settings.buttons[i].font; end),
                            set = (function(v) settings.buttons[i].font = v; end) },                                     
        }
    };
end

local function createSettingsRows(edit_width, maxLen)
    local children = {};
    for i = 1, 8 do
        children[i] = createSettingsRow(i, edit_width, maxLen);
    end
    return children;
end

function widget.settingsPage()
--    print("settingsPage");
    local page = lvgl.page({
        title = widget.name .. "@" .. widget.options.Address .. " : " ..settings.name ,
        subtitle = "Function-Settings",
        back = (function() askClose(); end),
    });
    local edit_width = widget.zone.w / 2 - 120;
    local maxLen = 16;
    local uit = { {
            type = "box",
            flexFlow = lvgl.FLOW_COLUMN,
            flexPad = lvgl.PAD_LARGE,
            children = createSettingsRows(edit_width, maxLen);
         }
    };
    uit[1].children[#uit[1].children + 1] = { type = "hline", w = widget.zone.w / 2, h = 1 };
    uit[1].children[#uit[1].children + 1] = { type = "box", flexFlow = lvgl.FLOW_ROW, children = {
            {type = "button", text = "Control", press = (function() widget.switchPage(PAGE_CONTROL); end)},
            {type = "button", text = "Global", press = (function() widget.switchPage(PAGE_GLOBALS); end)} }
        };
    widget.ui = page:build(uit);
end

function widget.widgetPage()
    lvgl.clear();
    widget.ui = lvgl.build({
        { type = "box", flexFlow = lvgl.FLOW_COLUMN, children = {
            { type = "label", text = widget.name, w = widget.zone.x, align = CENTER},
            { type = "label", text = settings.name .. "@" .. widget.options.Address, w = widget.zone.x, align = CENTER }, }
        }
    });
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
        widget.switchPage(PAGE_CONTROL);
    else
        widget.widgetPage();
    end
    serialize.save(settings, settingsFilename);
end

local function configItemCallback(item)
    print("configItemCallback:", item);
end 

function widget.background()
    fsm.tick(configItemCallback);
    readPhysical();
end

local function fullScreenRefresh()
end

function widget.refresh(event, touchState)
    --    print("refresh", widget.zone.x, widget.zone.y);
    if lvgl == nil then
        lcd.drawText(widget.zone.x, widget.zone.y, "Lvgl support required", COLOR_THEME_WARNING)
    end
    if (lvgl.isFullScreen()) then
        fullScreenRefresh();
    end
    widget.background();
end

return widget;
