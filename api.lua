local _, sc = ...;

-- WoW Forever (1.60.x, interface 16001) runs the Mainline client: the Classic
-- globals are gone and combat data can arrive as secret values. Everything the
-- addon needs from the client goes through this table. Nothing here is global;
-- files pull the functions they use into locals.

local api = {};
sc.api = api;

---------------------------------------------------------------------------------------------------
-- secret values

local issecretvalue = issecretvalue;

-- true when v may be used in arithmetic/comparisons
local function readable(v)
    return not (issecretvalue and issecretvalue(v));
end

-- plain number or the fallback, never a secret
local function num(v, fallback)
    if type(v) ~= "number" or not readable(v) then
        return fallback;
    end
    return v;
end

-- plain string or nil
local function str(v)
    if type(v) ~= "string" or not readable(v) then
        return nil;
    end
    return v;
end

-- plain boolean test; a secret counts as false
local function flag(v)
    if not readable(v) then
        return false;
    end
    return v and true or false;
end

api.readable = readable;
api.num = num;
api.str = str;
api.flag = flag;

function api.stats_restricted()
    return C_Secrets and C_Secrets.ShouldUnitStatsBeSecret and C_Secrets.ShouldUnitStatsBeSecret() or false;
end

function api.auras_restricted()
    return C_Secrets and C_Secrets.ShouldAurasBeSecret and C_Secrets.ShouldAurasBeSecret() or false;
end

---------------------------------------------------------------------------------------------------
-- spells

-- classic shape: name, rank, icon, cast_time_ms, min_range, max_range, spell_id
function api.GetSpellInfo(spell)
    if spell == nil then
        return nil;
    end
    local info = C_Spell.GetSpellInfo(spell);
    if not info then
        return nil;
    end
    return info.name, C_Spell.GetSpellSubtext(info.spellID), info.iconID,
        info.castTime, info.minRange, info.maxRange, info.spellID;
end

function api.GetSpellName(spell_id)
    return C_Spell.GetSpellName(spell_id);
end

function api.GetSpellTexture(spell)
    return C_Spell.GetSpellTexture(spell);
end

function api.GetSpellPowerCost(spell)
    return C_Spell.GetSpellPowerCost(spell);
end

function api.IsCurrentSpell(spell)
    return C_Spell.IsCurrentSpell(spell);
end

local bank_player = Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0;
local bank_pet = Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Pet or 1;

function api.IsSpellKnownOrOverridesKnown(spell_id, is_pet)
    return C_SpellBook.IsSpellKnownOrInSpellBook(spell_id, is_pet and bank_pet or bank_player, true);
end

function api.IsPlayerSpell(spell_id)
    return C_SpellBook.IsSpellKnown(spell_id, bank_player);
end

---------------------------------------------------------------------------------------------------
-- items

function api.GetItemInfo(item)
    if item == nil then
        return nil;
    end
    return C_Item.GetItemInfo(item);
end

function api.GetItemInfoInstant(item)
    if item == nil then
        return nil;
    end
    return C_Item.GetItemInfoInstant(item);
end

function api.GetItemIcon(item_id)
    if item_id == nil then
        return nil;
    end
    return C_Item.GetItemIconByID(item_id);
end

-- throws on slot names the client does not have
function api.GetInventorySlotInfo(slot_name)
    local ok, slot_id = pcall(C_PaperDollInfo.GetInventorySlotInfo, slot_name);
    if ok then
        return slot_id;
    end
    return nil;
end

local enchant_permanent = Enum.ItemEnchantType and Enum.ItemEnchantType.Permanent or 1;
local slot_mh = Enum.WeaponSlot and Enum.WeaponSlot.MainHand or 0;
local slot_oh = Enum.WeaponSlot and Enum.WeaponSlot.OffHand or 1;

-- temporary weapon enchant (oil, stone, poison, imbue) of one weapon slot:
-- has_enchant, time_left_ms, charges, enchant_id
local function temp_weapon_enchant(weapon_slot)
    local ok, enchants = pcall(C_Item.GetWeaponEnchantInfo, weapon_slot);
    if not ok or type(enchants) ~= "table" then
        return false;
    end
    for _, e in ipairs(enchants) do
        if e.hasEnchant and e.enchantType ~= enchant_permanent then
            return true, e.timeLeft, e.charges, e.enchantID;
        end
    end
    return false;
end

-- classic shape: has_mh, mh_time, mh_charges, mh_id, has_oh, oh_time, oh_charges, oh_id
function api.GetWeaponEnchantInfo()
    local has_mh, mh_time, mh_charges, mh_id = temp_weapon_enchant(slot_mh);
    local has_oh, oh_time, oh_charges, oh_id = temp_weapon_enchant(slot_oh);
    return has_mh, mh_time, mh_charges, mh_id, has_oh, oh_time, oh_charges, oh_id;
end

function api.GetCoinTextureString(copper)
    return C_CurrencyInfo.GetCoinTextureString(copper);
end

---------------------------------------------------------------------------------------------------
-- skills

function api.GetNumSkillLines()
    return C_SkillInfo.GetNumSkillLines() or 0;
end

-- classic shape: name, is_header, is_expanded, rank, temp_points, modifier, max_rank
function api.GetSkillLineInfo(index)
    local info = C_SkillInfo.GetSkillLineInfo(index);
    if not info then
        return nil;
    end
    return info.name, info.isHeader, not info.isCollapsed, info.rank, info.tempPoints, info.modifier, info.maxRank;
end

---------------------------------------------------------------------------------------------------
-- misc

function api.GetActiveTalentGroup()
    return C_SpecializationInfo.GetActiveSpecGroup() or 1;
end

-- the spellbook lives in a load-on-demand window on this client
function api.spellbook_frame()
    local frame = _G.PlayerSpellsFrame;
    return frame and frame.SpellBookFrame or nil;
end

function api.spellbook_shown()
    local book = api.spellbook_frame();
    return book and book:IsVisible() or false;
end

function api.getglobal(name)
    return _G[name];
end

function api.MouseIsOver(frame)
    return frame and frame:IsMouseOver() or false;
end

function api.IsAddOnLoaded(name)
    local loaded = C_AddOns.IsAddOnLoaded(name);
    return loaded and true or false;
end

-- melee skill is not exposed on this client; weapon skills come from the skill lines
function api.UnitDefense(unit)
    local base, mod = UnitDefenseSkill(unit);
    return num(base, nil), num(mod, 0);
end
