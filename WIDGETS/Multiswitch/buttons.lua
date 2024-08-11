local zone, options, config = ...
local widget = {}
widget.options = options;

CRSF_ADDRESS_CONTROLLER = 0xC8;
CRSF_ADDRESS_TRANSMITTER= 0xEA;
CRSF_ADDRESS_CC         = 0xA0; -- non-standard 
CRSF_ADDRESS_SWITCH     = 0xA1; -- non-standard

CRSF_FRAMETYPE_CMD      = 0x32;
-- following CRSF definitions are non-standard
CRSF_REALM_CC           = 0xA0; 
CRSF_REALM_SWITCH       = 0xA1; 
CRSF_SUBCMD_CC_ADATA    = 0x01;
CRSF_SUBCMD_CC_ACHUNK   = 0x02;
CRSF_SUBCMD_CC_ACHANNEL = 0x03;
CRSF_SUBCMD_SWITCH_SET  = 0x01;

local state = 0;

local function sendData()
  local payloadOut = { CRSF_ADDRESS_CONTROLLER, CRSF_ADDRESS_TRANSMITTER, CRSF_REALM_SWITCH, CRSF_SUBCMD_SWITCH_SET, widget.options.Address, state};
  crossfireTelemetryPush(CRSF_FRAMETYPE_CMD, payloadOut);
end

local WIDTH  = 180
local HEIGHT = 32
local COL1   = 20
local MID    = 480 / 2
local COL3   = MID + COL1
local TOP    = 32
local ROW    = (272 - TOP) / 4

local libGUI = loadGUI()
local gui = libGUI.newGUI()

local function callback(item)
--  print("callback 1: ", item.title, item.value, item.id, state, widget.options.Address);
  local id = item.id;
  if (id >= 8) then
    print("ERROR: wrong id:", id);
    return;
  end
  local v = item.value;
  if (type(item.value) == "boolean") then
    if (item.value) then
      v = 1;
    else
      v = 0;
    end
  end
  local mask = bit32.lshift(1, id);
  if (v == 0) then
    state = bit32.band(state, bit32.bnot(mask));
  else 
    state = bit32.bor(state, mask);
  end
--  print("callback 2: ", item.title, item.value, item.id, state, widget.options.Address);
  sendData();
end

local function buildButton(name, col, row, id) 
  local b = gui.toggleButton(col, TOP + row * ROW, WIDTH, HEIGHT, name, false, callback);
  b.id = id;
  return b;
end

local buttons = {};

local function create() 
  local name = "";
  for row = 0, 3 do
    buttons[#buttons + 1] = buildButton(name, COL1, row, row);
  end
  for row = 0, 3 do
    buttons[#buttons + 1] = buildButton(name, COL3, row, row + 4);
  end
end

local function lsChanged(b, newValue) 
  print("lsChanged:", b, newValue);
  local button = buttons[b];
  if (button) then
    button.value = newValue;
    callback(button);
  else
    print("Error: no such button", b);
  end
end

local ls = {};
local lsState = {};

local function readLS() 
  for i, ls in ipairs(ls) do
    local lsname = "ls" .. ls;
    local v = getValue(lsname);
--    print("readLS:", lsname, v);
    if (lsState[i] ~= v) then
      lsState[i] = v;
      lsChanged(i, v > 0 and true or false);
    end
  end
end

local function widgetRefresh()
  lcd.drawText(zone.w / 2, zone.h / 2, "MultiSwitch", DBLSIZE + CENTER + VCENTER + libGUI.colors.primary3);
  if (config.buttons[widget.options.Address].name) then
    lcd.drawText(zone.w / 2, zone.h / 2 + 20, config.buttons[widget.options.Address].name .. "@" .. widget.options.Address, CENTER + VCENTER + libGUI.colors.primary3);
  end
end

local function fullScreenRefresh(event, touchState)
  lcd.drawText(MID, TOP / 2, config.buttons[widget.options.Address].name .. "@" .. widget.options.Address, CENTER + VCENTER + libGUI.colors.primary3);
  gui.run(event, touchState)
end

local lastTimeCalled = getTime();

function widget.background()
  readLS();
  local t = getTime();
  if ((t - lastTimeCalled) > 100) then 
    lastTimeCalled = t;
    sendData();
--    print("bg", model.getInfo().name, widget.options.Address, config.buttons[widget.options.Address].name);
  end
end

function widget.refresh(event, touchState)
  widget.background();
  if (event) then
    fullScreenRefresh(event, touchState)
  else 
    widgetRefresh();
  end
end

-- todo: 
-- type of button
-- color of button
function widget.update()
  ls = {};
  lsState = {};
  if not(config.buttons[widget.options.Address]) then
    config.buttons[widget.options.Address] = {};
  end
  if not(config.buttons[widget.options.Address].name) then
    config.buttons[widget.options.Address].name ="-";
  end
  for row = 1, 8 do
    buttons[row].title = "F" .. row;
    if (config.buttons[widget.options.Address][row]) then
      if (config.buttons[widget.options.Address][row].name) then
        buttons[row].title = config.buttons[widget.options.Address][row].name;
      end
      if (config.buttons[widget.options.Address][row].ls) then
        ls[row] = config.buttons[widget.options.Address][row].ls;
      end
    end
  end
end

create();
widget.update();

return widget
