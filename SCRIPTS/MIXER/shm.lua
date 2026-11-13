local input = {
    {"Start", VALUE, 1, 11, 1}
};
local output = {
    "S1",
    "S2",
    "S3",
    "S4",
    "S5",
    "S6",
};
local function run(start)
    local s1 = getShmVar(start);
    local s2 = getShmVar(start + 1);
    local s3 = getShmVar(start + 2);
    local s4 = getShmVar(start + 3);
    local s5 = getShmVar(start + 4);
    local s6 = getShmVar(start + 5);
    return s1, s2, s3, s4, s5, s6;
end
return {
    input = input,
    run = run,
    output = output
};
