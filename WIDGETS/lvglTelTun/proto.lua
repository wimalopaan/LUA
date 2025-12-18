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

local zone, options, dir                        = ...

local CRSF_ADDRESS_CONTROLLER                   = 0xC8;
local CRSF_ADDRESS_TRANSMITTER                  = 0xEA;
local CRSF_ADDRESS_CC                           = 0xA0; -- non-standard
local CRSF_ADDRESS_SWITCH                       = 0xA1; -- non-standard

local CRSF_FRAMETYPE_CMD                        = 0x32;
local CRSF_FRAMETYPE_PASSTHRU                   = 0x7f;
local CRSF_FRAMETYPE_ARDUPILOT                  = 0x80;

-- following CRSF definitions are non-standard
local CRSF_REALM_CC                             = 0xA0;
local CRSF_REALM_SWITCH                         = 0xA1;
local CRSF_REALM_SCHOTTEL                       = 0xA2;
local CRSF_SUBCMD_CC_ADATA                      = 0x01;
local CRSF_SUBCMD_CC_ACHUNK                     = 0x02;
local CRSF_SUBCMD_CC_ACHANNEL                   = 0x03;
local CRSF_SUBCMD_CC_ACHAN_EXT                  = 0x04;
local CRSF_SUBCMD_SWITCH_SET                    = 0x01; -- 2-state switches
local CRSF_SUBCMD_SWITCH_PROP_SET               = 0x02;
local CRSF_SUBCMD_SWITCH_REQ_T                  = 0x03;
local CRSF_SUBCMD_SWITCH_REQ_TI                 = 0x04;
local CRSF_SUBCMD_SWITCH_REQ_CI                 = 0x05; -- request config item
local CRSF_SUBCMD_SWITCH_REQ_DI                 = 0x06; -- request device info
local CRSF_SUBCMD_SWITCH_SET4                   = 0x07; -- 4-state switches (8 switches) 2bytes payload
local CRSF_SUBCMD_SWITCH_SET64                  = 0x08; -- 64 x 4-state switches (8 groups of 8 switches) 3bytes payload
local CRSF_SUBCMD_SWITCH_SET4M                  = 0x09; -- 4-state switches (8 switches) 2bytes payload, multiple addresses
local CRSF_SUBCMD_SWITCH_SETRGB                 = 0x0a;
local CRSF_SUBCMD_SWITCH_INTERMOD               = 0x10; -- intermodule command
local CRSF_SUBCMD_SWITCH_INTERMOD_PATTERN_START = 0x11; -- intermodule command
local CRSF_SUBCMD_SWITCH_INTERMOD_PATTERN_STOP  = 0x12; -- intermodule command
local CRSF_SUBCMD_SWITCH_INTERMOD_SLAVE_SET     = 0x13; -- intermodule command
local CRSF_SUBCMD_SCHOTTEL_RESET                = 0x01;

local PASSTHRU_SUBTYPE_SWITCH                   = 0xa1;
local PASSTHRU_SUBTYPE_LINKSTAT                 = 0x01;
local PASSTHRU_SUBTYPE_TELEMETRY                = 0x02;

local PASSTHRU_APPID_STATUS                     = 6100;
local PASSTHRU_APPID_TELEM                      = 6200;

local ARDUPILOT_SCHOTTEL_APPID                  = 6000;
local ARDUPILOT_SCHOTTEL_RESP_T                 = 0x00;
local ARDUPILOT_SCHOTTEL_RESP_DI                = 0x01;

local ARDUPILOT_SWITCH_APPID                    = 6010;
local ARDUPILOT_SWITCH_RESP_CI                  = 0x00;
local ARDUPILOT_SWITCH_RESP_DI                  = 0x01;

local _, rv                                     = getVersion()
if string.sub(rv, -5) == "-simu" then
    local c = loadScript(dir .. "crsfserial.lua");
    if (c ~= nil) then
        print("load crsf serial")
        local t                = c();
        crossfireTelemetryPush = t.crossfireTelemetryPush;
        crossfireTelemetryPop  = t.crossfireTelemetryPop;
    end
