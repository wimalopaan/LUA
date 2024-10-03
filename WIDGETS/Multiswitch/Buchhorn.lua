local config = {};

config.buttons = {
    [0] = { -- Adresse [0, 255]
        name = "Beleuchtung",
        [1] = {name = "Nautische", color = "COLOR_THEME_PRIMARY1", type = "toggle", icon = "", ls = 10},
        [2] = {name = "Blaulicht", color = "COLOR_THEME_PRIMARY2", type = "t", ls = 11},
        [3] = {name = "Ankerlicht", color = "COLOR_THEME_PRIMARY3", type = "t", ls = 12},
        [4] = {name = "Suchscheinwerfer", color = "COLOR_THEME_PRIMARY3", type = "t", ls = 13},
        [5] = {name = "Kabinenbel.", color = "COLOR_THEME_PRIMARY3", type = "t", ls = 14},
    },
    [2] = { -- Adresse [0, 255]
        name = "Sounds",
        [1] = {name = "Martinshorn", type = "momentary", ls = 20},
        [2] = {name = "Nebelhorn", type = "m", ls = 21},
    }
};
config.global = {
    intervall = 1000, -- milli seconds: state update intervall without action
};

return config;