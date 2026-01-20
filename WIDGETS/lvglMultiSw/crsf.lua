-- WM EdgeTx LUA 
-- Copyright (C) 2016 - 2026 Wilhelm Meier <wilhelm.wm.meier@googlemail.com>
--
-- This program is free software: you can redistribute it and/or modify
-- it under the terms of the GNU General Public License as published by
-- the Free Software Foundation, either version 3 of the License, or
-- (at your option) any later version.
--
-- This program is distributed in the hope that it will be useful,
-- but WITHOUT ANY WARRANTY; without even the implied warranty of
-- MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
-- GNU General Public License for more details.
--
-- You should have received a copy of the GNU General Public License
-- along with this program.  If not, see <http://www.gnu.org/licenses/>.
--

local state, widget, dir = ... 

local CRSF_ADDRESS_CONTROLLER     = 0xC8; 
local CRSF_ADDRESS_TRANSMITTER    = 0xEA;
local CRSF_ADDRESS_CC             = 0xA0; -- non-standard
local CRSF_ADDRESS_SWITCH         = 0xA1; -- non-standard

local CRSF_FRAMETYPE_CMD          = 0x32;
local CRSF_FRAMETYPE_PASSTHRU     = 0x7f;
local CRSF_FRAMETYPE_ARDUPILOT    = 0x80;

-- following CRSF definitions are non-standard
local CRSF_REALM_CC               = 0xA0;
local CRSF_REALM_SWITCH           = 0xA1;
local CRSF_REALM_SCHOTTEL         = 0xA2;
local CRSF_SUBCMD_CC_ADATA        = 0x01;
local CRSF_SUBCMD_CC_ACHUNK       = 0x02;
local CRSF_SUBCMD_CC_ACHANNEL     = 0x03;
local CRSF_SUBCMD_CC_ACHAN_EXT    = 0x04;
local CRSF_SUBCMD_SWITCH_SET      = 0x01; -- 2-state switches
local CRSF_SUBCMD_SWITCH_PROP_SET = 0x02;
local CRSF_SUBCMD_SWITCH_REQ_T    = 0x03;
local CRSF_SUBCMD_SWITCH_REQ_TI   = 0x04;
local CRSF_SUBCMD_SWITCH_REQ_CI   = 0x05; -- request config item
local CRSF_SUBCMD_SWITCH_REQ_DI   = 0x06; -- request device info
local CRSF_SUBCMD_SWITCH_SET4     = 0x07; -- 4-state switches (8 switches) 2bytes payload
local CRSF_SUBCMD_SWITCH_SET64    = 0x08; -- 64 x 4-state switches (8 groups of 8 switches) 3bytes payload
local CRSF_SUBCMD_SWITCH_SET4M    = 0x09; -- 4-state switches (8 switches) 2bytes payload, multiple addresses
local CRSF_SUBCMD_SWITCH_SETRGB   = 0x0a; 
local CRSF_SUBCMD_SWITCH_INTERMOD = 0x10; -- intermodule command
local CRSF_SUBCMD_SCHOTTEL_RESET  = 0x01;

local PASSTHRU_SUBTYPE_SWITCH     = 0xa1;
local PASSTHRU_APPID_STATUS       = 6100;

local ARDUPILOT_SCHOTTEL_APPID    = 6000;
local ARDUPILOT_SCHOTTEL_RESP_T   = 0x00;
local ARDUPILOT_SCHOTTEL_RESP_DI  = 0x01;

local ARDUPILOT_SWITCH_APPID      = 6010;
local ARDUPILOT_SWITCH_RESP_CI    = 0x00;
local ARDUPILOT_SWITCH_RESP_DI    = 0x01;

local setProtocolVersion = CRSF_SUBCMD_SWITCH_SET4;

local _, rv = getVersion()
if string.sub(rv, -5) == "-simu" then 
  local c = loadScript(dir .. "crsfserial.lua");
  if (c ~= nil) then
    --print("load crsf serial")
    local t = c();
    crossfireTelemetryPush = t.crossfireTelemetryPush;
    crossfireTelemetryPop  = t.crossfireTelemetryPop;
    crossfireTelemetryPopPrivate = t.crossfireTelemetryPopPrivate;
  end
end
local function switchProtocol(proto)
  --print("switchProtocol", proto);
  if (proto == 1) then
    setProtocolVersion = CRSF_SUBCMD_SWITCH_SET4;
  elseif (proto == 2) then
    setProtocolVersion = CRSF_SUBCMD_SWITCH_SET4M;
  else
    setProtocolVersion = CRSF_SUBCMD_SWITCH_SET4;
  end 
