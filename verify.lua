local _, sc = ...;

-- /sc verify [all]
-- Compares the addon's spell data (generated from the Classic Era client) with
-- what the Forever client itself says about the same spells: the numbers in
-- the spell description, the level the spell is learned at, cast time and
-- cost. The report goes into the copyable dump window.

local spells                    = sc.spells;
local spell_flags               = sc.spell_flags;
local comp_flags                = sc.comp_flags;

local num                       = sc.api.num;
local IsSpellKnownOrOverridesKnown = sc.api.IsSpellKnownOrOverridesKnown;

local verify = {};

-- components whose min/max are weapon multipliers, not absolute values
local weapon_comp_flags = bit.bor(
    comp_flags.applies_mh,
    comp_flags.applies_oh,
    comp_flags.applies_ranged,
    comp_flags.weapon_pct,
    comp_flags.base_weapon_dmg,
    comp_flags.coef_applied_to_avg_weapon_dmg,
    comp_flags.heal_to_full
);

local skip_spell_flags = bit.bor(
    spell_flags.alias,
    spell_flags.pet,
    spell_flags.base_mana_cost,
    spell_flags.uses_all_power
);

local function strip_markup(text)
    text = text:gsub("|c%x%x%x%x%x%x%x%x", "");
    text = text:gsub("|r", "");
    text = text:gsub("|T.-|t", "");
    text = text:gsub("|A.-|a", "");
    text = text:gsub("|H.-|h", "");
    text = text:gsub("|h", "");
    return text;
end

