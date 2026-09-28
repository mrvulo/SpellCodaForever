local _, sc               = ...;

local class               = sc.class;
local classes             = sc.classes;

local apply_effect        = sc.loadouts.apply_effect;

local has_enchant         = sc.equipment.has_enchant;

local config              = sc.config;

local GetSpellInfo        = sc.api.GetSpellInfo;
local readable            = sc.api.readable;
local auras_restricted    = sc.api.auras_restricted;

----------------------------------------------------------------------------------------------------
local buffs_export        = {};
local buff_category       = {
    class    = 1,
    player   = 2,
    hostile  = 3,
    friendly = 4,
    enchant  = 5,
};

local unique_buffs        = {};
local unique_target_buffs = {};

for k, _ in pairs(sc.class_buffs) do
    if not unique_buffs[k] then
        unique_buffs[k] = {
            id = k,
            lname = GetSpellInfo(k),
            cat = buff_category.class,
        };
    end
end
for k, _ in pairs(sc.player_buffs) do
    if not unique_buffs[k] then
        unique_buffs[k] = {
            id = k,
            lname = GetSpellInfo(k),
            cat = buff_category.player,
        };
    end
end
-- allows weapon enchant buffs to be registered as buffs
for k, _ in pairs(sc.enchant_effects) do

    if k > 0 and not unique_buffs[k] then
        unique_buffs[k] = {
            id = k,
            --lname = GetSpellInfo(sc.enchant_effects[k]),
            lname = GetSpellInfo(k),
            cat = buff_category.enchant,
        };
    end
end
for k, _ in pairs(sc.hostile_buffs) do
    if not unique_target_buffs[k] then
        unique_target_buffs[k] = {
            id = k,
            lname = GetSpellInfo(k),
            cat = buff_category.hostile,
        };
    end
end
for k, _ in pairs(sc.friendly_buffs) do
    if not unique_target_buffs[k] then
        unique_target_buffs[k] = {
            id = k,
            lname = GetSpellInfo(k),
            cat = buff_category.friendly,
        };
    end
end

local buffs        = {};
local target_buffs = {};

for k, v in pairs(unique_buffs) do
    table.insert(buffs, v);
end
for k, v in pairs(unique_target_buffs) do
    table.insert(target_buffs, v);
end

unique_buffs = nil;
unique_target_buffs = nil;

-- Last readable aura snapshot per unit. While auras are secret (combat) the
-- client refuses addon reads, so the snapshot taken before combat keeps
-- feeding the calculation.
local aura_snapshot = {
    player = { by_id = {}, by_lname = {}, name = nil },
    target = { by_id = {}, by_lname = {}, name = nil },
    mouseover = { by_id = {}, by_lname = {}, name = nil },
};

local function scan_filter(unit, filter, by_id, by_lname)
    local i = 1;
    while true do
        local aura = C_UnitAuras.GetAuraDataByIndex(unit, i, filter);
        if not aura then
            break;
        end
        local spell_id = aura.spellId;
        if readable(spell_id) and spell_id then
            local count = aura.applications;
            if not readable(count) or not count or count == 0 then
                count = 1;
            end
            -- player owned takes priority
            local source = aura.sourceUnit;
            local player_owned = readable(source) and source == "player";
            if not by_id[spell_id] or player_owned then
                local buff_info = { count = count, id = spell_id, player_owned = player_owned };
                by_id[spell_id] = buff_info;
                if readable(aura.name) and aura.name then
                    by_lname[aura.name] = buff_info;
                end
            end
        end
        i = i + 1;
    end
end

local function scan_unit(unit)
    local by_id, by_lname = {}, {};
    if not UnitExists(unit) then
        return true, by_id, by_lname;
    end
    local ok = pcall(scan_filter, unit, "HELPFUL", by_id, by_lname) and
        pcall(scan_filter, unit, "HARMFUL", by_id, by_lname);
    return ok, by_id, by_lname;
end

local function detect_buffs(loadout)

    local restricted = auras_restricted();

    for unit, snap in pairs(aura_snapshot) do
        local unit_name = loadout[unit.."_name"];
        if not restricted then
            local ok, by_id, by_lname = scan_unit(unit);
            if ok then
                snap.by_id = by_id;
                snap.by_lname = by_lname;
                snap.name = unit_name;
            end
        elseif snap.name ~= unit_name then
            -- different unit than the snapshot and nothing readable: assume no auras
            snap.by_id = {};
            snap.by_lname = {};
            snap.name = unit_name;
        end
        loadout.dynamic_buffs[unit] = snap.by_id;
        loadout.dynamic_buffs_lname[unit] = snap.by_lname;
    end

    if loadout.player_name == loadout.target_name then
        loadout.dynamic_buffs["target"] = loadout.dynamic_buffs["player"]
        loadout.dynamic_buffs_lname["target"] = loadout.dynamic_buffs_lname["player"]
    end
    if loadout.player_name == loadout.mouseover_name then
        loadout.dynamic_buffs["mouseover"] = loadout.dynamic_buffs["player"]
        loadout.dynamic_buffs_lname["mouseover"] = loadout.dynamic_buffs_lname["player"]
    end
    if loadout.target_name == loadout.mouseover_name then
        loadout.dynamic_buffs["mouseover"] = loadout.dynamic_buffs["target"]
        loadout.dynamic_buffs_lname["mouseover"] = loadout.dynamic_buffs_lname["target"]
    end
end

