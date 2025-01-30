local name = "LVGLContr"
local longname = "LVGL-Controls"
local dir = "lvglControls"

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
    {"Name", STRING, "Sliders"}
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
