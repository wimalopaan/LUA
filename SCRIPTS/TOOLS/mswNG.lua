-- TNS|MultiSwitchNG|TNE
-- SPDX-License-Identifier: GPL-3.0-or-later
-- Copyright (C) 2026 Wilhelm Meier

local app
local function init()
    local chunk, err = loadScript("/SCRIPTS/LIB/mswNG/app.lua", "btd")
    if not chunk then error(err or "mswNG/app.lua fehlt") end
    app = chunk(false)
    app.init()
end

return {init = init, run = function(event) return app.run(event) end}
