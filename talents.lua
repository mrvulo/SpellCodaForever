local _, sc                = ...;

local class                 = sc.class;
local config                = sc.config;
local apply_effect          = sc.loadouts.apply_effect;

local GetNumSkillLines      = sc.api.GetNumSkillLines;
local GetSkillLineInfo      = sc.api.GetSkillLineInfo;
local GetSpellName          = sc.api.GetSpellName;
---------------------------------------------------------------------------------------------------
local talents_export        = {};

local expansion_short = "classic";
if sc.expansion == sc.expansions.tbc then
    expansion_short = "tbc";
end

local function wowhead_talent_link(code)
    local lowercase_class = string.lower(class);
    return "https://wowhead.com/"..expansion_short.."/talent-calc/" .. lowercase_class .. "/" .. code;
end

local function wowhead_talent_code_from_url(link)
    local last_slash_index = 1;
    local i = 1;

    while link:sub(i, i) ~= "" do
        if link:sub(i, i) == "/" then
            last_slash_index = i;
        end
        i = i + 1;
    end
    return link:sub(last_slash_index + 1, i);
end

-- Forever keeps talents in a C_Traits tree instead of GetTalentInfo. Talents are
-- matched to the generated data by spell: every rank spell id of every talent,
-- and the talent's name as a fallback for trait definitions that point at a
-- different rank spell.
local talent_idx_by_spell = nil;
local talent_idx_by_lname = nil;

local function build_talent_lookups()
    talent_idx_by_spell = {};
    talent_idx_by_lname = {};
    for idx, ranks in pairs(sc.talent_ranks) do
        for rank, spell_id in pairs(ranks) do
            talent_idx_by_spell[spell_id] = { idx = idx, rank = rank };
        end
        if ranks[1] then
            local lname = GetSpellName(ranks[1]);
            if lname then
                talent_idx_by_lname[lname] = idx;
            end
        end
    end
end

local function active_talent_config_id()
    local group = C_SpecializationInfo.GetActiveSpecGroup and C_SpecializationInfo.GetActiveSpecGroup();
    local config_id;
    if group and C_SpecializationInfo.GetCombatConfigIDForSpecGroup then
        config_id = C_SpecializationInfo.GetCombatConfigIDForSpecGroup(group);
    end
    if not config_id and C_ClassTalents and C_ClassTalents.GetActiveConfigID then
        config_id = C_ClassTalents.GetActiveConfigID();
    end
    return config_id;
end

-- talent points by internal index (tree*100 + position), nil when not queryable yet
local function talent_points_by_idx()
    local config_id = active_talent_config_id();
    if not config_id then
        return nil;
    end
    local config_info = C_Traits.GetConfigInfo(config_id);
    if not config_info or not config_info.treeIDs then
        return nil;
    end
    if not talent_idx_by_spell then
        build_talent_lookups();
    end

    local pts_by_idx = {};
    for _, tree_id in pairs(config_info.treeIDs) do
        for _, node_id in pairs(C_Traits.GetTreeNodes(tree_id) or {}) do
            local node = C_Traits.GetNodeInfo(config_id, node_id);
            local rank = node and (node.currentRank or node.ranksPurchased) or 0;
            if rank > 0 and node.activeEntry and node.activeEntry.entryID then
                local entry = C_Traits.GetEntryInfo(config_id, node.activeEntry.entryID);
                local def = entry and entry.definitionID and C_Traits.GetDefinitionInfo(entry.definitionID);
                local spell_id = def and (def.spellID or def.overriddenSpellID);
                if spell_id then
                    local idx, pts;
                    local by_spell = talent_idx_by_spell[spell_id];
                    if by_spell then
                        -- the node rank decides; a definition may point at any rank spell
                        idx = by_spell.idx;
                        pts = rank;
                    else
                        local lname = GetSpellName(spell_id);
                        idx = lname and talent_idx_by_lname[lname];
                        pts = rank;
                    end
                    if idx then
                        local max_pts = #sc.talent_ranks[idx];
                        pts_by_idx[idx] = math.min(math.max(pts_by_idx[idx] or 0, pts), max_pts);
                    end
                end
            end
        end
    end
    return pts_by_idx;
end

