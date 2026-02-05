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

local log = ... 

local function exportstring(s)
    return string.format("%q", s)
end

local charS, charE = "   ", "\n";

local S_IDLE = 0;
local S_SAVING = 1;
local S_ERROR = 2;
local s_state = S_IDLE;

local s_file;
local s_tables;
local s_lookup;
local s_i;

local function save_table(idx, t)
    local ef, es, en;
    ef, es, en = io.write(s_file, "-- Table: {" .. idx .. "}" .. charE)
    if (ef == nil) then
        log.log("save_table 1: %s, %d", es, en);
        return false;
    end
    ef, es, en = io.write(s_file, "{" .. charE)
    if (ef == nil) then
        log.log("save_table 2: %s, %d", es, en);
        return false;
    end
    local thandled = {}

    for i, v in ipairs(t) do
        thandled[i] = true
        local stype = type(v)
        -- only handle value
        if stype == "table" then
            if not s_lookup[v] then
                table.insert(s_tables, v)
                s_lookup[v] = #s_tables
            end
            ef, es, en = io.write(s_file, charS .. "{" .. s_lookup[v] .. "}," .. charE)
            if (ef == nil) then
                log.log("save_table 3: %s, %d", es, en);
                return false;
            end
        elseif stype == "string" then
            ef, es, en = io.write(s_file, charS .. exportstring(v) .. "," .. charE);
            if (ef == nil) then
                log.log("save_table 4: %s, %d", es, en);
                return false;
            end
        elseif stype == "number" then
            ef, es, en = io.write(s_file, charS .. tostring(v) .. "," .. charE)
            if (ef == nil) then
                log.log("save_table 5: %s, %d", es, en);
                return false;
            end
        elseif stype == "boolean" then
            ef, es, en = io.write(s_file, charS .. tostring(v) .. "," .. charE)
            if (ef == nil) then
                log.log("save_table 6: %s, %d", es, en);
                return false;
            end
        end
    end

    for i, v in pairs(t) do
        -- escape handled values
        if (not thandled[i]) then
            local str = ""
            local stype = type(i)
            -- handle index
            if stype == "table" then
                if not s_lookup[i] then
                    table.insert(s_tables, i)
                    s_lookup[i] = #s_tables
                end
                str = charS .. "[{" .. s_lookup[i] .. "}]="
            elseif stype == "string" then
                str = charS .. "[" .. exportstring(i) .. "]="
            elseif stype == "number" then
                str = charS .. "[" .. tostring(i) .. "]="
            end

            if str ~= "" then
                stype = type(v)
                -- handle value
                if stype == "table" then
                    if not s_lookup[v] then
                        table.insert(s_tables, v)
                        s_lookup[v] = #s_tables
                    end
                    ef, es, en = io.write(s_file, str .. "{" .. s_lookup[v] .. "}," .. charE)
                    if (ef == nil) then
                        log.log("save_table 7: %s, %d", es, en);
                        return false;
                    end
                elseif stype == "string" then
                    ef, es, en = io.write(s_file, str .. exportstring(v) .. "," .. charE)
                    if (ef == nil) then
                        log.log("save_table 8: %s, %d", es, en);
                        return false;
                    end
                elseif stype == "number" then
                    ef, es, en = io.write(s_file, str .. tostring(v) .. "," .. charE)
                    if (ef == nil) then
                        log.log("save_table 9: %s, %d", es, en);
                        return false;
                    end
                end
            end
        end
    end
    ef, es, en = io.write(s_file, "}," .. charE)
    if (ef == nil) then
        log.log("save_table 10: %s, %d", es, en);
        return false;
    end
    return true;
