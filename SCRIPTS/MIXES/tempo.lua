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

-- ToDo:
-- restore the value smoothly instead of instantaneously

local input = {
    {"Input", SOURCE}, -- throttle input
    {"Button", SOURCE}, -- 3pos momentary button: "Set/+" and "Res/-"
    {"DeadB", VALUE, 0, 10, 1}, -- percent
    {"Adjust", VALUE, 1, 20, 10} -- percent adjustment for "Set/+" and "Res/-"
};
local output = {
    "Throttle", -- throttle output (with tempomat)
    "State" -- informative, maybe used to trigger voice anouncements
};
local thr_set = 0;
local state = 0;
local buttonstate = 0;
local function event(button)
    if (buttonstate == 0) then
        if (button > 0) then
            buttonstate = 1;
            return 1;
        elseif (button < 0) then
            buttonstate = 1;
            return -1;
        end
    elseif (buttonstate == 1) then
        if (button == 0) then
            buttonstate = 0;
        end
    end
    return 0;
end
local function run(input, button, deadband, adjust)
    local evt = event(button);
    if (state == 0) then -- off
        if (evt == 1) then
            if (input > (deadband * 10.24)) then
                state = 1;
                thr_set = input;                
            end
        elseif (evt == -1) then
            state = 1;
        end
        return input, 0;
    elseif (state == 1) then -- on
        if (input < -(deadband * 10.24)) then -- brake -> off
            state = 0;
            return input, 0;
        else 
            if (evt == 1) then
                thr_set = math.min(1024, thr_set + adjust * 10.24);
            elseif (evt == -1) then
                thr_set = math.max(-1024, thr_set - adjust * 10.24);
            end
        end
    end
    return math.max(thr_set, input), 102.4 * state;
end
return {
    input = input,
    run = run,
    output = output
};
