local name = "HWExt"
local libGUI

function loadGUI()
  if not libGUI then
  	libGUI = loadScript("/WIDGETS/LibGUI/libgui.lua")
  end
  
  return libGUI()
end

local function create(zone, options)
--  local config = loadScript("/WIDGETS/" .. name .. "/" .. model.getInfo().name .. ".lua")();
  local config = {};
  return loadScript("/WIDGETS/" .. name .. "/hwext.lua")(zone, options, config);
end

local function refresh(widget, event, touchState)
  widget.refresh(event, touchState)
end

local function background(widget)
  widget.background();
end

local options = {
  {"Show", VALUE, 0, 0, 7}; -- Display switches of this controller
  {"C0LS1", VALUE, 50, 1, 64}; -- LS50, 51, 52, 53, 54, 55, 56, 57
  {"C1LS1", VALUE, 55, 1, 64}; -- LS55, 56, 57, 58, 59, 60, 61, 62 -- overlap!!!
  {"C2LS1", VALUE, 60, 1, 64};
  {"C3LS1", VALUE, 65, 1, 64};
  {"C4LS1", VALUE, 30, 1, 64};
  {"C5LS1", VALUE, 35, 1, 64};
  {"C6LS1", VALUE, 40, 1, 64};
  {"C7LS1", VALUE, 45, 1, 64};
  {"C1ShmV", VALUE, 1, 1, 16};
}

local function update(widget, options)
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