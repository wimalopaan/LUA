local state, widget, widget_id, dir = ... 

local CRSF_ADDRESS_CONTROLLER     = 0xC8;
local CRSF_ADDRESS_TRANSMITTER    = 0xEA;
local CRSF_ADDRESS_CC             = 0xA0; -- non-standard
local CRSF_ADDRESS_SWITCH         = 0xA1; -- non-standard

local CRSF_FRAMETYPE_CMD          = 0x32;
local CRSF_FRAMETYPE_ARDUPILOT    = 0x80;

-- following CRSF definitions are non-standard
local CRSF_REALM_CC               = 0xA0;
local CRSF_REALM_SWITCH           = 0xA1;
local CRSF_REALM_SCHOTTEL         = 0xA2;
local CRSF_SUBCMD_CC_ADATA        = 0x01;
local CRSF_SUBCMD_CC_ACHUNK       = 0x02;
local CRSF_SUBCMD_CC_ACHANNEL     = 0x03;
local CRSF_SUBCMD_SWITCH_SET      = 0x01; -- 2-state switches
local CRSF_SUBCMD_SWITCH_PROP_SET = 0x02;
local CRSF_SUBCMD_SWITCH_REQ_T    = 0x03;
local CRSF_SUBCMD_SWITCH_REQ_TI   = 0x04;
local CRSF_SUBCMD_SWITCH_REQ_CI   = 0x05; -- request config item
local CRSF_SUBCMD_SWITCH_REQ_DI   = 0x06; -- request device info
local CRSF_SUBCMD_SWITCH_SET4     = 0x07; -- 4-state switches
local CRSF_SUBCMD_SCHOTTEL_RESET  = 0x01;

local ARDUPILOT_SCHOTTEL_APPID    = 6000;
local ARDUPILOT_SCHOTTEL_RESP_T   = 0x00;
local ARDUPILOT_SCHOTTEL_RESP_DI  = 0x01;

local ARDUPILOT_SWITCH_APPID      = 6010;
local ARDUPILOT_SWITCH_RESP_CI    = 0x00;
local ARDUPILOT_SWITCH_RESP_DI    = 0x01;

local setProtocolVersion = CRSF_SUBCMD_SWITCH_SET4;

local _, rv = getVersion()
if string.sub(rv, -5) == "-simu" then 
  local c = loadScript("/WIDGETS/" .. dir .. "/crsfserial.lua");
  if (c ~= nil) then
    --print("load crsf serial")
    local t = c();
    crossfireTelemetryPush = t.crossfireTelemetryPush;
    crossfireTelemetryPop  = t.crossfireTelemetryPop;
    crossfireTelemetryPopPrivate = t.crossfireTelemetryPopPrivate;
  end
end
local function computeState2()
    local s = 0;
    for i = 1, 8 do
        s = s * 2;
        if (state.buttons[i].value > 0) then
            s = s + 1;
        end
    end
    return s;
end
local function computeState4()
    local s = 0;
    for i = 1, 8 do
        s = s * 4;
        if (state.buttons[i].value == 1) then
            s = s + 1;
        elseif (state.buttons[i].value == 2) then
            s = s + 2;
        end
    end
    return s;
end
local function send()
    print("senddata adr:", widget.options.Address);
    if (setProtocolVersion == CRSF_SUBCMD_SWITCH_SET) then
        local state2 = computeState2(state);
        local payloadOut = { CRSF_ADDRESS_CONTROLLER, CRSF_ADDRESS_TRANSMITTER, CRSF_REALM_SWITCH, CRSF_SUBCMD_SWITCH_SET,
                             widget.options.Address, state2 };
        crossfireTelemetryPush(CRSF_FRAMETYPE_CMD, payloadOut);    
    elseif (setProtocolVersion == CRSF_SUBCMD_SWITCH_SET4) then
        local state4 = computeState4(state);
        local state_high = bit32.rshift(state4, 8);
        local state_low = bit32.band(state4, 0xff);
        local payloadOut = { CRSF_ADDRESS_CONTROLLER, CRSF_ADDRESS_TRANSMITTER, CRSF_REALM_SWITCH, CRSF_SUBCMD_SWITCH_SET4,
        widget.options.Address, state_high, state_low };
        crossfireTelemetryPush(CRSF_FRAMETYPE_CMD, payloadOut);    
    end
end
local function sendProp(channel, value)
      --print("sendprop adr:", widget.options.Address, channel, value);
      local payloadOut = { CRSF_ADDRESS_CONTROLLER, CRSF_ADDRESS_TRANSMITTER, CRSF_REALM_SWITCH, CRSF_SUBCMD_SWITCH_PROP_SET, 
                           widget.options.Address, channel, value };
      crossfireTelemetryPush(CRSF_FRAMETYPE_CMD, payloadOut);
end    

local function requestConfigItem(nr)
    --print("reg config item adr:", widget.options.Address, nr);
    local payloadOut = { CRSF_ADDRESS_CONTROLLER, CRSF_ADDRESS_TRANSMITTER, CRSF_REALM_SWITCH, CRSF_SUBCMD_SWITCH_REQ_CI, 
                         widget.options.Address, nr };
    crossfireTelemetryPush(CRSF_FRAMETYPE_CMD, payloadOut);
end

local function requestDeviceInfo()
    --print("reg device info adr:", widget.options.Address);
    local payloadOut = { CRSF_ADDRESS_CONTROLLER, CRSF_ADDRESS_TRANSMITTER, CRSF_REALM_SWITCH, CRSF_SUBCMD_SWITCH_REQ_DI, 
                         widget.options.Address};
    crossfireTelemetryPush(CRSF_FRAMETYPE_CMD, payloadOut);
end

local frameCounter = 0;

local function readItem()
  local command = 0;
  local data = {};
  if (crossfireTelemetryPopPrivate ~= nil) then
    command, data = crossfireTelemetryPopPrivate(widget_id);
  else
    command, data = crossfireTelemetryPop();
  end
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
        requestConfigItem = requestConfigItem, 
        readItem = readItem, 
        requestDeviceInfo = requestDeviceInfo };