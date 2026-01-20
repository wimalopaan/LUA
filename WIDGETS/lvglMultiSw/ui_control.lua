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

local state, widget = ... 

local function invert(v) 
    if (v == 0) then
        return 1;
    else
        return 0;
    end    
end

local function processButtonGroup(bnum) 
    local egr = widget.settings.buttons[bnum].exclusive_group;
    if ((state.buttons[bnum].value > 0) and (egr > 0)) then
        for i, btn in ipairs(widget.settings.buttons) do
            if ((i ~= bnum) and (egr == btn.exclusive_group)) then
                if (state.buttons[i].value > 0) then
                    state.buttons[i].value = 0;
                    widget.checkButton(i, false);
                    widget.setLSorVs(widget.settings.buttons[i].external_switch, false);
                end
            end            
        end
    end
end

local function updateButton(i)
    processButtonGroup(i);
    widget.fsm.update();
    widget.setLSorVs(widget.settings.buttons[i].external_switch, (state.buttons[i].value > 0));
    if (widget.hasVirtualInputs) then
        if (state.buttons[i].value > 0) then
            if (widget.settings.buttons[i].setVirtualInput > 0) then
                setVirtualInput(widget.settings.buttons[i].setVirtualInput, widget.settings.buttons[i].setVirtualValue * 10.24);            
            end
        else
            if (widget.settings.buttons[i].setVirtualInput > 0) then
                local off = widget.settings.virtualInputs[widget.settings.buttons[i].setVirtualInput].off * 10.24;
                setVirtualInput(widget.settings.buttons[i].setVirtualInput, off);        
            end
        end        
    end
end

local function isSwitchActive(i)
    local possible_active = (widget.settings.buttons[i].activation_switch == 0) or getSwitchValue(widget.settings.buttons[i].activation_switch);
    if (possible_active) then
        if (widget.settings.buttons[i].switch > 0) then 
            return false; 
        else 
            return true; 
        end; 
    else
        return false;
    end
end

local function createButton(i, width)
    if (widget.settings.buttons[i].visible == 0) then
        return;
    end
    local ichild = {};
    if (widget.settings.buttons[i].image ~= "") then
        ichild = {{ type = "image", file = widget.settings.imagesdir .. widget.settings.buttons[i].image, x = 0, y = -1, 
                                                                                    w = widget.settings.line_height, 
                                                                                    h = widget.settings.line_height - 7}};        
    end
    if (widget.settings.buttons[i].type == widget.C.TYPE_BUTTON) then
        return { type = "button", name = "b" .. i, text = (function() 
                    local sw = widget.settings.buttons[i].switch * widget.settings.show_physical;
                    if (sw ~= 0) then
                        local swname = getSwitchName(sw);
                        if (swname ~= nil) then
                            return widget.settings.buttons[i].name .. " (" .. getSwitchName(sw) .. ")";
                        else                            
                            return widget.settings.buttons[i].name .. " (?)";
                        end
                    else
                        return widget.settings.buttons[i].name;
                    end
                 end)(), 
                 w = width, h = widget.settings.line_height, 
                 color = widget.settings.buttons[i].color, textColor = widget.settings.buttons[i].textColor, font = widget.settings.buttons[i].font,
                 press = (function() state.buttons[i].value = invert(state.buttons[i].value); updateButton(i); return state.buttons[i].value; end),
                 active = (function() return isSwitchActive(i); end),
                 checked = (state.buttons[i].value ~= 0),
                 children = ichild
            };
    elseif (widget.settings.buttons[i].type == widget.C.TYPE_MOMENTARY) then
        return { type = "momentaryButton", text = widget.settings.buttons[i].name, 
        w = width, h = widget.settings.line_height, cornerRadius = widget.settings.momentaryButton_radius,
        color = widget.settings.buttons[i].color, textColor = widget.settings.buttons[i].textColor, font = widget.settings.buttons[i].font,
        press = (function() state.buttons[i].value = 1; updateButton(i); end),
        release = (function() state.buttons[i].value = 0; updateButton(i); end),
        active = (function() return isSwitchActive(i); end),
        children = ichild
    };
    elseif (widget.settings.buttons[i].type == widget.C.TYPE_3POS) then
        return {type = "box", flexFlow = lvgl.FLOW_ROW, children = {
            { type = "label", text = (function() 
                local sw = widget.settings.buttons[i].switch * widget.settings.show_physical;
                local sw2 = widget.settings.buttons[i].switch2;
                if (sw > 0) then
                    return widget.settings.buttons[i].name .. " (" .. getSwitchName(sw) .. "|" .. getSwitchName(sw2) .. ")";
                else
                    return widget.settings.buttons[i].name;
                end
             end)(), 
              w = width / 2, font = widget.settings.buttons[i].font},
            { type = "slider", min = -1, max = 1, 
                                get = (function() local v = state.buttons[i].value; if (v <= 1) then return v; else return -1; end; end), 
                                set = (function(v) if (v == -1) then state.buttons[i].value = 2; else state.buttons[i].value = v; end; updateButton(i); end), 
                                active = (function() return isSwitchActive(i); end),
                                w = width / 2, color = widget.settings.buttons[i].color, 
                            }
        }};
    elseif (widget.settings.buttons[i].type == widget.C.TYPE_TOGGLE) then
        return {type = "box", flexFlow = lvgl.FLOW_ROW, x = 0, w = width, children = {
            { type = "label", text = (function() 
                local sw = widget.settings.buttons[i].switch * widget.settings.show_physical;
                if (sw > 0) then
                    return widget.settings.buttons[i].name .. " (" .. getSwitchName(sw) .. ")";
                else
                    return widget.settings.buttons[i].name;
                end
             end)(), 
              w = width / 2, x = 0, font = widget.settings.buttons[i].font, 
            },
            { type = "toggle", get = (function() if (state.buttons[i].value ~= 0) then return 1; else return 0; end; end), 
                               set = (function(v) state.buttons[i].value = v; updateButton(i); end), w = width / 2 ,
                               active = (function() return isSwitchActive(i); end),
                               color = widget.settings.buttons[i].color }
        }};
    elseif (widget.settings.buttons[i].type == widget.C.TYPE_SLIDER) then
        return {type = "box", flexFlow = lvgl.FLOW_ROW, children = {
            { type = "label", text = (function() 
                local so = widget.settings.buttons[i].source * widget.settings.show_physical;
                if (so > 0) then
                    return widget.settings.buttons[i].name .. " (" .. getSourceName(so) .. ")";
                else
                    return widget.settings.buttons[i].name;
                end
             end)(), 
              w = width / 3, font = widget.settings.buttons[i].font},
            { type = "slider", min = 0, max = 100, get = (function() return state.buttons[i].value; end),
                                                      set = (function(v) state.buttons[i].value = v; widget.crsf.sendProp(i, v); end), w = (2 * width) / 3,
                                                      active = (function() if (widget.settings.buttons[i].source > 0) then return false; else return true; end; end),
                                                      color = widget.settings.buttons[i].color
                                                    }
        }};
    end