end
-- fix: use output-value instead of i
local function computeState2()
    local s = 0;
    for i = 1, 8 do
        s = s * 2;
        if ((state.buttons[8 - i + 1] ~= nil) and (state.buttons[8 - i + 1].value > 0)) then
            s = s + 1;
        end
    end
    return s;
end
-- fix: use output-value instead of i
local function computeState4()
    local s = 0;
    for i = 1, 8 do
        s = s * 4;
        if (state.buttons[8 - i + 1] ~= nil) then
          if (state.buttons[8 - i + 1].value == 1) then
            s = s + 1;
          elseif (state.buttons[8 - i + 1].value == 2) then
            s = s + 2;
          end      
        end
    end
    return s;
end
local function computeState4M(buttons)
  local s = 0;
  for _, btn in ipairs(buttons) do
    --print("button: ", btn, #state.buttons, state.buttons[btn]);
    if (widget.settings.buttons[btn].output ~= nil) then
      local outnr = widget.settings.buttons[btn].output - 1;
      if (state.buttons[btn].value == 1) then
        s = s + bit32.lshift(1, 2 * outnr);
      elseif (state.buttons[btn].value == 2) then
        s = s + bit32.lshift(1, 2 * outnr + 1);
      end        
    end
  end
  return s;
end
local function sendSet()
  local state2 = computeState2();
  local payloadOut = { widget.settings.commandBroadcastAddress, CRSF_ADDRESS_TRANSMITTER, CRSF_REALM_SWITCH, CRSF_SUBCMD_SWITCH_SET,
                       widget.options.Address, state2 };
  return crossfireTelemetryPush(CRSF_FRAMETYPE_CMD, payloadOut);    
end
local function sendSet4()
  local state4 = computeState4();
  local state_high = bit32.rshift(state4, 8);
  local state_low = bit32.band(state4, 0xff);
  local payloadOut = {widget.settings.commandBroadcastAddress, CRSF_ADDRESS_TRANSMITTER, CRSF_REALM_SWITCH, CRSF_SUBCMD_SWITCH_SET4,
                      widget.options.Address, state_high, state_low };
  return crossfireTelemetryPush(CRSF_FRAMETYPE_CMD, payloadOut);    
end
local function sendSet4M()
  -- [N, A1, {H1, L1}, A2, {H2, L2}]
  local payload = {widget.settings.commandBroadcastAddress, CRSF_ADDRESS_TRANSMITTER, CRSF_REALM_SWITCH, CRSF_SUBCMD_SWITCH_SET4M, 0};
  for adr, buttons in pairs(state.addresses) do
    --print("adr:", adr, #buttons);
    payload[5] = payload[5] + 1;
    payload[#payload+1] = adr;
    local state4m = computeState4M(buttons);
    local state_high = bit32.rshift(state4m, 8);
    local state_low = bit32.band(state4m, 0xff);
    payload[#payload+1] = state_high;
    payload[#payload+1] = state_low;
  end
  return crossfireTelemetryPush(CRSF_FRAMETYPE_CMD, payload);    
end
local function send()
  --print("crsf send:", setProtocolVersion);
    local ret = false;
    if (setProtocolVersion == CRSF_SUBCMD_SWITCH_SET) then
        ret = sendSet();
    elseif (setProtocolVersion == CRSF_SUBCMD_SWITCH_SET4) then
        ret = sendSet4();
    elseif (setProtocolVersion == CRSF_SUBCMD_SWITCH_SET4M) then
        ret = sendSet4M();
    end
    if (ret == nil) then ret = true; end;
--    print("senddata adr:", widget.options.Address, ret);
    return ret;
end
local function sendColorsForAddress(adr, buttons)
  --print("sendColorsForAddress", adr, buttons);
  if (buttons == nil) then
    return true;
  end
  -- [A, N, {O1/R1, G1/B1}, ..., {ON/RN,GNBN}] ; A: Address; Ox: 3-bit MSB output, Rx, Gx, Bx: 4-bit color
  local payload = {widget.settings.commandBroadcastAddress, CRSF_ADDRESS_TRANSMITTER, CRSF_REALM_SWITCH, CRSF_SUBCMD_SWITCH_SETRGB, adr, 0};
  for _, btn in ipairs(buttons) do
    payload[6] = payload[6] + 1;
    local c = 0;
    if (bit32.band(widget.settings.buttons[btn].color, 0x8000) > 0) then
      c = bit32.rshift(widget.settings.buttons[btn].color, 16); -- RGB565 in upper half
    else
      c = bit32.rshift(lcd.getColor(widget.settings.buttons[btn].color), 16);
    end
    local r = bit32.band(bit32.rshift(c, 11 + 1), 0x0f);
    local g = bit32.band(bit32.rshift(c, 5 + 2), 0x0f);
    local b = bit32.band(bit32.rshift(c, 1), 0x0f);
    local b1 = bit32.band(bit32.lshift(widget.settings.buttons[btn].output - 1, 4), 0xf0) + r;
    local b2 = bit32.lshift(g, 4) + b;
    payload[#payload+1] = b1;
    payload[#payload+1] = b2;
--    print("out:", widget.settings.buttons[btn].output - 1, c, r, g, b, b1, b2, widget.settings.buttons[btn].color);
  end
  return crossfireTelemetryPush(CRSF_FRAMETYPE_CMD, payload);    
end
local colorIter = {adr = nil, btn = nil};
local function sendNextColor()
  if (colorIter.adr == nil) then
    colorIter.adr, colorIter.btn = next(state.addresses);
  end
  local r = sendColorsForAddress(colorIter.adr, colorIter.btn);
  -- print("sendNextColor", colorIter.adr, r);
  if (r) then
    colorIter.adr, colorIter.btn = next(state.addresses, colorIter.adr);
    if (colorIter.adr == nil) then
      return true;
    end
  end
  return false;
end
local function sendProp(channel, value)
--    print("sendprop adr:", widget.settings.buttons[channel].address, channel, value);
    local payloadOut = { widget.settings.commandBroadcastAddress, CRSF_ADDRESS_TRANSMITTER, CRSF_REALM_SWITCH, CRSF_SUBCMD_SWITCH_PROP_SET, 
                          widget.settings.buttons[channel].address, widget.settings.buttons[channel].output - 1, value };
    crossfireTelemetryPush(CRSF_FRAMETYPE_CMD, payloadOut);
end    

local function requestConfigItem(nr)
    --print("reg config item adr:", widget.options.Address, nr);
    local payloadOut = { widget.settings.commandBroadcastAddress, CRSF_ADDRESS_TRANSMITTER, CRSF_REALM_SWITCH, CRSF_SUBCMD_SWITCH_REQ_CI, 
                         widget.options.Address, nr };
    crossfireTelemetryPush(CRSF_FRAMETYPE_CMD, payloadOut);
end

local function requestDeviceInfo()
    --print("reg device info adr:", widget.options.Address);
    local payloadOut = { widget.settings.commandBroadcastAddress, CRSF_ADDRESS_TRANSMITTER, CRSF_REALM_SWITCH, CRSF_SUBCMD_SWITCH_REQ_DI, 
                         widget.options.Address};
    crossfireTelemetryPush(CRSF_FRAMETYPE_CMD, payloadOut);
end

local function readPassThru()
  local command, data = crossfireTelemetryPop();
  if (command == CRSF_FRAMETYPE_PASSTHRU) and data ~= nil then
    if (#data >= 7) then
      local extdest = data[1]; 
      local extsrc = data[2];
      local subtype = data[3];
      local appid = bit32.lshift(data[4], 8) + data[5];
      if (subtype == PASSTHRU_SUBTYPE_SWITCH) then
        if (appid == PASSTHRU_APPID_STATUS) then
          local address = data[6];
          local bits = data[7];
          return address, bits;
        end
      end     
    end
  end
  return nil, nil;
end

local frameCounter = 0;
local function readItem()
  local command = 0;
  local data = {};
  command, data = crossfireTelemetryPop();
  local t = {};
  if (command == CRSF_FRAMETYPE_ARDUPILOT) and data ~= nil then
      if #data >= 9 then 
          local extdest = data[1]; 
          local extsrc = data[2];
          local app_id = bit32.lshift(data[3], 8) + data[4];
          --print("appid:", app_id);
          if (app_id == ARDUPILOT_SWITCH_APPID) then
            frameCounter = frameCounter + 1;
            t.src = extsrc;
            t.adr = data[5];
            local rtype = data[6];
            if (rtype == ARDUPILOT_SWITCH_RESP_CI) then
              t.item = data[7];
              local strlength = #data - 9; -- incl. `\0`
              t.str = "";
              for i = 0, strlength - 2 do -- no `\0`
                local b = data[i + 8];
                t.str = t.str .. string.char(b);
              end 
              t.ls = data[8 + strlength];
              t.type = data[9 + strlength];
              return t;                
            elseif (app_id == ARDUPILOT_SWITCH_RESP_DI) then
              t.setProtocolVersion = data[7];
              t.remoteHwVersion = data[8];
              t.remoteSwVersion = data[9];
              return t;
            end
          end
      end
  end
  return nil;
end
  
return {send = send, 
        sendProp = sendProp, 
        sendNextColor = sendNextColor,
        switchProtocol = switchProtocol,
        requestConfigItem = requestConfigItem, 
        readItem = readItem, 
        readPassThru = readPassThru,
        requestDeviceInfo = requestDeviceInfo };