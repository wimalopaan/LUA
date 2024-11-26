local zone, options, config = ...
local widget                = {}
widget.options              = options;

CRSF_ADDRESS_CONTROLLER     = 0xC8;
CRSF_ADDRESS_TRANSMITTER    = 0xEA;
CRSF_ADDRESS_CC             = 0xA0; -- non-standard
CRSF_ADDRESS_SWITCH         = 0xA1; -- non-standard

CRSF_FRAMETYPE_CMD          = 0x32;
-- following CRSF definitions are non-standard
CRSF_REALM_CC               = 0xA0;
CRSF_REALM_SWITCH           = 0xA1;
CRSF_SUBCMD_CC_ADATA        = 0x01;
CRSF_SUBCMD_CC_ACHUNK       = 0x02;
CRSF_SUBCMD_CC_ACHANNEL     = 0x03;
CRSF_SUBCMD_SWITCH_SET      = 0x01;
CRSF_SUBCMD_PROP_SET        = 0x02;

local state                 = 0;

--[[
For CRSF_COMMAND the extended address (CRSF_ADDRESS_CONTROLLER) isn't really neccessary (but must be valid in th epacket)
All MultiSwitc-E8 grab the CRSF-COMMAND packets corresponding their realm CRSF_REALM_SWITCH, sub-command CRSF_SUBCMD_SWITCH_SET and
their (logical) address (0..255)
--]]

--[[
* To use momentary switches EdgeTx PR5585 is needed.
* ExpressLRS PR2941 is needed to use config-menu for more than one MultiSwitch-E at a time
--]]

local function sendData()
  print("senddata adr:", widget.options.Address, state);
  local payloadOut = { CRSF_ADDRESS_CONTROLLER, CRSF_ADDRESS_TRANSMITTER, CRSF_REALM_SWITCH, CRSF_SUBCMD_SWITCH_SET,
    widget.options.Address, state };
  crossfireTelemetryPush(CRSF_FRAMETYPE_CMD, payloadOut);
end
local function sendProp(channel, value)
  print("sendprop adr:", widget.options.Address, channel, value);
  local payloadOut = { CRSF_ADDRESS_CONTROLLER, CRSF_ADDRESS_TRANSMITTER, CRSF_REALM_SWITCH, CRSF_SUBCMD_PROP_SET, widget
      .options.Address, channel, value };
  crossfireTelemetryPush(CRSF_FRAMETYPE_CMD, payloadOut);
end

local WIDTH  = 180
local WLEFT  = WIDTH / 20
local HEIGHT = 32
local COL1   = 20
local MID    = 480 / 2
local COL3   = MID + COL1
local TOP    = 32
local ROW    = (272 - TOP) / 4

local libGUI = loadGUI()
local gui    = {};

