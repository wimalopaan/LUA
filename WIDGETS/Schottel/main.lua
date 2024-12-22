local VERSION = "V1.2"

local onSimu = false;
local _, rv = getVersion()
if string.sub(rv, -5) == "-simu" then 
  local c = loadScript("/WIDGETS/Schottel/crsfserial.lua");
  if (c ~= nil) then
    print("load crsf serial")
    local t = c();
    if (t ~= nil) then
        crossfireTelemetryPush = t.crossfireTelemetryPush;
        crossfireTelemetryPop  = t.crossfireTelemetryPop;
        onSimu = true;
    end
  end
end

local libGUI = loadScript("/WIDGETS/LibGUI/libgui.lua")()
local gui = libGUI.newGUI()

local confirmPrompt = libGUI.newGUI()

function confirmPrompt.fullScreenRefresh()
  lcd.drawFilledRectangle(40, 80, LCD_W - 80, 100, COLOR_THEME_SECONDARY2)
  lcd.drawText(LCD_W / 2, 90, "Reset turns to position zero", CENTER + COLOR_THEME_WARNING);
end

CRSF_ADDRESS_CONTROLLER     = 0xC8;
CRSF_ADDRESS_TRANSMITTER    = 0xEA;
CRSF_ADDRESS_CC             = 0xA0; -- non-standard
CRSF_ADDRESS_SWITCH         = 0xA1; -- non-standard

CRSF_FRAMETYPE_CMD          = 0x32;
-- following CRSF definitions are non-standard
CRSF_REALM_CC               = 0xA0;
CRSF_REALM_SWITCH           = 0xA1;
CRSF_REALM_SCHOTTEL         = 0xA2;
CRSF_SUBCMD_CC_ADATA        = 0x01;
CRSF_SUBCMD_CC_ACHUNK       = 0x02;
CRSF_SUBCMD_CC_ACHANNEL     = 0x03;
CRSF_SUBCMD_SWITCH_SET      = 0x01;
CRSF_SUBCMD_PROP_SET        = 0x02;
CRSF_SUBCMD_SCHOTTEL_RESET  = 0x01;

local adr = CRSF_ADDRESS_CONTROLLER; -- default value

local function sendResetCommand() 
    print("send reset");
    local payloadOut = { adr, CRSF_ADDRESS_TRANSMITTER, CRSF_REALM_SCHOTTEL, CRSF_SUBCMD_SCHOTTEL_RESET};
    crossfireTelemetryPush(CRSF_FRAMETYPE_CMD, payloadOut);
  end

confirmPrompt.button(100, 120, 80, 40, "YES", function()
    sendResetCommand(); 
    gui.dismissPrompt();
end)

confirmPrompt.button(LCD_W / 2 + 60, 120, 80, 40, "NO", function() 
    gui.dismissPrompt();
end)

gui.button(LCD_W / 2 - 30, LCD_H - 42, 60, 20, "Reset", 
function()
    gui.showPrompt(confirmPrompt);
end);

local function create(zone, options)
    return {
        zone = zone,
        options = options
    };
end

local function update(widget, options)
    widget.options = options;
end

