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

--[[
For CRSF_COMMAND the extended address (CRSF_ADDRESS_CONTROLLER) isn't really neccessary (but must be valid in th epacket)
All MultiSwitc-E8 grab the CRSF-COMMAND packets corresponding their realm CRSF_REALM_SWITCH, sub-command CRSF_SUBCMD_SWITCH_SET and 
their (logical) address (0..255)
--]]

local function sendData()
  print("senddata adr:", widget.options.Address);
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
--print("callback 1: ", item.title, item.value, item.id, state, widget.options.Address);
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
  print("callback 2: ", item.title, item.value, item.id, state, widget.options.Address);
  sendData();
end

local function buildButton(name, col, row, id, bt) 
--  print("buildbutton: ", name, col, row, id, bt);
  local b = nil;
  if (bt == "t") then
    b = gui.toggleButton(col, TOP + row * ROW, WIDTH, HEIGHT, name, false, callback);
  elseif (bt == "m") then
    b = gui.button(col, TOP + row * ROW, WIDTH, HEIGHT, name, callback);

    function b.onEvent(event, touchState)
      if (event == EVT_TOUCH_FIRST) then
        gui.editing = true;
        b.value = true;
        return b.callBack(b);
      end
      if (event == EVT_TOUCH_RELEASE) then
        gui.editing = false;
        b.value = false;
        return b.callBack(b);
      end
    end

    function b.draw(focused)
      local x = col;
      local y = TOP + row * ROW;
      local w = WIDTH;
      local h = HEIGHT;
      local fg = libGUI.colors.primary2
      local bg = libGUI.colors.focus

      if b.value then
          fg = libGUI.colors.primary3
          bg = libGUI.colors.active
          border = libGUI.colors.focus
      end

      lcd.drawFilledRectangle(x, y, w, h, bg)
      lcd.drawText(x + w / 2, y + h / 2, b.title, bit32.bor(fg, b.flags))

      if b.disabled then
          lcd.drawFilledRectangle(x, y, w, h, GREY, 7)
      end
  end

  end
  b.id = id;
  return b;
end

local buttons = {};

local function create() 
  if not(buttons) then
    buttons = {};
  end
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
local timeout = 100; -- in 10ms steps

function widget.background()
  readLS();
  local t = getTime();
  if ((t - lastTimeCalled) > timeout) then 
    lastTimeCalled = t;
    sendData();
--    print("bg", model.getInfo().name, widget.options.Address, config.buttons[widget.options.Address].name);
  end
end

function widget.refresh(event, touchState)
--  print("refresh e:", event, touchState);
  widget.background();
  if (event) then
    fullScreenRefresh(event, touchState)
  else 
    widgetRefresh();
  end
end

-- todo: 
-- type of button (does not reveive the EVT_VIRTUAL_EXIT ???), needs PR 5585
-- color of button
-- timeout value
function widget.update()
  ls = {};
  lsState = {};
  gui = libGUI.newGUI()
  
  if not(config) then
    print("Error: no Config")
    config = {};
    config.buttons = {};
  end
  if not(config.buttons[widget.options.Address]) then
    config.buttons[widget.options.Address] = {};
  end
  if not(config.buttons[widget.options.Address].name) then
    config.buttons[widget.options.Address].name ="-";
  else
    if not(type(config.buttons[widget.options.Address].name) == "string") then
      config.buttons[widget.options.Address].name ="-";
    end
  end

  if (config.global) then
    if (config.global.intervall and (config.global.intervall >= 10)) then
      timeout = config.global.intervall / 10;
    end      
  end

  timeout = timeout + widget.options.Address; -- each different timeout

  for row = 1, 8 do
    local bname = "F" .. row;
    local btype = "t";
    if (config.buttons[widget.options.Address][row]) then
      if (config.buttons[widget.options.Address][row].name) then
        if (type(config.buttons[widget.options.Address][row].name) == "string") then
          bname = config.buttons[widget.options.Address][row].name;
        else
          bname = "E" .. row;
        end
      end

      if (config.buttons[widget.options.Address][row].ls) then
        ls[row] = config.buttons[widget.options.Address][row].ls;
      end

      local t = config.buttons[widget.options.Address][row].type;
      if (t) then
        if (type(t) == "string") then
          if (string.sub(t, 1, 1) == "m") then
            btype = "m";
          elseif (string.sub(t, 1, 1) == "t") then
            btype = "t";
          end
        end
      end
    end
    if (row < 5) then
      buttons[row] = buildButton(bname, COL1, row - 1, row, btype); 
    else
      buttons[row] = buildButton(bname, COL3, row - 1 - 4, row, btype); 
    end
  end

  --[[
  for row = 1, 8 do
    buttons[row].title = "F" .. row;
    if (config.buttons[widget.options.Address][row]) then
      if (config.buttons[widget.options.Address][row].name) then
        if (type(config.buttons[widget.options.Address][row].name) == "string") then
          buttons[row].title = config.buttons[widget.options.Address][row].name;
        else
          buttons[row].title = "E" .. row;
        end
      end
      if (config.buttons[widget.options.Address][row].ls) then
        ls[row] = config.buttons[widget.options.Address][row].ls;
      end
      if (config.buttons[widget.options.Address][row].type) then
        if (type(config.buttons[widget.options.Address][row].type) == "string") then
          local t = config.buttons[widget.options.Address][row].type;
          if (string.sub(t, 1, 1) == "m") then
            buttons[row].type = "m";
          end
          if (string.sub(t, 1, 1) == "t") then
            buttons[row].type = "t";
          end
        end
      end
    end
  end
--]]
end

--create();
widget.update();

return widget