end
local function saveIncremental(tbl, filename)
    local ef, es, en;
    if (s_state == S_IDLE) then
        log.log("save_inc: IDLE: %s", filename);
        local err;
        s_file, err, en = io.open(filename, "wb")
        if (err) then 
            log.log("save_table open: %s, %d", err, en);
            s_state = S_ERROR;
            return false; 
        end
        s_tables, s_lookup = { tbl }, { [tbl] = 1 }
        ef, es, en = io.write(s_file, "return {" .. charE)
        if (ef == nil) then
            log.log("save_table 11: %s, %d", es, en);
            s_state = S_ERROR;
            return false;
        end
        s_state = S_SAVING;
        s_i = 0;
        return false;
    elseif (s_state == S_SAVING) then
        s_i = s_i + 1;
        local t = s_tables[s_i];
        log.log("save_inc: SAVE %d, %s", s_i, (t ~= nil));
        if (t) then
            local rs = save_table(s_i, t);
            if (not rs) then
                s_state = S_ERROR;
            end
            return false;
        else
            ef, es, en = io.write(s_file, "}\n--end\n");
            if (ef == nil) then
                log.log("save_table 12: %s, %d", es, en);
                s_state = S_ERROR;
                return false;
            end
            io.close(s_file);
            s_state = S_IDLE;
            return true;
        end
    elseif (s_state == S_ERROR) then
        log.log("save_table: ERROR state");
        if (s_file) then
            io.close(s_file);        
        end
        s_state = S_IDLE;
    end
end

local function save(tbl, filename)
--    local charS, charE = "   ", "\n"
    local file, err = io.open(filename, "wb")
    if err then return err end

    -- initiate variables for save procedure
    local tables, lookup = { tbl }, { [tbl] = 1 }
    io.write(file, "return {" .. charE)

    for idx, t in ipairs(tables) do
        io.write(file, "-- Table: {" .. idx .. "}" .. charE)
        io.write(file, "{" .. charE)
        local thandled = {}

        for i, v in ipairs(t) do
            thandled[i] = true
            local stype = type(v)
            -- only handle value
            if stype == "table" then
                if not lookup[v] then
                    table.insert(tables, v)
                    lookup[v] = #tables
                end
                io.write(file, charS .. "{" .. lookup[v] .. "}," .. charE)
            elseif stype == "string" then
                io.write(file, charS .. exportstring(v) .. "," .. charE)
            elseif stype == "number" then
                io.write(file, charS .. tostring(v) .. "," .. charE)
            elseif stype == "boolean" then
                io.write(file, charS .. tostring(v) .. "," .. charE)
            end
        end

        for i, v in pairs(t) do
            -- escape handled values
            if (not thandled[i]) then
                local str = ""
                local stype = type(i)
                -- handle index
                if stype == "table" then
                    if not lookup[i] then
                        table.insert(tables, i)
                        lookup[i] = #tables
                    end
                    str = charS .. "[{" .. lookup[i] .. "}]="
                elseif stype == "string" then
                    str = charS .. "[" .. exportstring(i) .. "]="
                elseif stype == "number" then
                    str = charS .. "[" .. tostring(i) .. "]="
                end

                if str ~= "" then
                    stype = type(v)
                    -- handle value
                    if stype == "table" then
                        if not lookup[v] then
                            table.insert(tables, v)
                            lookup[v] = #tables
                        end
                        io.write(file, str .. "{" .. lookup[v] .. "}," .. charE)
                    elseif stype == "string" then
                        io.write(file, str .. exportstring(v) .. "," .. charE)
                    elseif stype == "number" then
                        io.write(file, str .. tostring(v) .. "," .. charE)
                    end
                end
            end
        end
        io.write(file, "}," .. charE)
    end
    io.write(file, "}")
    io.close(file)
end

local function load(sfile)
    local ftables, err = loadfile(sfile)
    if err then return _, err end
    local tables = ftables()
    if (tables == nil) then
        return nil, "empty file";
    end
    for idx = 1, #tables do
        local tolinki = {}
        for i, v in pairs(tables[idx]) do
            if type(v) == "table" then
                tables[idx][i] = tables[v[1]]
            end
            if type(i) == "table" and tables[i[1]] then
                table.insert(tolinki, { i, tables[i[1]] })
            end
        end
        -- link indices
        for _, v in ipairs(tolinki) do
            tables[idx][v[2]], tables[idx][v[1]] = tables[idx][v[1]], nil
        end
    end
    return tables[1]
end

return {save = save, load = load, saveIncremental = saveIncremental};