end


local function leftStatusBit(i)
    local xo = 1;
    local yo = 20;
    local dy = 10;
    local w = 10;
    local h = 20;
    local r = {type = "rectangle", x = xo, y = yo + (i - 1) * (dy + h), w = w, h = h, filled = true,
                                   color = (function() 
                                    if (state.remoteStatus[i] > 0) then
                                        return widget.settings.telemActions[i].colorOn;
                                    else
                                        return widget.settings.telemActions[i].colorOff;
                                    end
                                   end)};
    return r;                   
end

local function rightStatusBit(i)
    local xo = 1;
    local yo = 20;
    local dy = 10;
    local w = 10;
    local h = 20;
    local r = {type = "rectangle", x = LCD_W - xo - w, y = yo + (i - 1) * (dy + h), w = w, h = h, filled = true,
                                   color = (function() 
                                    local ii = i + 4;
                                    if (state.remoteStatus[ii] > 0) then
                                        return widget.settings.telemActions[ii].colorOn;
                                    else
                                        return widget.settings.telemActions[ii].colorOff;
                                    end
                                   end)};
    return r;                   
end

function widget.controlPage()
    lvgl.clear();
    local page = lvgl.page({
        title = widget.titleString(),
        subtitle = "Control",
        icon = widget.dir .. "Logo_30_inv.png";
        back = (function() widget.askClose(); end),
    });

    local column_width = widget.zone.w / widget.settings.columns - 10;
    local button_width = widget.zone.w / widget.settings.columns - 40;

    local columns = {};
    for c = 1, widget.settings.columns do
        columns[c] = {};
        for r = 1, widget.settings.rows do
            local b = createButton(r + (c - 1) * widget.settings.rows, button_width);
            if (b) then
                columns[c][#columns[c]+1] = b;
            end
        end
    end

    local uit = {{ type = "box", flexFlow = lvgl.FLOW_COLUMN, children = {
        { type = "box",
            flexFlow = lvgl.FLOW_ROW,
            children = (function() 
                local cols = {};
                for c = 1, widget.settings.columns do
                    cols[c] = {type = "box", w = column_width, flexFlow = lvgl.FLOW_COLUMN, flexPad = lvgl.PAD_LARGE, children = columns[c],};
                end
                return cols;
            end)(),
        },
        { type = "hline", w = widget.zone.w / 2, h = 1 },
        { type = "box", flexFlow = lvgl.FLOW_ROW, flexPad = lvgl.PAD_LARGE, children = {
                {type = "image", file = widget.dir .. "Logo_small_64_t.png", w = 32, h = 32},
                {type = "box", w = 40},
                {type = "button", text = "Settings", press = (function() widget.switchPage(widget.C.PAGE_SETTINGS, true); end)},
                {type = "button", text = "Global", press = (function() widget.switchPage(widget.C.PAGE_GLOBALS, true); end)},
                {type = "button", text = "Telemetry", press = (function() widget.switchPage(widget.C.PAGE_TELEMETRY, true); end)} 
            }
        }
    }}};
    uit[#uit + 1] = widget.saveIndicator();
    if (widget.settings.statusPassthru > 0) then
        for i = 1, 4 do
            uit[#uit + 1] = leftStatusBit(i);        
        end
        for i = 1, 4 do
            uit[#uit + 1] = rightStatusBit(i);        
        end
    end
    if (page ~= nil) then
        widget.ui = page:build(uit);        
    end
end