end

local proto = {
    linkcounter = 0,
    telemcounter = 0
};

local function setLinkStat()
    local instance = 0;
    local id = 14;
    local id_base = 100;
    setTelemetryValue(id_base + id, 0, instance, proto.linkstat.rssi1, UNIT_DB, 0, "X1RS");
    instance = instance + 1;
    setTelemetryValue(id_base + id, 0, instance, proto.linkstat.rssi2, UNIT_DB, 0, "X2RS");
    instance = instance + 1;
    setTelemetryValue(id_base + id, 0, instance, proto.linkstat.lq_up, UNIT_PERCENT, 0, "XRQl");
    instance = instance + 1;
    setTelemetryValue(id_base + id, 0, instance, proto.linkstat.snr_up, UNIT_DB, 0, "XRSN");
    instance = instance + 1;
    setTelemetryValue(id_base + id, 0, instance, proto.linkstat.ant, UNIT_RAW, 0, "XANT");
    instance = instance + 1;
    setTelemetryValue(id_base + id, 0, instance, proto.linkstat.mode, UNIT_RAW, 0, "XRFM");
    instance = instance + 1;
    setTelemetryValue(id_base + id, 0, instance, proto.linkstat.tx_pwr, UNIT_MILLIWATTS, 0, "XTPW");
    instance = instance + 1;
    setTelemetryValue(id_base + id, 0, instance, proto.linkstat.rssi_dn, UNIT_DB, 0, "XRSS");
    instance = instance + 1;
    setTelemetryValue(id_base + id, 0, instance, proto.linkstat.lq_dn, UNIT_PERCENT, 0, "XTQl");
    instance = instance + 1;
    setTelemetryValue(id_base + id, 0, instance, proto.linkstat.snr_dn, UNIT_DB, 0, "XTSN");
end

local pwr_values = {
    [0] = 0,
    [1] = 10,
    [2] = 25,
    [3] = 100,
    [4] = 500,
    [5] = 1000,
    [6] = 2000,
    [7] = 250,
    [8] = 50
};
local function topower(i) 
    if (i < #pwr_values) then
        return pwr_values[i];
    end
    return 0;
end

local function readPassThru()
    local command, data = crossfireTelemetryPop();
    if (command == CRSF_FRAMETYPE_PASSTHRU) and data ~= nil then
--        print("passthru");
        if (#data >= 7) then
            local extdest = data[1];
            local extsrc = data[2];
            local appid = bit32.lshift(data[3], 8) + data[4];
            local subtype = data[5];
            if (appid == PASSTHRU_APPID_TELEM) then
                if (subtype == PASSTHRU_SUBTYPE_LINKSTAT) then
                    proto.linkcounter = proto.linkcounter + 1;
                    local linkstat = {};
                    linkstat.type  = data[6];
                    linkstat.rssi1  = data[7] - 255;
                    linkstat.rssi2  = data[8] - 255;
                    linkstat.lq_up = data[9];
                    linkstat.snr_up  = data[10];
                    linkstat.ant  = data[11];
                    linkstat.mode  = data[12];
                    linkstat.tx_pwr = topower(data[13]);
                    linkstat.rssi_dn = data[14] - 255;
                    linkstat.lq_dn = data[15];
                    linkstat.snr_dn = data[16];
                    proto.linkstat = linkstat;
                    print("linkstat", linkstat.type, linkstat.rssi1, linkstat.rssi2, linkstat.lq_up);
                    setLinkStat();
                elseif (subtype == PASSTHRU_SUBTYPE_TELEMETRY) then
                    proto.telemcounter = proto.telemcounter + 1;
                    local type  = data[6];
                    print("telemetry", type);
                end
            end
        end
    end
end

function proto.tick() 
    readPassThru();
end

return proto;