local function drawGauge(widget, side, steer, throttle, actual, offset, alarm)
--    print("DRAWGAUGE");
    local zone = {};
    if (side == 0) then
        zone.x = widget.zone.x;
        zone.y = widget.zone.y;
        zone.w = widget.zone.w / 2;
        zone.h = widget.zone.h;
    else
        zone.x = widget.zone.x + widget.zone.w / 2;
        zone.y = widget.zone.y;
        zone.w = widget.zone.w / 2;
        zone.h = widget.zone.h;
    end
    zone.cx = zone.x + zone.w / 2;
    zone.cy = zone.y + zone.h / 2;

    if (side == 0) then
        lcd.drawText(zone.x, zone.y, "Left", LEFT + SMLSIZE + COLOR_THEME_PRIMARY1);
    else
        lcd.drawText(zone.x + zone.w, zone.y, "Right", RIGHT + SMLSIZE + COLOR_THEME_PRIMARY1);
    end

    local rr = math.min(zone.w / 2, zone.h / 2) * 0.8;

    local r1 = rr * 0.9;
    local r2 = rr * 1.1;
    local r3 = rr / 0.9;
    local r4 = rr * 0.9;

    lcd.drawCircle(zone.cx, zone.cy, rr, SOLID + COLOR_THEME_PRIMARY3);

    if (alarm) then
        lcd.drawFilledCircle(zone.cx, zone.cy, 15, SOLID + COLOR_THEME_WARNING);
    else
        lcd.drawFilledCircle(zone.cx, zone.cy, 5, SOLID + COLOR_THEME_SECONDARY1);
    end

    for i = 0, 11 do
        local phi = (2 * math.pi * i) / 12;
        local tx1 = zone.cx + r1 * math.cos(phi);
        local ty1 = zone.cy + r1 * math.sin(phi);
        local tx2 = zone.cx + r2 * math.cos(phi);
        local ty2 = zone.cy + r2 * math.sin(phi);
        lcd.drawLine(tx1, ty1, tx2, ty2, SOLID + COLOR_THEME_SECONDARY2);
    end

    local offset_phi = offset * (math.pi / 2);
    -- negative phi, disply is upside-down
    local steer_phi  = -math.pi * steer / 2024 + offset_phi;
    local actual_phi = -math.pi * actual / 2024 + offset_phi;
    local thr_norm = math.max(0, throttle / 820);
    local thr_r = rr * (1 - thr_norm);

    local delta_phi = math.pi / 30;

    local steer_xa = zone.cx - thr_r * math.cos(steer_phi);
    local steer_ya = zone.cy - thr_r * math.sin(steer_phi);
    local steer_xe = zone.cx - rr * math.cos(steer_phi);
    local steer_ye = zone.cy - rr * math.sin(steer_phi);
    lcd.drawLine(steer_xa, steer_ya, steer_xe, steer_ye, SOLID + COLOR_THEME_WARNING);

    local r5 = math.min(r4, thr_r);
    local ix = zone.cx - r5 * math.cos(steer_phi);
    local iy = zone.cy - r5 * math.sin(steer_phi);
    local d = 10;
    local dx = d * math.sin(steer_phi);
    local dy = d * math.cos(steer_phi);
    local steer_x2 = ix - dx;
    local steer_y2 = iy + dy;
    local steer_x3 = ix + dx;
    local steer_y3 = iy - dy;
    lcd.drawFilledTriangle(steer_xe, steer_ye, steer_x2, steer_y2, steer_x3, steer_y3, SOLID + COLOR_THEME_WARNING);

    local actual_x1 = zone.cx - rr * math.cos(actual_phi);
    local actual_y1 = zone.cy - rr * math.sin(actual_phi);
    local actual_x2 = zone.cx - r3 * math.cos(actual_phi + delta_phi);
    local actual_y2 = zone.cy - r3 * math.sin(actual_phi + delta_phi);
    local actual_x3 = zone.cx - r3 * math.cos(actual_phi - delta_phi);
    local actual_y3 = zone.cy - r3 * math.sin(actual_phi - delta_phi);
    lcd.drawFilledTriangle(actual_x1, actual_y1, actual_x2, actual_y2, actual_x3, actual_y3, SOLID + COLOR_THEME_EDIT);
end

local steer1 = 0;
local power1 = 0;
local actual1 = 0;
local curr1 = 0;
local rpm1 = 0;
local turns1 = 0;
local steer2 = 0;
local power2 = 0;
local actual2 = 0;
local curr2 = 0;
local rpm2 = 0;
local turns2 = 0;
local flags = 0;

local frameCounter = 0;
local lastFrameCounter = 0;
local refreshCounter = 0;

