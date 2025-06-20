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

local function exportstring(s)
    return string.format("%q", s)
end

local function save(tbl, filename)
    local charS, charE = "   ", "\n"
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
--                    table.insert(tables, v)
                    tables[#tables+1] = v 
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
--                        table.insert(tables, i)
                        tables[#tables+1] = i 
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
--                            table.insert(tables, v)
                            tables[#tables+1] = v 
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

return {save = save};