local function apply_buffs(loadout, effects, forced, undo)

    for k, v in pairs(loadout.dynamic_buffs["player"]) do
        if sc.class_buffs[k] then
            apply_effect(effects, k, sc.class_buffs[k], forced, v.count, undo, v.player_owned);
        elseif sc.player_buffs[k] then
            apply_effect(effects, k, sc.player_buffs[k], forced, v.count, undo, v.player_owned);
        end
    end
    for k, v in pairs(loadout.dynamic_buffs[loadout.friendly_towards]) do
        if sc.friendly_buffs[k] then
            apply_effect(effects, k, sc.friendly_buffs[k], forced, v.count, undo, v.player_owned);
        end
    end
    if loadout.hostile_towards ~= "" then
        for k, v in pairs(loadout.dynamic_buffs[loadout.hostile_towards]) do
            if sc.hostile_buffs[k] then
                apply_effect(effects, k, sc.hostile_buffs[k], forced, v.count, undo, v.player_owned);
            end
        end
    end

    -- some shapeshifts like stances cannot be detected as buff
    -- assigned from data override
    if sc.shapeshift_id_to_effects and sc.shapeshift_id_to_effects[loadout.shapeshift] then
        for _, k in pairs(sc.shapeshift_id_to_effects[loadout.shapeshift]) do
            apply_effect(effects, k, sc.shapeshift_passives[k], forced, 1, undo);
        end
    end

    if __spellcoda_test_all_data__ then
        -- Testing all buffs
        local buffs_applied = 0;
        for k, v in pairs(sc.player_buffs) do
            apply_effect(effects, k, v, true, 1, false, true);
            buffs_applied = buffs_applied + 1;
        end
        for k, v in pairs(sc.class_buffs) do
            apply_effect(effects, k, v, true, 1, false, true);
            buffs_applied = buffs_applied + 1;
        end
        for k, v in pairs(sc.friendly_buffs) do
            apply_effect(effects, k, v, true, 1, false, true);
            buffs_applied = buffs_applied + 1;
        end
        for k, v in pairs(sc.hostile_buffs) do
            apply_effect(effects, k, v, true, 1, false, true);
            buffs_applied = buffs_applied + 1;
        end
        print(buffs_applied, "gen buffs applied");
    end
end

local function apply_fake_buffs(loadout, effects, buffs_cfg)

    local preserve = buffs_cfg.preserve_active;
    if not preserve then
        apply_buffs(loadout, effects, true, true);
    end

    for k, cnt in pairs(buffs_cfg.player_buffs) do
        if not preserve or not loadout.dynamic_buffs["player"][k] then
            if sc.class_buffs[k] then
                apply_effect(effects, k, sc.class_buffs[k], true, cnt, false, true);
            elseif sc.player_buffs[k] then
                apply_effect(effects, k, sc.player_buffs[k], true, cnt, false, true);
            elseif sc.enchant_effects[k] then
                apply_effect(effects, k, sc.enchant_effects[k], true, cnt, false, true);
            end
        end
    end
    for k, cnt in pairs(buffs_cfg.target_buffs) do
        if not preserve or
            (not loadout.dynamic_buffs[loadout.friendly_towards][k]
            and
            (loadout.hostile_towards == "" or not loadout.dynamic_buffs[loadout.hostile_towards][k])) then
            if sc.friendly_buffs[k] then
                apply_effect(effects, k, sc.friendly_buffs[k], true, cnt, false, true);
            end
            if sc.hostile_buffs[k] then
                apply_effect(effects, k, sc.hostile_buffs[k], true, cnt, false, true);
            end
        end
    end
end

local sandbox_buffs_cfg;
local function post_login_load()
    sandbox_buffs_cfg = __sc_frame.calculator_frame.buffs.working;
end

local function get_buff_by_lname(loadout, unit, lname, only_self_buff, require_ownership)

    if unit ~= "" and
        (not loadout.calculator_mode or not sandbox_buffs_cfg.use_custom or sandbox_buffs_cfg.preserve_active) then

        local buff = loadout.dynamic_buffs_lname[unit][lname];
        if buff and (not require_ownership or buff.player_owned) then
            return buff.id;
        end
    end
    if loadout.calculator_mode and
        sandbox_buffs_cfg.use_custom and
        sc.ui.forced_buffs_lname_to_id[lname] and
         ((only_self_buff and
            sandbox_buffs_cfg.player_buffs[sc.ui.forced_buffs_lname_to_id[lname]])
            or
            sandbox_buffs_cfg.target_buffs[sc.ui.forced_buffs_lname_to_id[lname]]) then

        return sc.ui.forced_buffs_lname_to_id[lname]
    end

    return nil;
end

local function get_buff(loadout, unit, id, only_self_buff, require_ownership)

    if unit ~= "" and
        (not loadout.calculator_mode or not sandbox_buffs_cfg.use_custom or sandbox_buffs_cfg.preserve_active) then

        local buff = loadout.dynamic_buffs[unit][id];
        if buff and (not require_ownership or buff.player_owned) then
            return buff.id;
        end
    end

    if loadout.calculator_mode and
        sandbox_buffs_cfg.use_custom and
         ((only_self_buff and sandbox_buffs_cfg.player_buffs[id]) or
            sandbox_buffs_cfg.target_buffs[id]) then

        return id;
    end

    return nil;
end

----------------------------------------------------------------------------------------------------
buffs_export.buff_category                      = buff_category;
buffs_export.buffs                              = buffs;
buffs_export.target_buffs                       = target_buffs;
buffs_export.detect_buffs                       = detect_buffs;
buffs_export.apply_buffs                        = apply_buffs;
buffs_export.apply_fake_buffs                   = apply_fake_buffs;
buffs_export.get_buff                           = get_buff;
buffs_export.get_buff_by_lname                  = get_buff_by_lname;
buffs_export.post_login_load                    = post_login_load;

sc.buffs = buffs_export;
