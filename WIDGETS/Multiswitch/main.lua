local name = "Multiswitch"
local libGUI

function loadGUI()
  if not libGUI then
  	libGUI = loadScript("/WIDGETS/LibGUI/libgui.lua")
  end
  
  return libGUI()
end

local function create(zone, options)
  local cf = loadScript("/WIDGETS/" .. name .. "/" .. model.getInfo().name .. ".lua");
  local config = nil;
  if (cf) then
    config = cf();
  end
  return loadScript("/WIDGETS/" .. name .. "/buttons.lua")(zone, options, config);
end

local function refresh(widget, event, touchState)
  widget.refresh(event, touchState)
end

local function background(widget)
  widget.background();
end

local options = {
  {"Address", VALUE, 0, 0, 255};
}

local function update(widget, options)
  print("Update1", options);
  widget.options = options;
  widget.update();
end

return {
  name = name,
  create = create,
  refresh = refresh,
  background = background,
  options = options,
  update = update
}