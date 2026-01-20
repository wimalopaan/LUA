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

local uilib, env = ... 

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
local CRSF_SUBCMD_SWITCH_SET4     = 0x07; -- 4-state switches (8 switches) 2bytes payload
local CRSF_SUBCMD_SWITCH_SET64    = 0x08; -- 64 x 4-state switches (8 groups of 8 switches) 3bytes payload
local CRSF_SUBCMD_SWITCH_SET4M    = 0x09; -- 4-state switches (8 switches) 2bytes payload, multiple addresses
local CRSF_SUBCMD_SWITCH_INTERMOD = 0x10; -- intermodule command
local CRSF_SUBCMD_SCHOTTEL_RESET  = 0x01;

local ARDUPILOT_SCHOTTEL_APPID    = 6000;
local ARDUPILOT_SCHOTTEL_RESP_T   = 0x00;
local ARDUPILOT_SCHOTTEL_RESP_DI  = 0x01;

local ARDUPILOT_SWITCH_APPID      = 6010;
local ARDUPILOT_SWITCH_RESP_CI    = 0x00;
local ARDUPILOT_SWITCH_RESP_DI    = 0x01;

local setProtocolVersion = CRSF_SUBCMD_SWITCH_SET4M;

local function computeState4M(buttons)
  local s = 0;
  for _, btn in ipairs(buttons) do
--    print("button: ", btn, #uilib.global.state.buttons, uilib.global.state.buttons[btn]);
    if (uilib.global.settings.buttons[btn].output ~= nil) then
      local outnr = uilib.global.settings.buttons[btn].output - 1;
      if (uilib.global.state.buttons[btn].value == 1) then
        s = s + bit32.lshift(1, 2 * outnr);
      elseif (uilib.global.state.buttons[btn].value == 2) then
        s = s + bit32.lshift(1, 2 * outnr + 1);
      end        
    end
  end
  return s;
end
local function sendSet4M()
  -- [N, A1, {H1, L1}, A2, {H2, L2}]
  local payload = {CRSF_ADDRESS_CONTROLLER, CRSF_ADDRESS_TRANSMITTER, CRSF_REALM_SWITCH, CRSF_SUBCMD_SWITCH_SET4M, 0};
  for adr, buttons in pairs(uilib.global.state.addresses) do
--    print("adr:", adr, #buttons);
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
    local ret = sendSet4M();
    if (ret == nil) then ret = true; end;
    return ret;
end
  
return {send = send};