local function wowhead_talent_code()
    local talent_code = "";

    local pts_by_idx = talent_points_by_idx() or {};

    local sub_codes = { "", "", "" };
    for i = 1, 3 do
        for pos = 1, #(sc.talent_order[i] or {}) do
            sub_codes[i] = sub_codes[i]..tostring(pts_by_idx[i*100 + pos] or 0);
        end
        local num_redundant = 0;
        local n = #sub_codes[i];
        for k = 1, n do
            if string.sub(sub_codes[i], n-k+1, n-k+1) == "0" then
                num_redundant = num_redundant + 1;
            else
                break;
            end
        end
        sub_codes[i] = string.sub(sub_codes[i], 1, n-num_redundant);
    end
    if sub_codes[2] == "" and sub_codes[3] == "" then
        talent_code = sub_codes[1];
    elseif sub_codes[2] == "" then
        talent_code = sub_codes[1] .. "--" .. sub_codes[3];
    elseif sub_codes[3] == "" then
        talent_code = sub_codes[1] .. "-" .. sub_codes[2];
    else
        talent_code = sub_codes[1] .. "-" .. sub_codes[2] .. "-" .. sub_codes[3];
    end

    return talent_code .. "_";
end

local function talent_pts(effects, idx)
    return effects.talent_pts[idx] or 0;
end

local function apply_talents(loadout, effects, wowhead_code, forced, undo)

    local i = 1;
    local tree_index = 1;
    local talent_index = 1;

    while wowhead_code:sub(i, i) ~= "" and wowhead_code:sub(i, i) ~= "_" do
        local next = wowhead_code:sub(i, i);
        local next_num = tonumber(next);
        if next == "-" then
            tree_index = tree_index + 1;
            talent_index = 1;
        elseif next_num then
            local pts = next_num;
            local pts_change;
            if undo then
                pts_change = -pts;
            else
                pts_change = pts;
            end
            local idx = tree_index*100 + talent_index;

            effects.talent_pts[idx] = (effects.talent_pts[idx] or 0) + pts_change;
            if pts > 0 and sc.talent_ranks[idx] then

                local effect_id = sc.talent_ranks[idx][pts];
                if effect_id then
                    apply_effect(effects,
                                 effect_id,
                                 sc.talent_effects[effect_id],
                                 forced,
                                 1,
                                 undo);
                end
            end

            talent_index = talent_index + 1;
        end
        i = i + 1;
    end


    if __spellcoda_test_all_data__ and not forced then
        -- Testing all special passives
        local passives_applied = 0;
        for id, e in pairs(sc.passives) do
            apply_effect(effects, id, e, true, 1, false, true, true);
            passives_applied = passives_applied + 1;
        end

        print(passives_applied, "gen passives applied");

        -- Testing all talents
        local applied = 0;
        for k, _  in pairs(sc.talent_ranks) do
            effects.talent_pts[k] = #sc.talent_ranks[k];
        end

        for _, v in pairs(sc.talent_ranks) do
            for _, i in pairs(v) do
                apply_effect(effects, i, sc.talent_effects[i], true, 1, false, true, true);
                applied = applied + 1;
            end
        end
        print(applied, "gen talents applied");

    end
end

local function loadout_talents_info(loadout)

    --loadout_front.talents.code = sc.talents.wowhead_talent_code();
    loadout.talents.code = wowhead_talent_code();

    -- weapon skills
    -- no talent config exists before the first talent point
    local success = GetNumSkillLines() ~= 0 and
        (active_talent_config_id() ~= nil or UnitLevel("player") < 10);
    for i = 1, GetNumSkillLines() do
        local skill_lname, _, _, skill = GetSkillLineInfo(i);
        local wep_subclass = skill_lname and sc.wpn_skill_lname_to_subclass[skill_lname];
        if wep_subclass and skill then
            loadout.wpn_skills[wep_subclass] = skill;
        end
    end

    if sc.core.addon_running_time < sc.core.login_grace_time and
        loadout.talents.code == "_" and
        UnitLevel("player") >= 10 then
        -- edge case when the talents query won't work shortly after logging in
        success = false;
    end

    return success;
end

---------------------------------------------------------------------------------------------------
talents_export.wowhead_talent_link = wowhead_talent_link
talents_export.wowhead_talent_code_from_url = wowhead_talent_code_from_url;
talents_export.wowhead_talent_code = wowhead_talent_code;
talents_export.loadout_talents_info = loadout_talents_info;
talents_export.talent_pts = talent_pts;
talents_export.apply_talents = apply_talents;

sc.talents = talents_export;