local function initGUI()
  local gui = libGUI.newGUI();

  function gui.toggleButton(x, y, w, h, title, help, value, callBack, flags)
    local self = {
      title = title,
      help = help,
      value = value,
      callBack = callBack or _.doNothing,
      flags = bit32.bor(flags or libGUI.flags, CENTER, VCENTER),
      disabled = false,
      hidden = false
    }

    function self.draw(focused)
      local fg = libGUI.colors.primary2
      local bg = libGUI.colors.focus
      local border = libGUI.colors.active

      if self.value then
        fg = libGUI.colors.primary3
        bg = libGUI.colors.active
        border = libGUI.colors.focus
      end

      gui.drawFilledRectangle(x, y, w, h, bg)
      gui.drawText(x + w / 2, y + h / 2, self.title, bit32.bor(fg, self.flags))
      gui.drawText(x + w - 30, y + h - 15, self.help, SMLSIZE + COLOR_THEME_SECONDARY3);
      gui.drawFilledRectangle(x, y, WLEFT, h, COLOR_THEME_SECONDARY1);

      if focused then
        gui.drawRectangle(x - 2, y - 2, w + 4, h + 4, border, 2)
      end

      if self.disabled then
        gui.drawFilledRectangle(x, y, w, h, GREY, 7)
      end
    end

    function self.onEvent(event, touchState)
      if event == EVT_VIRTUAL_ENTER then
        self.value = not self.value
        return self.callBack(self)
      end
    end

    gui.custom(self, x, y, w, h)

    return self
  end

  function gui.momentaryButton(x, y, w, h, title, help, callBack, flags)
    local self = {
      title = title,
      help = help,
      callBack = callBack or _.doNothing,
      flags = bit32.bor(flags or libGUI.flags, CENTER, VCENTER),
      disabled = false,
      hidden = false
    }

    function self.draw(focused)
      local fg = libGUI.colors.primary2
      local bg = libGUI.colors.focus
      local border = libGUI.colors.active

      if self.value then
        fg = libGUI.colors.primary3
        bg = libGUI.colors.active
        border = libGUI.colors.focus
      end

      gui.drawFilledRectangle(x, y, w, h, bg)
      gui.drawText(x + w / 2, y + h / 2, self.title, bit32.bor(fg, self.flags))
      gui.drawText(x + w - 30, y + h - 15, self.help, SMLSIZE + COLOR_THEME_SECONDARY3);
      gui.drawFilledTriangle(x, y, x + WLEFT, y + h / 2, x, y + h, COLOR_THEME_WARNING)

      if focused then
        gui.drawRectangle(x - 2, y - 2, w + 4, h + 4, border, 2)
      end

      if self.disabled then
        gui.drawFilledRectangle(x, y, w, h, GREY, 7)
      end
    end

    function self.onEvent(event, touchState)
      if (event == EVT_TOUCH_FIRST) then
        if (self.covers(touchState.x, touchState.y)) then
          gui.editing = true;
          self.value = true;
          return self.callBack(self);
        end
      elseif (event == EVT_VIRTUAL_ENTER_LONG) then
        gui.editing = true;
        self.value = true;
        return self.callBack(self);
      elseif (event == EVT_TOUCH_BREAK) or (event == EVT_VIRTUAL_EXIT) then
        gui.editing = false;
        self.value = false;
        return self.callBack(self);
      end
    end

    gui.custom(self, x, y, w, h)

    return self
  end

  function gui.horizontalSlider(x, y, w, h, value, min, max, delta, callBack, name)
    local self = {
      value = value,
      min = min,
      max = max,
      delta = delta,
      callBack = callBack or _.doNothing,
      disabled = false,
      hidden = false,
      editable = true,
      title = name
    }

    function self.draw(focused)
      local ys = y + h / 2;

      local xdot = x + w * (self.value - self.min) / (self.max - self.min)

      local colorBar = libGUI.colors.primary3
      local colorDot = libGUI.colors.primary2
      local colorDotBorder = libGUI.colors.primary3

      if focused then
        colorDotBorder = libGUI.colors.active
        if gui.editing then
          colorBar = libGUI.colors.primary1
          colorDot = libGUI.colors.edit
        end
      end

      gui.drawFilledRectangle(x, ys - 2, w, 5, colorBar)
      gui.drawFilledCircle(xdot, ys, libGUI.SLIDER_DOT_RADIUS, colorDot)
      for i = -1, 1 do
        gui.drawCircle(xdot, ys, libGUI.SLIDER_DOT_RADIUS + i, colorDotBorder)
      end
      gui.drawRectangle(x, y, w, h, COLOR_THEME_SECONDARY2);
      if (self.title) then
        gui.drawText(x + w / 2, y + h / 2 + 6, self.title, SMLSIZE + CENTER);
      end
    end

    function self.onEvent(event, touchState)
      local v0 = self.value

      if gui.editing then
        if libGUI.match(event, EVT_VIRTUAL_ENTER, EVT_VIRTUAL_EXIT) then
          gui.editing = false
        elseif event == EVT_VIRTUAL_INC then
          self.value = math.min(self.max, self.value + self.delta)
        elseif event == EVT_VIRTUAL_DEC then
          self.value = math.max(self.min, self.value - self.delta)
        end
      elseif event == EVT_VIRTUAL_ENTER then
        gui.editing = true
      end

      if event == EVT_TOUCH_SLIDE then
        local value = self.min + (self.max - self.min) * (touchState.x - x) / w
        value = math.min(self.max, value)
        value = math.max(self.min, value)
        self.value = self.min + self.delta * math.floor((value - self.min) / self.delta + 0.5)
      end

      if v0 ~= self.value then
        self.callBack(self)
      end
    end

    gui.custom(self, x, y, w, h)

    return self
  end

  return gui;
end

local function callbackSlider(item)
  --print("callbackSlider: ", item.title, item.value, item.id, widget.options.Address);
  sendProp(item.id, item.value);
end

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

local sliderPrompt = libGUI.newGUI();
local sly = 50;
function sliderPrompt.fullScreenRefresh()
  lcd.drawFilledRectangle(20, sly + 30, LCD_W - 40, 30, COLOR_THEME_SECONDARY1)
  lcd.drawFilledRectangle(20, sly + 60, LCD_W - 40, 100, libGUI.colors.primary2)
  lcd.drawRectangle(20, sly + 30, LCD_W - 40, 130, libGUI.colors.primary1, 2)
  lcd.drawText(40, sly + 45, sliderPrompt.item.title, VCENTER + MIDSIZE + libGUI.colors.primary2);
end

