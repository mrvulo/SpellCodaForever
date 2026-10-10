local _, sc = ...;

-- Weapon skills a class can learn from the weapon masters of its side, and
-- where those masters stand. Forever keeps Classic Era's weapon masters; it
-- lets rogues train one-handed axes and shamans two-handed axes and maces, and
-- its Stormwind map includes the harbor, which moves Woo Ping's coordinates.
-- Trainer lists are server side, so this is kept by hand.

local ONE_HANDED_AXES, TWO_HANDED_AXES = 196, 197;
local ONE_HANDED_MACES, TWO_HANDED_MACES = 198, 199;
local POLEARMS = 200;
local ONE_HANDED_SWORDS, TWO_HANDED_SWORDS = 201, 202;
local STAVES, BOWS, GUNS, DAGGERS = 227, 264, 266, 1180;
local THROWN, CROSSBOWS, FIST_WEAPONS = 2567, 5011, 15590;

local DEFAULT_COST = 1000;  -- 10 silver

-- skill spell id -> classes that can learn it, level, price; in display order
local skills = {
    { id = ONE_HANDED_AXES, classes = { WARRIOR = true, PALADIN = true, HUNTER = true, SHAMAN = true, ROGUE = true } },
    { id = TWO_HANDED_AXES, classes = { WARRIOR = true, PALADIN = true, HUNTER = true, SHAMAN = true } },
    { id = ONE_HANDED_MACES, classes = { WARRIOR = true, PALADIN = true, ROGUE = true, PRIEST = true, SHAMAN = true, DRUID = true } },
    { id = TWO_HANDED_MACES, classes = { WARRIOR = true, PALADIN = true, DRUID = true, SHAMAN = true } },
    { id = ONE_HANDED_SWORDS, classes = { WARRIOR = true, PALADIN = true, HUNTER = true, ROGUE = true, MAGE = true, WARLOCK = true } },
    { id = TWO_HANDED_SWORDS, classes = { WARRIOR = true, PALADIN = true, HUNTER = true } },
    { id = DAGGERS, classes = { WARRIOR = true, HUNTER = true, ROGUE = true, PRIEST = true, SHAMAN = true, DRUID = true, WARLOCK = true, MAGE = true } },
    { id = FIST_WEAPONS, classes = { WARRIOR = true, HUNTER = true, ROGUE = true, SHAMAN = true, DRUID = true } },
    { id = STAVES, classes = { WARRIOR = true, HUNTER = true, PRIEST = true, SHAMAN = true, DRUID = true, WARLOCK = true, MAGE = true } },
    { id = POLEARMS, classes = { WARRIOR = true, PALADIN = true, HUNTER = true, DRUID = true }, level = 20, cost = 10000 },
    { id = BOWS, classes = { WARRIOR = true, HUNTER = true, ROGUE = true } },
    { id = GUNS, classes = { WARRIOR = true, HUNTER = true, ROGUE = true } },
    { id = CROSSBOWS, classes = { WARRIOR = true, HUNTER = true, ROGUE = true } },
    { id = THROWN, classes = { WARRIOR = true, HUNTER = true, ROGUE = true } },
};

-- npc id -> side, town (area id, map id, coordinates), the town's faction
-- (reputation discount) and what the master teaches
local masters = {
    [11865] = { side = "Alliance", area = 1537, map = 1455, x = 61.2, y = 89.5, faction = 47, name = "Buliwyf Stonehand",
                teaches = { ONE_HANDED_AXES, TWO_HANDED_AXES, ONE_HANDED_MACES, TWO_HANDED_MACES, GUNS, FIST_WEAPONS } },
    [13084] = { side = "Alliance", area = 1537, map = 1455, x = 62.2, y = 89.6, faction = 47, name = "Bixi Wobblebonk",
                teaches = { DAGGERS, THROWN, CROSSBOWS } },
    [11867] = { side = "Alliance", area = 1519, map = 1453, x = 63.9, y = 69.1, faction = 72, name = "Woo Ping",
                teaches = { POLEARMS, ONE_HANDED_SWORDS, TWO_HANDED_SWORDS, STAVES, DAGGERS, CROSSBOWS } },
    [11866] = { side = "Alliance", area = 1657, map = 1457, x = 57.6, y = 46.7, faction = 69, name = "Ilyenia Moonfire",
                teaches = { STAVES, BOWS, DAGGERS, THROWN, FIST_WEAPONS } },
    [2704]  = { side = "Horde", area = 1637, map = 1454, x = 81.5, y = 19.6, faction = 530, name = "Hanashi",
                teaches = { ONE_HANDED_AXES, TWO_HANDED_AXES, STAVES, BOWS, THROWN } },
    [11868] = { side = "Horde", area = 1637, map = 1454, x = 81.7, y = 19.6, faction = 76, name = "Sayoc",
                teaches = { ONE_HANDED_AXES, TWO_HANDED_AXES, STAVES, BOWS, DAGGERS, THROWN, FIST_WEAPONS } },
    [11869] = { side = "Horde", area = 1638, map = 1456, x = 40.9, y = 62.7, faction = 81, name = "Ansekhwa",
                teaches = { ONE_HANDED_MACES, TWO_HANDED_MACES, STAVES, GUNS } },
    [11870] = { side = "Horde", area = 1497, map = 1458, x = 57.3, y = 32.8, faction = 68, name = "Archibald",
                teaches = { POLEARMS, ONE_HANDED_SWORDS, TWO_HANDED_SWORDS, DAGGERS, CROSSBOWS } },
};

-- the client's own name for an npc, once it has seen it; the English one before
local npc_names = {};
local function npc_name(npc)
    if npc_names[npc] then
        return npc_names[npc];
    end
    local info = C_TooltipInfo and C_TooltipInfo.GetHyperlink(string.format("unit:Creature-0-0-0-0-%d-0000000000", npc));
    local line = info and info.lines and info.lines[1];
    local name = line and line.leftText;
    if sc.api.readable(name) and type(name) == "string" and name ~= "" then
        npc_names[npc] = name;
        return name;
    end
    return masters[npc].name;
end

local function town_name(master)
    return C_Map.GetAreaInfo(master.area) or "";
end

-- the class's weapon skills, each with the masters of the player's side
local function list()
    local _, class = UnitClass("player");
    local side = UnitFactionGroup("player");
    local out = {};
    for _, skill in ipairs(skills) do
        if skill.classes[class] then
            local entry = { id = skill.id, level = skill.level or 1, cost = skill.cost or DEFAULT_COST, masters = {} };
            for npc, master in pairs(masters) do
                if master.side == side then
                    for _, taught in ipairs(master.teaches) do
                        if taught == skill.id then
                            table.insert(entry.masters, { npc = npc, data = master });
                        end
                    end
                end
            end
            table.sort(entry.masters, function(a, b)
                return town_name(a.data) < town_name(b.data);
            end);
            table.insert(out, entry);
        end
    end
    return out;
end

local function set_waypoint(master)
    local data = master.data;
    if not C_Map.CanSetUserWaypointOnMap(data.map) then
        return false;
    end
    local was_set = C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(data.map, data.x / 100, data.y / 100));
    if was_set == false then
        return false;
    end
    C_SuperTrack.SetSuperTrackedUserWaypoint(true);
    return true;
end

sc.weapon_skills = {
    list = list,
    npc_name = npc_name,
    town_name = town_name,
    set_waypoint = set_waypoint,
};
