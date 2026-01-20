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

local env = ...

local ui = {
    global = {},
    pages = {
        -- {script = "", parent = "", data = {}}
    },
    activePage = nil,
    activeContent = nil;
    
    textGap = 5,
    defaultSize = {
        w = 50,
        h = 10,
    },
    switchIndexNone = 1;
};
local switchTab = (function()
    local t = {};
    for i, _ in switches() do
        t[#t+1] = {number = i};
        if (i == 0) then
            ui.switchIndexNone = #t;
        end
    end
    return t;
end)();
local textEdit = {
    stringPossibleChars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_#-. ",
    maxStringLength = 8,
};
local function incrCharInTextField(self, step)
    local text = self.text();
    local c = string.sub(text, self.fieldIndex, self.fieldIndex)
    local idx = string.find(textEdit.stringPossibleChars, c, 1, true)
    idx = (idx + step + #textEdit.stringPossibleChars - 1) % #textEdit.stringPossibleChars + 1 
    c = string.sub(textEdit.stringPossibleChars, idx, idx)
    text = string.sub(text, 1, self.fieldIndex - 1) .. c .. string.sub(text, self.fieldIndex + 1, string.len(text))
    self.set(text);
end
local function textEditEvent(self, event)
    if (event == EVT_VIRTUAL_ENTER) then
        self.editing = not self.editing;
        event = 0;
    elseif (self.editing) and (event == EVT_VIRTUAL_INC) then
        incrCharInTextField(self, 1);
        event = 0;
    elseif (self.editing) and (event == EVT_VIRTUAL_DEC) then
        incrCharInTextField(self, -1);
        event = 0;
    elseif (event == EVT_VIRTUAL_PREV) then
        if (self.editing) then
            self.fieldIndex = (self.fieldIndex - 1 - 1) % textEdit.maxStringLength + 1;
            event = 0;
        else
            self.fieldIndex = 1;
        end
    elseif (event == EVT_VIRTUAL_NEXT) or (event == EVT_VIRTUAL_MENU) then
        if (self.editing) then
            self.fieldIndex = (self.fieldIndex - 1 + 1) % textEdit.maxStringLength + 1;
            event = 0;
        else
            self.fieldIndex = 1;
        end
    end
    return event;
end
local function numberEditEvent(self, event)
    if (event == EVT_VIRTUAL_ENTER) then
        self.editing = not self.editing;
        event = 0;
    elseif (self.editing) and (event == EVT_VIRTUAL_INC) then
        local value = self.value();
        value = value + 1;
        if (value >= self.max) then
            value = self.max;
        end
        self.set(value);
        event = 0;
    elseif (self.editing) and (event == EVT_VIRTUAL_DEC) then
        local value = self.value();
        value = value - 1;
        if (value <= self.min) then
            value = self.min;
        end
        self.set(value);
        event = 0;
    elseif (self.editing) and (event == EVT_VIRTUAL_MENU) then
        self.set(self.max);
        event = 0;
    end
    return event;
end
local function choiceEvent(self, event)
    if (event == EVT_VIRTUAL_ENTER) then
        self.editing = not self.editing;
        event = 0;
    elseif (self.editing) and (event == EVT_VIRTUAL_INC) then
        local value = self.index();
        value = value + 1;
        if (value >= #self.values) then
            value = #self.values;
        end
        self.set(value);
        event = 0;
    elseif (self.editing) and (event == EVT_VIRTUAL_DEC) then
        local value = self.index();
        value = value - 1;
        if (value <= 0) then
            value = 1;
        end
        self.set(value);
        event = 0;
    end
    return event;
end
local function switchSelectEvent(self, event)
    if (event == EVT_VIRTUAL_ENTER) then
        self.editing = not self.editing;
        event = 0;
    elseif (self.editing) and (event == EVT_VIRTUAL_INC) then
        local value = self.value();
        value = value + 1;
        if (value >= #switchTab) then
            value = #switchTab;
        end
        self.set(value);
        event = 0;
    elseif (self.editing) and (event == EVT_VIRTUAL_DEC) then
        local value = self.value();
        value = value - 1;
        if (value <= 0) then
            value = 1;
        end
        self.set(value);
        event = 0;
    end
    return event;
end
local function drawButton(self)
    local flags = 0;
    if (self.active) then
        if (self.active()) then
            if (GREY ~= nil) then
                flags = flags + GREY(8);            
            end
        end
    end
    if (self.state() > 0) then
        flags = flags + INVERS;
    end
    if (self == ui.activeContent.activeItem) then
        flags = flags + BLINK;
    end
    local text = self.text();
    local swindex = self.switch();
    if (swindex ~= ui.switchIndexNone) then
        lcd.drawText(self.x + ui.activeContent.x_offset, self.y + ui.activeContent.y_offset, text, flags);
        local swname = getSwitchName(switchTab[swindex].number);
        lcd.drawText(lcd.getLastPos() + ui.textGap, self.y + ui.activeContent.y_offset, swname, SMLSIZE);
    else
        lcd.drawText(self.x + ui.activeContent.x_offset, self.y + ui.activeContent.y_offset, text, flags);
    end
end
local function drawPressButton(self)
    local flags = 0;
    if (self == ui.activeContent.activeItem) then
        flags = flags + BLINK;
    end
    local text = self.text();
    lcd.drawText(self.x + ui.activeContent.x_offset, self.y + ui.activeContent.y_offset, text, flags);
end
local function drawLabel(self)
    local text = self.text();
    lcd.drawText(self.x + ui.activeContent.x_offset, self.y + ui.activeContent.y_offset, text);
end
local function drawNumberEdit(self)
    local flags = 0;
    if (self == ui.activeContent.activeItem) then
        flags = flags + BLINK;
    end
    if (self.editing) then
        flags = flags + INVERS;
    end
    local value = self.value();
    lcd.drawText(self.x + ui.activeContent.x_offset, self.y + ui.activeContent.y_offset, value, flags);
end
local function drawChoice(self)
    local flags = 0;
    if (self == ui.activeContent.activeItem) then
        flags = flags + BLINK;
    end
    if (self.editing) then
        flags = flags + INVERS;
    end
    local index = self.index();
    local text = self.values[index];
    lcd.drawText(self.x + ui.activeContent.x_offset, self.y + ui.activeContent.y_offset, text, flags);
end
local function drawTextEdit(self)
    local flags = 0;
    if (self == ui.activeContent.activeItem) then
        flags = flags + BLINK;
    end
    if (self.editing) then
        flags = flags + INVERS;
    end
    local text = self.text();
    lcd.drawText(self.x + ui.activeContent.x_offset, self.y + ui.activeContent.y_offset, text, flags);
end
local function drawSwitchSelect(self)
    local flags = 0;
    if (self == ui.activeContent.activeItem) then
        flags = flags + BLINK;
    end
    if (self.editing) then
        flags = flags + INVERS;
    end
    local index = self.value();
    local sw = switchTab[index].number;
    lcd.drawSwitch(self.x + ui.activeContent.x_offset, self.y + ui.activeContent.y_offset, sw, flags);
end
function ui.getSwitchValue(index)
    local sw = switchTab[index].number;
    return getSwitchValue(sw);
end
local function insert(table, item)
    item.next = item;    
    item.prev = item;
    item.siblings = 1;
    item.sibling  = 1;
    for _, p in pairs(table) do
        if ((p.parent == item.parent) and (p.sibling == p.siblings)) then
            local p_next = p.next;
            p.next = item;
            item.next = p_next;
            item.prev = p;
            p_next.prev = item;
            item.sibling = p.sibling + 1;
            item.siblings = p.siblings + 1;
            local ii = item.next;
            while (ii ~= item) do
                ii.siblings = item.siblings; 
                ii = ii.next;
            end
            break;
        end
    end
    table[#table+1] = item;
    return item;
end
local function emptyItem()
    local item = {};
    item.next = item;
    item.prev = item;
    return item;
end
function ui:setupPage(page) 
    page.x_offset = 0;
    page.y_offset = 10;
    page.activeItem = emptyItem();
    page.items = {};
    page.unfocus_items = {};
    function page:addStateButton(params)
        params.draw = drawButton;
        self.activeItem = insert(self.items, params);
    end;
    function page:addButton(params) 
        params.draw = drawPressButton;
        self.activeItem = insert(self.items, params);
    end;
    function page:addNumberEdit(params) 
        params.draw = drawNumberEdit;
        params.handleEvent = numberEditEvent;
        params.editing = false;
        self.activeItem = insert(self.items, params);
    end;
    function page:addChoice(params) 
        params.draw = drawChoice;
        params.handleEvent = choiceEvent;
        params.editing = false;
        self.activeItem = insert(self.items, params);
    end;
    function page:addSwitchSelect(params) 
        params.draw = drawSwitchSelect;
        params.handleEvent = switchSelectEvent;
        params.editing = false;
        self.activeItem = insert(self.items, params);
    end;
    function page:addTextEdit(params) 
        params.draw = drawTextEdit;
        params.handleEvent = textEditEvent;
        params.fieldIndex = 1;
        params.editing = false;
        self.activeItem = insert(self.items, params);
    end;
    function page:addLabel(params)
        params.draw = drawLabel;
        insert(self.unfocus_items, params);
    end;
    self.activeContent = page;
    return page;
end
local function findEqualPage(p)
    for _, pp in pairs(ui.pages) do
        if ((p.script == pp.script) and (p.instance == pp.instance)) then
            return pp;
        end
    end
    return nil;
end
function ui.addPage(params) 
    local p = findEqualPage(params);
    if (p ~= nil) then
        print("found:", p);
        return p;
    else
        return insert(ui.pages, params);
    end
end
local function drawactiveContent()
	lcd.clear();
    if (ui.activeContent.name ~= nil) then
        local name = ui.activeContent.name();
        lcd.drawScreenTitle(name, ui.activePage.sibling, ui.activePage.siblings);        
    end
    for _, item in ipairs(ui.activeContent.items) do
        item:draw();
    end
    for _, item in pairs(ui.activeContent.unfocus_items) do
        item:draw();
    end
end
local function handleEvent(event)
    if (ui.activeContent.activeItem.handleEvent ~= nil) then
        event = ui.activeContent.activeItem:handleEvent(event);
    end
    if (event == EVT_VIRTUAL_NEXT or event == EVT_VIRTUAL_NEXT_REPT) then
        ui.activeContent.activeItem = ui.activeContent.activeItem.next;
    elseif (event == EVT_VIRTUAL_PREV or event == EVT_VIRTUAL_PREV_REPT) then
        ui.activeContent.activeItem = ui.activeContent.activeItem.prev;
    elseif (event == EVT_VIRTUAL_ENTER) then
        if (ui.activeContent.activeItem.press ~= nil) then
            ui.activeContent.activeItem.press();
        end
    elseif (event == EVT_VIRTUAL_MENU) then
        ui.activate(ui.activePage.next);
    elseif (event == EVT_VIRTUAL_EXIT) then
        if (ui.activePage.parent ~= nil) then
            ui.activate(ui.activePage.parent);
        end
    end
end
function ui.initGlobal(script)
    local initscript = loadScript(env.dir .. script, "btd");
    if (initscript ~= nil) then
        local t = initscript(ui, env);
        if (t.init ~= nil) then
            ui.global = t.init();        
        end
    end
    initscript = nil;
    collectgarbage("collect");
end
local function loadPage(page)
    local pagescript = loadScript(env.dir .. page.script, "btd");
    if (pagescript ~= nil) then
        local p = pagescript(ui, env);
        p.init(page.instance, page.parent, page);
    end
end
function ui.activate(page)
    if (ui.activeContent ~= nil) then
        ui.activeContent = nil;
        collectgarbage("collect");
    end
    ui.activePage = page;
    loadPage(page);
end
function ui.addBackground(script)
    local bg = loadScript(env.dir .. script, "btd");
    if (bg ~= nil) then
        local p = bg(ui, env);
        p.init();
        p.init = nil;
        collectgarbage("collect");
        ui.background_script = p;
    end
end
local iCounter = 0;
local lastTime = getTime();
local timeout = 10;
function ui.background()
    if ((getTime() - lastTime) > timeout) then
        lastTime = getTime();
        if (iCounter == 0) then
            ui.activeContent = nil;
            collectgarbage("collect");
        else
            iCounter = 0;
        end
    end
    if (ui.background_script ~= nil) then
        ui.background_script.background();
    end
end
function ui.update() 
    if (ui.background_script ~= nil) then
        ui.background_script.update();
    end
end
function ui.run(event)
    iCounter = iCounter + 1;
    if (ui.activeContent == nil) then
        loadPage(ui.activePage);
    else
        drawactiveContent();
        handleEvent(event);
    end
end

return ui;