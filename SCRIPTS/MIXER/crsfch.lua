CRSF_ADDRESS_CONTROLLER             = 0xC8
CRSF_ADDRESS_TRANSMITTER            = 0xEA

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
    return (v * 127) / 1023;
  else
    return (v * 128) / 1024;    
  end
end

local function sendChannels(startChannel, numberOfChannels) 
--  print("sendchannels", startChannel, numberOfChannels, "ch:", scaleTo8Bit(startChannel));
  local payloadOut = {CRSF_ADDRESS_CONTROLLER, CRSF_ADDRESS_TRANSMITTER, CRSF_REALM_CC, CRSF_SUBCMD_CC_ACHANNEL};
  for ch=startChannel, (startChannel + numberOfChannels - 1) do
    payloadOut[5 + ch - startChannel] = scaleTo8Bit(ch);
  end
  crossfireTelemetryPush(CRSF_FRAMETYPE_CMD, payloadOut);
end

local inputs = {
	{"StartC", VALUE, 1, 32, 17},
	{"Number", VALUE, 1, 16, 16},
  {"Interv", VALUE, 1, 99, 5}
}

local last = getTime();
local function run(startChannel, numberOfChannels, intervall)
    local t = getTime();
    if ((t - last) >= intervall) then
      sendChannels(startChannel, numberOfChannels);
      last = t;
    end  
end

return {input=inputs, run=run} 