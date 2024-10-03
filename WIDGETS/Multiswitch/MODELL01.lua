local config = {};

config.buttons = {
    [0] = { -- Adresse [0, 255]
        name = "Lichter",
        [1] = {name = "Top", color = "COLOR_THEME_PRIMARY1", type = "toggle", icon = "", ls = 10},
        [2] = {name = "Heck", color = "COLOR_THEME_PRIMARY2", type = "t", ls = 11},
        [3] = {name = "Bug", color = "COLOR_THEME_PRIMARY3", type = "t", ls = 12},
    },
    [2] = { -- Adresse [0, 255]
        name = "Geräusche",
        [1] = {name = "Sirene", type = "momentary", ls = 20},
        [2] = {name = "Horn", type = "m", ls = 21},
    };
};
config.global = {
    intervall = 1000, -- milli seconds: state update intervall without action 
};


return config;