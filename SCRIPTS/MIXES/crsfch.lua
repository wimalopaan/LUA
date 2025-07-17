-- WM EdgeTx LUA 
-- Copyright (C) 2016 - 2025 Wilhelm Meier <wilhelm.wm.meier@googlemail.com>
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

CRSF_ADDRESS_CONTROLLER             = 0xC8
CRSF_ADDRESS_TRANSMITTER            = 0xEA

CRSF_FRAMETYPE_RC       = 0x16
CRSF_FRAMETYPE_CMD      = 0x32
CRSF_REALM_CC           = 0xA0;
CRSF_SUBCMD_CC_ADATA    = 0x01;
CRSF_SUBCMD_CC_ACHUNK   = 0x02;
CRSF_SUBCMD_CC_ACHANNEL = 0x03;
CRSF_SUBCMD_CC_ACHAN_LO = 0x04;
CRSF_SUBCMD_CC_ACHAN_HI = 0x05;

local function scaleTo8Bit(channel)
  local v = getOutputValue(channel - 1);
  if (v >= 0) then
    return (v * 127) / 1024;
  else
    return (v * 128) / 1024;    
  end
end

local function sendChannels(startChannel, numberOfChannels) 
  print("sendchannels", startChannel, numberOfChannels, "ch:", scaleTo8Bit(startChannel));
  local payloadOut = {CRSF_ADDRESS_CONTROLLER, CRSF_ADDRESS_TRANSMITTER, CRSF_REALM_CC, CRSF_SUBCMD_CC_ACHANNEL};
  for ch=startChannel, (startChannel + numberOfChannels - 1) do
    payloadOut[5 + ch - startChannel] = scaleTo8Bit(ch);
  end
  crossfireTelemetryPush(CRSF_FRAMETYPE_CMD, payloadOut);
end

local inputs = {
	{"StartC", VALUE, 1, 17, 17},
  {"Interv", VALUE, 1, 99, 5}
}

local last = getTime();
local function run(startChannel, Interv)
    local t = getTime();
    if ((t - last) >= Interv) then
      sendChannels(startChannel, 16);
      last = t;
    end  
end

local function init() 
  local ver, radio, maj, minor, rev, osname = getVersion();
  print(radio, osname);
end

return {input=inputs, init=init, run=run} 