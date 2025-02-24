local name = "LVGLContr"
local longname = "LVGL-Controls"

-- local function featureTest() 
--     if (getVirtualSwitch ~= nil) then
--         return true;
--     end
--     return false;
-- end

local function create(zone, options, dir)
    print("create", dir)
    -- if (not featureTest()) then
    --     return {zone = zone, options = options, update = (function() end), background = (function() end), refresh = (function() end)};
    -- end
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
