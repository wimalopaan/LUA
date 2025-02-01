local name = "MultiSw-EL"
local longname = "MultiSwitch-E/L"
local dir = "lvglMultiSw"

local function create(zone, options, id)
    return loadScript("/WIDGETS/" .. dir .. "/ui.lua")(zone, options, longname, dir, id);
end

local function refresh(widget, event, touchState)
    widget.refresh(event, touchState)
end

local function background(widget)
    if (lvgl == nil) then 
        return;
    end
    widget.background();
end

local options = {
    { "Address",  VALUE, 0, 0, 255 },
    { "Intervall",  VALUE, 100, 10, 100 },
    { "Autoconf", BOOL,  0 },
--    { "File", FILE, model.getInfo().name .. ".lua", "/WIDGETS/" .. dir};
}
  
local function update(widget, options)
    widget.options = options;
    if (lvgl == nil) then 
        return;
    end
    widget.update();
end

return {
    useLvgl = true,
    name = name,
    create = create,
    refresh = refresh,
    background = background,
    options = options,
    update = update
}