function refresh(widget, event, touchState)
--    print("REFRESH");
    refreshCounter = refreshCounter + 1;
    lcd.clear();

    local command, data = crossfireTelemetryPop();
    local app_id = 0;
    if (command == 0x80 or command == 0x7F) and data ~= nil then
        local dest = data[1]; 
        adr = data[2];
        app_id = bit32.lshift(data[3], 8) + data[4];
        if #data >= 27 then 
            if (app_id == 6000) then
                frameCounter = frameCounter + 1;
                steer1  = bit32.lshift(data[5], 8) + data[6];
                power1  = bit32.lshift(data[7], 8) + data[8];
                actual1 = bit32.lshift(data[9], 8) + data[10];
                curr1   = bit32.lshift(data[11], 8) + data[12] * 0.01;                    
                rpm1    = bit32.lshift(data[13], 8) + data[14];
                steer2  = bit32.lshift(data[15], 8) + data[16];                    
                power2  = bit32.lshift(data[17], 8) + data[18];
                actual2 = bit32.lshift(data[19], 8) + data[20];                    
                curr2   = bit32.lshift(data[21], 8) + data[22] * 0.01;
                rpm2    = bit32.lshift(data[23], 8) + data[24];                    
                turns1  = data[25]; 
                turns2  = data[26];
                flags   = data[27];
            end
        end
    end

    if (turns1 >= 128) then
        turns1 = turns1 - 256;
    end
    if (turns2 >= 128) then
        turns2 = turns2 - 256;
    end

    if (refreshCounter == 10) then
        refreshCounter = 0;
        lastFrameCounter = frameCounter;
        frameCounter = 0;
    end

    local alarm1 = false;
    local alarm2 = false;
    local alarm3 = false;
    if (bit32.band(flags, 0x01) ~= 0x00) then
        alarm1 = true;
    end
    if (bit32.band(flags, 0x02) ~= 0x00) then
        alarm2 = true;
    end
    if (bit32.band(flags, 0x04) ~= 0x00) then
        alarm3 = true;
        playTone(440, 500, 100);
    end

    drawGauge(widget, 0, steer1, power1, actual1, widget.options.Offset, alarm1);
    drawGauge(widget, 1, steer2, power2, actual2, widget.options.Offset, alarm2);

    if (event ~= nil) then
        lcd.drawText(widget.zone.x + widget.zone.w / 2 - 5, widget.zone.y, "Adr: " .. adr, RIGHT + SMLSIZE + COLOR_THEME_WARNING);
        if (onSimu) then
            lcd.drawText(widget.zone.x + widget.zone.w / 2 + 5, widget.zone.y, "[" .. lastFrameCounter .. "]simu", LEFT + SMLSIZE + COLOR_THEME_WARNING);
        else
            lcd.drawText(widget.zone.x + widget.zone.w / 2 + 5, widget.zone.y, "[" .. lastFrameCounter .. "]", LEFT + SMLSIZE + COLOR_THEME_WARNING);
        end

        lcd.drawText(widget.zone.x + widget.zone.w / 2 - 5, widget.zone.y + widget.zone.h - 18, "Steer/Pwr", RIGHT + SMLSIZE + COLOR_THEME_WARNING);
        lcd.drawText(widget.zone.x + widget.zone.w / 2 + 5, widget.zone.y + widget.zone.h - 18, "Actual", LEFT + SMLSIZE + COLOR_THEME_EDIT);
    
        lcd.drawLine(widget.zone.x, widget.zone.y + 20, widget.zone.x + widget.zone.w, widget.zone.y + 20, SOLID, COLOR_THEME_PRIMARY2);
        lcd.drawLine(widget.zone.x, widget.zone.y + widget.zone.h - 20, widget.zone.x + widget.zone.w, widget.zone.y + widget.zone.h - 20, SOLID, COLOR_THEME_PRIMARY2);
        lcd.drawLine(widget.zone.x + widget.zone.w / 2, widget.zone.y + 20, widget.zone.x + widget.zone.w / 2, widget.zone.y + widget.zone.h - 20, SOLID, COLOR_THEME_PRIMARY2);            

        lcd.drawText(widget.zone.x, widget.zone.y + widget.zone.h - 18, "Curr: " .. curr1, LEFT + SMLSIZE + COLOR_THEME_PRIMARY1);
        lcd.drawText(widget.zone.x + 60, widget.zone.y + widget.zone.h - 18, "RpM: " .. rpm1, LEFT + SMLSIZE + COLOR_THEME_PRIMARY1);
        lcd.drawText(widget.zone.x + 120, widget.zone.y + widget.zone.h - 18, "Turns: " .. turns1, LEFT + SMLSIZE + COLOR_THEME_PRIMARY1);

        lcd.drawText(widget.zone.x + widget.zone.w - 180, widget.zone.y + widget.zone.h - 18, "Curr: " .. curr2, LEFT + SMLSIZE + COLOR_THEME_PRIMARY1);
        lcd.drawText(widget.zone.x + widget.zone.w - 120, widget.zone.y + widget.zone.h - 18, "RpM: " .. rpm2, LEFT + SMLSIZE + COLOR_THEME_PRIMARY1);
        lcd.drawText(widget.zone.x + widget.zone.w, widget.zone.y + widget.zone.h - 18, "Turns: " .. turns2, RIGHT + SMLSIZE + COLOR_THEME_PRIMARY1);

        gui.run(event, touchState);
    else
        lcd.drawText(widget.zone.x + widget.zone.w / 2, widget.zone.y, VERSION, CENTER + SMLSIZE + COLOR_THEME_PRIMARY1);
    end
end

local options = {
    {"Offset", VALUE, 0, 0, 3};
}
  
return {
    name = "RC720E32",
    create = create,
    update = update,
    refresh = refresh,
    options = options
};
