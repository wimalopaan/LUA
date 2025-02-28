local name = "HwExt/L"
local longname = "HwExt/L"

local function create(zone, options, dir)
    if (dir == nil) then
        dir = "/WIDGETS/lvglHwExt/";
    end
    return loadScript(dir .. "ui.lua")(zone, options, longname, dir);
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
    {"Name", STRING, "Pult"}
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