-- Make a dismiss button from a custom element
local custom2 = sliderPrompt.custom({}, LCD_W - 45, sly + 36, 20, 20)
local promptSlider = sliderPrompt.horizontalSlider(30, sly + 100, LCD_W - 60, 0, 0, 99, 1, function(s)
  sliderPrompt.item.value = s.value;
  callbackSlider(sliderPrompt.item);
end);
function custom2.draw(focused)
  lcd.drawRectangle(LCD_W - 45, sly + 36, 20, 20, libGUI.colors.primary2)
  lcd.drawText(LCD_W - 35, sly + 45, "X", MIDSIZE + CENTER + VCENTER + libGUI.colors.primary2)
end

function custom2.onEvent(event, touchState)
  if event == EVT_VIRTUAL_ENTER then
    gui.dismissPrompt()
  end
end

local function buildButton(name, col, row, id, bt, help, options)
  --  print("buildbutton: ", name, col, row, id, bt);
  local b = nil;
  if (bt == "t") then
    b = gui.toggleButton(col, TOP + row * ROW, WIDTH, HEIGHT, name, help, false, callback);
  elseif (bt == "m") then
    b = gui.momentaryButton(col, TOP + row * ROW, WIDTH, HEIGHT, name, help, callback);
  elseif (bt == "s") then
    b = gui.horizontalSlider(col, TOP + row * ROW, WIDTH, HEIGHT, 0, 0, 99, 1, callbackSlider, name);
    if (options and (bit32.band(options, 0x01) == 0x01)) then
      function b.onEvent(event, touchState)
        sliderPrompt.item = b;
        promptSlider.value = b.value;
        gui.showPrompt(sliderPrompt);
      end
    end
  end
  b.id = id;
  return b;
end

local buttons = {};

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
    local lsw = model.getLogicalSwitch(ls - 1);
    if ((lsw ~= nil) and (lsw.func ~= LS_FUNC_NONE)) then -- bug in EdgeTx???
      local lsname = "ls" .. ls;
      local v = getValue(lsname);
      print("readLS:", lsname, v, lsw);
      if (lsState[i] ~= v) then
        lsState[i] = v;
        lsChanged(i, v > 0 and true or false);
      end
    end
  end
end

local function widgetRefresh()
  lcd.drawText(zone.w / 2, zone.h / 2, "MultiSwitch", DBLSIZE + CENTER + VCENTER + libGUI.colors.primary3);
  if (config.buttons[widget.options.Address]) then
    if (config.buttons[widget.options.Address].name) then
      lcd.drawText(zone.w / 2, zone.h / 2 + 20,
        config.buttons[widget.options.Address].name .. "@" .. widget.options.Address,
        CENTER + VCENTER + libGUI.colors.primary3);
    end      
  end
end

local function fullScreenRefresh(event, touchState)
  lcd.drawText(MID, TOP / 2, config.buttons[widget.options.Address].name .. "@" .. widget.options.Address,
    CENTER + VCENTER + libGUI.colors.primary1);
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
local lo = nil;
local address = 0;
function widget.update()
  print("update")
  print("file:", widget.options.File)
  -- update() is called if user changes options OR if zone changes (switch from full-screen to app-mode)
  -- if only zone changes, option table ref remains same (2.11, previous?)
  if (lo == widget.options) then
    print("ref:", lo);
    if (widget.options.Address == address) then
      print("adr: ", address);
      return;
    end      
  end
  address = widget.options.Address;
  lo = widget.options;
  print("update lo")

  ls = {};
  lsState = {};
  gui = initGUI();

  if not (config) then
    print("Error: no Config")
    config = {};
    config.buttons = {};
  end
  if not (config.buttons[widget.options.Address]) then
    config.buttons[widget.options.Address] = {};
  end
  if not (config.buttons[widget.options.Address].name) then
    config.buttons[widget.options.Address].name = "-";
  else
    if not (type(config.buttons[widget.options.Address].name) == "string") then
      config.buttons[widget.options.Address].name = "-";
    end
  end

  if (config.global) then
    if (config.global.intervall and (config.global.intervall >= 10)) then
      timeout = config.global.intervall / 10;
    end
  end

  timeout = timeout + widget.options.Address; -- each different timeout
  print("update: timeout:", timeout);

  for row = 1, 8 do
    local bname = "F" .. row;
    local btype = "t";
    local o = nil;
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
          elseif (string.sub(t, 1, 1) == "s") then
            btype = "s";
            ls[row] = nil;
          end
        end
      end
      o = config.buttons[widget.options.Address][row].options;
    end
    local htext = "-";
    if (ls[row]) then
      htext = "LS" .. ls[row];
    end
    print("Button", bname, htext);
    if (row < 5) then
      buttons[row] = buildButton(bname, COL1, row - 1, row - 1, btype, htext, o);
    else
      buttons[row] = buildButton(bname, COL3, row - 1 - 4, row - 1, btype, htext, o);
    end
  end
end

--create();
widget.update();

return widget
