local _, sc = ...;

-- Recipes the character can still learn for its professions, for the spellbook
-- page. The recipe list and the skill a recipe item asks for come from the client
-- tables (Professions/recipes.lua, generated). The skill and price a trainer asks
-- for are server side: they are recorded whenever the player opens a profession
-- trainer, account-wide, since trainers ask every character the same.

local GetSpellName                              = sc.api.GetSpellName;
local IsPlayerSpell                             = sc.api.IsPlayerSpell;
local num                                       = sc.api.num;

-- skill-ups between "coming soon" and "not yet available"
local SOON_SKILL = 25;
-- skill cap a profession rank adds
local RANK_STEP = 75;

-- recipe spell -> its entry and skill line
local entries, line_of = {}, {};
for line, list in pairs(sc.recipes) do
    for _, entry in ipairs(list) do
        entries[entry[1]] = entry;
        line_of[entry[1]] = line;
    end
end

-- the saved defaults fill top-level keys only
local function store()
    local saved = SpellCodaForeverDB.profession_trainer;
    saved.spells = saved.spells or {};
    saved.lines = saved.lines or {};
    return saved;
end

-------------------------------------------------------------------------------
-- trainer recording

-- the skill line most of a trainer's known recipes belong to (rank spells and
-- recipes missing from the data go with it)
local function trainer_line(found)
    local votes, best = {}, nil;
    for spell in pairs(found) do
        local line = line_of[spell];
        if line then
            votes[line] = (votes[line] or 0) + 1;
            if not best or votes[line] > votes[best] then
                best = line;
            end
        end
    end
    return best;
end

-- what the open profession trainer teaches, with its current filters (the
-- default ones list everything not learned yet)
local function record_trainer()
    if not IsTradeskillTrainer() then
        return false;
    end
    local found = {};
    for i = 1, GetNumTrainerServices() or 0 do
        local _, service_type, _, level = GetTrainerServiceInfo(i);
        if service_type and service_type ~= "header" then
            local data = C_TooltipInfo.GetTrainerService(i);
            local spell = data and num(data.id, nil);
            if spell and spell > 0 then
                local _, skill = GetTrainerServiceSkillReq(i);
                -- what the recording character pays (its reputation discount included)
                found[spell] = {
                    skill = num(skill, 0),
                    cost = num((GetTrainerServiceCost(i)), 0),
                    level = num(level, 0),
                };
            end
        end
    end
    local line = trainer_line(found);
    if not line then
        return false;
    end
    local saved = store();
    for spell, info in pairs(found) do
        info.line = line_of[spell] or line;
        saved.spells[spell] = info;
    end
    -- only a full list tells what this trainer does not teach
    if GetTrainerServiceTypeFilter("available") and GetTrainerServiceTypeFilter("unavailable") then
        saved.lines[line] = true;
    end
    return true;
end

-------------------------------------------------------------------------------
-- the list

-- the character's professions: skill line -> name, skill, max skill. A
-- profession not learned has no cap (whether the client returns nil or zeros).
local function learned_lines()
    local lines = {};
    for line in pairs(sc.recipes) do
        local info = C_SkillInfo.GetSkillLineInfoByID(line);
        local rank = info and num(info.rank, nil);
        local max = info and num(info.maxRank, 0) or 0;
        if rank and max > 0 and info.name then
            lines[line] = { name = info.name, skill = rank, max = max };
        end
    end
    return lines;
end

-- every recipe of the character's professions it has not learned, the
-- professions, and whether there is any:
-- { spell, line, skill (nil: unknown), cost, level, item, low, key }, where key
-- is "available", "missing" (level), "soon", "later", "unknown" (no trainer of
-- the profession seen yet) or "elsewhere" (not taught by the trainers seen and
-- no recipe item)
local function list()
    local saved = store();
    local faction = UnitFactionGroup("player");
    local lvl = UnitLevel("player");
    local lines, rows = learned_lines(), {};
    local function add(spell, line, entry, trained)
        local prof = lines[line];
        if not prof or IsPlayerSpell(spell) or not GetSpellName(spell) then
            return;
        end
        if entry and entry[6] and entry[6] ~= faction then
            return;
        end
        local item = entry and entry[5] ~= 0 and entry[5] or nil;
        local skill = trained and trained.skill or (entry and entry[2] > 0 and entry[2]) or nil;
        local key;
        if not skill then
            key = saved.lines[line] and "elsewhere" or "unknown";
        elseif skill > prof.skill then
            key = skill <= prof.skill + SOON_SKILL and "soon" or "later";
        else
            key = trained and trained.level > lvl and "missing" or "available";
        end
        table.insert(rows, {
            spell = spell, line = line, profession = prof.name, skill = skill,
            -- a free trainer recipe has no price to show
            cost = trained and trained.cost > 0 and trained.cost or nil, level = trained and trained.level or 0,
            item = item, low = entry and entry[3] or (skill or 0), key = key,
        });
    end
    for line, recipes in pairs(sc.recipes) do
        if lines[line] then
            for _, entry in ipairs(recipes) do
                add(entry[1], line, entry, saved.spells[entry[1]]);
            end
        end
    end
    -- taught by a trainer but not in the data: mostly the profession ranks. A
    -- lower rank counts as unlearned once the next one is learned; a rank asks
    -- for at most 75 below the cap it raises, so one asking for less than that
    -- below the current cap is behind the character.
    for spell, trained in pairs(saved.spells) do
        local prof = lines[trained.line];
        if not entries[spell] and prof and trained.skill + RANK_STEP >= prof.max then
            add(spell, trained.line, nil, trained);
        end
    end
    table.sort(rows, function(a, b)
        local sa, sb = a.skill or a.low, b.skill or b.low;
        if sa ~= sb then
            return sa < sb;
        end
        if a.profession ~= b.profession then
            return a.profession < b.profession;
        end
        return a.spell < b.spell;
    end);
    return rows, lines, next(lines) ~= nil;
end

local listeners = {};
local frame = CreateFrame("Frame");
frame:RegisterEvent("TRAINER_SHOW");
frame:RegisterEvent("TRAINER_UPDATE");
-- service data that arrives after the trainer opened
frame:RegisterEvent("TRAINER_SERVICE_INFO_NAME_UPDATE");
frame:SetScript("OnEvent", function()
    if SpellCodaForeverDB and record_trainer() then
        for _, fn in ipairs(listeners) do
            fn();
        end
    end
end);

sc.professions = {
    list = list,
    -- fn runs after a trainer visit changed the recorded data
    on_change = function(fn)
        table.insert(listeners, fn);
    end,
};