local function numbers_in(text)
    -- join thousands separators ("1.234" / "1,234") before splitting
    text = text:gsub("(%d)[%.,](%d%d%d)%f[%D]", "%1%2");
    local nums = {};
    for n in text:gmatch("%d+") do
        nums[#nums + 1] = tonumber(n);
    end
    return nums;
end

local function contains(nums, value)
    for _, n in ipairs(nums) do
        if math.abs(n - value) <= 1 then
            return true;
        end
    end
    return false;
end

local function lvl_diff(spell, lvl)
    return math.max(0, math.min(lvl - spell.lvl_req, spell.lvl_max - spell.lvl_req));
end

-- the absolute values a description of this spell should show, or nil
local function expected_values(spell, lvl)
    local exp = {};
    local direct = spell.direct;
    if direct and direct.per_lvl_sq == 0 and bit.band(direct.flags, weapon_comp_flags) == 0 then
        local d = lvl_diff(spell, lvl);
        local min = direct.min + direct.per_lvl * d;
        local max = direct.max + direct.per_lvl * d;
        if max > 1 then
            exp.direct = { min = math.floor(min), max = math.floor(max) };
        end
    end
    local periodic = spell.periodic;
    if periodic and periodic.per_lvl_sq == 0 and bit.band(periodic.flags, weapon_comp_flags) == 0 and
        periodic.tick_time and periodic.tick_time > 0 then

        local d = lvl_diff(spell, lvl);
        local tick = periodic.min + periodic.per_lvl * d;
        local ticks = math.floor(periodic.dur / periodic.tick_time + 0.5);
        if tick > 0 and ticks > 0 then
            exp.periodic = { tick = math.floor(tick), total = math.floor(tick * ticks), ticks = ticks };
        end
    end
    if not exp.direct and not exp.periodic then
        return nil;
    end
    return exp;
end

local function spell_label(spell_id)
    local name = C_Spell.GetSpellName(spell_id) or ("?"..spell_id);
    local sub = C_Spell.GetSpellSubtext(spell_id);
    if sub and sub ~= "" then
        name = name.." ("..sub..")";
    end
    return name.." ["..spell_id.."]";
end

local function check_spell(spell_id, spell, lvl, report)
    local problems = {};

    -- level the client teaches the spell at
    local learned = num(C_Spell.GetSpellLevelLearned(spell_id));
    if learned and learned > 0 and spell.lvl_req and learned ~= spell.lvl_req then
        problems[#problems + 1] = string.format("level: addon %d, client %d", spell.lvl_req, learned);
    end

    -- cast time (client value includes talents and haste)
    local info = C_Spell.GetSpellInfo(spell_id);
    -- ranged attacks (shoot, throw) cast in weapon speed, not a spell cast time
    local weapon_timed = bit.bor(spell_flags.channel, spell_flags.requires_ranged_slot, spell_flags.uses_attack_speed);
    if info and spell.cast_time and bit.band(spell.flags, weapon_timed) == 0 then
        local client_cast = num(info.castTime, 0)/1000;
        local addon_cast = spell.cast_time;
        if bit.band(spell.flags, spell_flags.instant) ~= 0 then
            addon_cast = 0;
        end
        if client_cast > 0 and math.abs(client_cast - addon_cast) > 0.05 then
            problems[#problems + 1] = string.format("cast time: addon %.2fs, client %.2fs (client includes talents)", addon_cast, client_cast);
        end
    end

    -- cost (client value includes talents)
    if spell.cost and spell.cost > 0 then
        local costs = C_Spell.GetSpellPowerCost(spell_id);
        local client_cost = costs and costs[1] and num(costs[1].cost);
        if client_cost and client_cost > 0 and math.abs(client_cost - spell.cost) > 0.5 then
            problems[#problems + 1] = string.format("cost: addon %d, client %d (client includes talents)", spell.cost, client_cost);
        end
    end

    -- values in the description
    local exp = expected_values(spell, lvl);
    local desc = C_Spell.GetSpellDescription(spell_id);
    local desc_state = "checked";
    if exp then
        if not desc or desc == "" then
            desc_state = "no description";
        else
            local nums = numbers_in(strip_markup(desc));
            if exp.direct then
                if not contains(nums, exp.direct.min) or not contains(nums, exp.direct.max) then
                    problems[#problems + 1] = string.format("direct: addon %d-%d not in description", exp.direct.min, exp.direct.max);
                end
            end
            if exp.periodic then
                if not contains(nums, exp.periodic.total) and not contains(nums, exp.periodic.tick) then
                    problems[#problems + 1] = string.format("periodic: addon %d total (%d x %d) not in description",
                        exp.periodic.total, exp.periodic.ticks, exp.periodic.tick);
                end
            end
        end
    else
        desc_state = "no absolute values";
    end

    -- buff values of the spell's own aura (percentages are stored as fractions)
    local auras = sc.class_buffs and sc.class_buffs[spell_id];
    if auras and desc and desc ~= "" then
        local nums = numbers_in(strip_markup(desc));
        local shown = {};
        for _, aura in ipairs(auras) do
            local value = aura[sc.aura_idx_value];
            if type(value) == "number" and value ~= 0 and aura[sc.aura_idx_iid] >= 0 then
                local v = math.abs(value);
                local found = contains(nums, v) or (v < 1 and contains(nums, v*100));
                shown[#shown + 1] = string.format("%s %s", tostring(value), found and "ok" or "MISSING");
                if not found then
                    problems[#problems + 1] = string.format("buff: addon value %s (%s) not in description",
                        tostring(value), tostring(aura[sc.aura_idx_effect]));
                end
            end
        end
        if #shown > 0 and desc_state ~= "checked" then
            desc_state = "checked";
        end
    end

    if #problems > 0 then
        report.mismatch = report.mismatch + 1;
        local lines = report.lines;
        lines[#lines + 1] = "MISMATCH "..spell_label(spell_id);
        for _, p in ipairs(problems) do
            lines[#lines + 1] = "  "..p;
        end
        if desc and desc ~= "" then
            lines[#lines + 1] = "  text: "..strip_markup(desc):gsub("\n", " ");
        end
        lines[#lines + 1] = "";
    elseif desc_state == "checked" then
        report.ok = report.ok + 1;
    else
        report.skipped = report.skipped + 1;
    end
end

local function collect(all)
    local ids = {};
    for id, spell in pairs(spells) do
        if bit.band(spell.flags, skip_spell_flags) == 0 and
            (all or IsSpellKnownOrOverridesKnown(id)) then
            ids[#ids + 1] = id;
        end
    end
    table.sort(ids, function(a, b)
        local sa, sb = spells[a], spells[b];
        if sa.lvl_req ~= sb.lvl_req then
            return sa.lvl_req < sb.lvl_req;
        end
        return a < b;
    end);
    return ids;
end

local running = false;

function verify.run(all)
    if running then
        return;
    end
    running = true;

    local ids = collect(all);
    -- descriptions are loaded on demand; ask for all of them, then read
    for _, id in ipairs(ids) do
        C_Spell.RequestLoadSpellData(id);
    end
    print(sc.core.addon_name..": verifying "..#ids.." spells...");

    C_Timer.After(2.0, function()
        running = false;
        local lvl = num(UnitLevel("player"), 1);
        local report = { ok = 0, mismatch = 0, skipped = 0, lines = {} };
        for _, id in ipairs(ids) do
            check_spell(id, spells[id], lvl, report);
        end

        local _, class = UnitClass("player");
        local header = {
            string.format("SpellCoda Forever verify - data %s, client %s, level %d %s, %s",
                sc.client_version_src, sc.client_version_loaded, lvl, class or "?",
                all and "all class spells" or "known spells"),
            string.format("checked %d: ok %d, mismatch %d, skipped %d (no absolute values or no description)",
                #ids, report.ok, report.mismatch, report.skipped),
            "",
        };
        local text = table.concat(header, "\n").."\n"..table.concat(report.lines, "\n");
        sc.ui.dump_text("SpellCoda verify", text, 700, 500);

        print(string.format("%s: verify done - ok %d, mismatch %d, skipped %d",
            sc.core.addon_name, report.ok, report.mismatch, report.skipped));
    end);
end

sc.verify = verify;
