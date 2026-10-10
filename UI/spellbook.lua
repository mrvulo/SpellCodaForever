local _, sc = ...;

-- SpellCoda's page in the spellbook: a tab in the row of the book's category
-- tabs that lays a parchment page over the book, listing every spell the
-- character can still learn, grouped by when it can be learned. Nothing
-- Blizzard owns is written to; tab, pages and covers are frames of our own
-- parented to the spellbook window.

local L                                         = sc.L;
local spells                                    = sc.spells;
local spell_flags                               = sc.spell_flags;
local GetSpellInfo                              = sc.api.GetSpellInfo;
local GetSpellTexture                           = sc.api.GetSpellTexture;
local GetCoinTextureString                      = sc.api.GetCoinTextureString;
local IsSpellKnownOrOverridesKnown              = sc.api.IsSpellKnownOrOverridesKnown;
local highest_learned_rank                      = sc.utils.highest_learned_rank;

-------------------------------------------------------------------------------
local skin = {
    icon        = "Interface\\AddOns\\SpellCodaForever\\Media\\icon",
    tab         = "spellbook-Tab-Frame-C60",
    tab_active  = "spellbook-Tab-Frame-Glow-C60",
    tab_glow    = "spellbook-Tab-Frame-glow-gradient-C60",
    page_left   = "spellbook-Page-Left-C60",
    page_right  = "spellbook-Page-Right-C60",
    band        = "Interface\\AchievementFrame\\UI-Achievement-Parchment-Horizontal-Desaturated",
    icon_border = "Interface\\Buttons\\UI-Quickslot2",
};

-- the tab row, search box and settings dropdown sit in the book's top 60px;
-- the native spell views are 680 wide, so each page is a 696 wide column
-- around one of them
local HEADER_HEIGHT = 60;
local PAGE_WIDTH, PAGE_TOP, PAGE_BOTTOM = 696, -90, 15;
local LIST_TOP, LIST_BOTTOM = -87, 46;
local ROW_HEIGHT, HEADING_HEIGHT, HEADING_GAP = 28, 32, 8;
local SCROLL_STEP = 3;

local colors = {
    backing     = {0.10, 0.07, 0.035},
    body        = {0.19, 0.12, 0.06},
    separator   = {0.30, 0.19, 0.08, 0.18},
    highlight   = {1, 0.85, 0.50, 0.08},
    shadow      = {0, 0, 0, 1},
    -- band tint, then text color
    sections = {
        available = {0.12, 0.24, 0.08, 0.65, 1, 0.40},
        missing   = {0.32, 0.15, 0.03, 1, 0.82, 0.30},
        soon      = {0.08, 0.18, 0.29, 0.55, 0.84, 1},
        later     = {0.30, 0.07, 0.04, 1, 0.55, 0.45},
        ignored   = {0.20, 0.17, 0.12, 0.75, 0.75, 0.75},
    },
    level_missing = {0.55, 0.30, 0.02},
    level_soon  = {0.08, 0.22, 0.50},
    level_later = {0.45, 0.09, 0.04},
    dim         = {0.40, 0.40, 0.40},
};

local section_order = { "available", "missing", "soon", "later", "ignored" };
local section_names = {
    available = "Now available",
    missing = "Missing requirement",
    soon = "Coming soon",
    later = "Not yet available",
    ignored = "Ignored",
};

local book, root, launcher, attic, return_tab, pages, search, settings;
local covers = {};
local active, shown_tab, queued = false, nil, false;
local items, offset = {}, 1;
local show_ignored = false;

-------------------------------------------------------------------------------
-- trainer prices

-- The data carries base prices. Class trainers take 10% off from Honored with
-- the faction of their town (Forever 1.60.1; Revered and Exalted not checked).
-- Factions of the towns that train each class, per side.
local trainer_factions = {
    DRUID   = { Alliance = {69, 72, 609, 2740}, Horde = {81, 609, 2787} },
    HUNTER  = { Alliance = {47, 69, 72}, Horde = {76, 81, 530} },
    MAGE    = { Alliance = {47, 54, 69, 72, 2740}, Horde = {68, 76, 530} },
    PALADIN = { Alliance = {47, 72}, Horde = {68} },
    PRIEST  = { Alliance = {47, 54, 69, 72}, Horde = {68, 76, 530} },
    ROGUE   = { Alliance = {21, 47, 54, 69, 72, 349}, Horde = {21, 68, 76, 81, 349, 530} },
    SHAMAN  = { Alliance = {47}, Horde = {76, 81, 2787} },
    WARLOCK = { Alliance = {47, 54, 72}, Horde = {68, 76} },
    WARRIOR = { Alliance = {47, 54, 69, 72}, Horde = {68, 76, 81} },
};
local HONORED, DISCOUNT_PCT = 6, 10;

-- {name, standing label, pct} per trainer town, best discount first
local function discount_options()
    local _, class = UnitClass("player");
    local by_side = trainer_factions[class];
    local keys = by_side and by_side[UnitFactionGroup("player")] or {};
    local options = {};
    for _, key in ipairs(keys) do
        local data = C_Reputation.GetFactionDataByID(key);
        if data and data.name then
            local standing = data.reaction or 4;
            table.insert(options, {
                name = data.name,
                standing = _G["FACTION_STANDING_LABEL"..standing] or "",
                pct = standing >= HONORED and DISCOUNT_PCT or 0,
            });
        end
    end
    table.sort(options, function(a, b)
        if a.pct ~= b.pct then
            return a.pct > b.pct;
        end
        return a.name < b.name;
    end);
    return options;
end

local function best_discount()
    local best = discount_options()[1];
    return best and best.pct or 0, best and best.name;
end

local function discounted(cost, pct)
    return math.floor((cost * (100 - pct) + 50) / 100);
end

local function hide_tooltip(self)
    if GameTooltip:IsOwned(self) then
        GameTooltip:Hide();
    end
end

local function enabled()
    return sc.config.settings.general_spellbook_button;
end

-------------------------------------------------------------------------------
-- data

local function spell_known(id)
    if IsSpellKnownOrOverridesKnown(id) or IsSpellKnownOrOverridesKnown(id, true) then
        return true;
    end
    -- lower ranks are unlearned once a higher rank is known
    local highest = highest_learned_rank(spells[id].base_id);
    return highest ~= nil and spells[highest] ~= nil and spells[highest].rank > spells[id].rank;
end

-- a spell this character could still learn from a trainer or a book
local function learnable(id)
    local spell = spells[id];
    -- in the data but not on this client
    if not spell or spell.train == 0 or not GetSpellInfo(id) then
        return false;
    end
    if bit.band(spell.flags, bit.bor(spell_flags.talent, spell_flags.pet)) ~= 0 then
        return false;
    end
    if spell.race_flags and bit.band(spell.race_flags, bit.lshift(1, sc.race-1)) == 0 then
        return false;
    end
    return not spell_known(id);
end

local function ignored(id)
    return sc.config.settings.spells_ignore_list[id] ~= nil;
end

-- the rank before id when that one is not learned yet (trainers ask for it)
local function missing_rank(id)
    local seq = sc.rank_seqs[spells[id].base_id];
    if not seq then
        return nil;
    end
    for i, rank_id in ipairs(seq) do
        if rank_id == id then
            local prev = seq[i - 1];
            if prev and spells[prev] and not spell_known(prev) then
                return prev;
            end
            return nil;
        end
    end
    return nil;
end

local function matches_search(id)
    local text = search and search:GetText() or "";
    if text == "" then
        return true;
    end
    local name = GetSpellInfo(id);
    return name ~= nil and string.find(string.lower(name), string.lower(text), 1, true) ~= nil;
end

-- items: section headings followed by their spells, in level order.
-- Returns the trainer prices of everything learnable now, search or not:
-- trainers round each spell's discount on its own, so the total sums them.
local function build_items()
    local lvl = UnitLevel("player");
    local next_lvl = lvl % 2 == 0 and lvl + 2 or lvl + 1;
    local sections = { available = {}, missing = {}, soon = {}, later = {}, ignored = {} };
    local available_costs = {};

    for _, id in ipairs(sc.spells_lvl_ordered) do
        if learnable(id) then
            local req = spells[id].lvl_req;
            local key;
            if ignored(id) then
                key = show_ignored and "ignored" or nil;
            elseif req <= lvl then
                key = missing_rank(id) and "missing" or "available";
            else
                key = req <= next_lvl and "soon" or "later";
            end
            if key == "available" and spells[id].train > 0 then
                table.insert(available_costs, spells[id].train);
            end
            if key and matches_search(id) then
                table.insert(sections[key], id);
            end
        end
    end

    items = {};
    for _, key in ipairs(section_order) do
        if #sections[key] > 0 then
            table.insert(items, { heading = key, count = #sections[key] });
            for _, id in ipairs(sections[key]) do
                table.insert(items, { spell_id = id, section = key });
            end
        end
    end
    return available_costs;
end

local function total_price(costs, pct)
    local sum = 0;
    for _, cost in ipairs(costs) do
        sum = sum + discounted(cost, pct);
    end
    return sum;
end

-- number of ignored spells that would otherwise be listed
local function ignored_count()
    local n = 0;
    for id in pairs(sc.config.settings.spells_ignore_list) do
        if spells[id] and learnable(id) then
            n = n + 1;
        end
    end
    return n;
end

-------------------------------------------------------------------------------
-- rows

local function label(parent, font, x, y)
    local fs = parent:CreateFontString(nil, "OVERLAY", font);
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y);
    fs:SetTextColor(unpack(colors.body));
    fs:SetJustifyH("LEFT");
    fs:SetWordWrap(false);
    return fs;
end

local refresh;

local function row_on_enter(self)
    local item = self.item;
    if not item or not item.spell_id then
        return;
    end
    local spell = spells[item.spell_id];
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
    GameTooltip:SetSpellByID(item.spell_id);
    if spell.train > 0 then
        local pct = best_discount();
        GameTooltip:AddLine(" ");
        GameTooltip:AddDoubleLine(L["Training cost"], GetCoinTextureString(discounted(spell.train, pct)), 1, 0.82, 0, 1, 1, 1);
        if pct > 0 then
            GameTooltip:AddDoubleLine(L["Base price"], GetCoinTextureString(spell.train), 0.6, 0.6, 0.6, 0.6, 0.6, 0.6);
        end
    elseif spell.train < -1 then
        local item_name = C_Item.GetItemNameByID(-spell.train);
        if item_name then
            GameTooltip:AddLine(" ");
            GameTooltip:AddDoubleLine(L["Learned from"], item_name, 1, 0.82, 0, 1, 1, 1);
        end
    end
    local prev = item.section == "missing" and missing_rank(item.spell_id);
    if prev then
        GameTooltip:AddLine(string.format(L["Needs rank %d"], spells[prev].rank), 1, 0.5, 0.25);
    end
    GameTooltip:AddLine(item.section == "ignored" and L["Right click: stop ignoring"] or L["Right click: ignore"], 0.5, 0.5, 0.5);
    GameTooltip:Show();
end

-- the Spells tab reads the same ignore list
local function ignore_list_changed()
    refresh();
    if __sc_frame and __sc_frame:IsShown() then
        sc.ui.update_spells_frame(nil, nil, nil, true);
    end
end

local function set_ignored(ids, on)
    for _, id in ipairs(ids) do
        sc.config.settings.spells_ignore_list[id] = on and 1 or nil;
    end
    ignore_list_changed();
end

local function open_ignore_menu(row, id)
    MenuUtil.CreateContextMenu(row, function(_, description)
        description:CreateTitle(GetSpellInfo(id) or "");
        if ignored(id) then
            description:CreateButton(L["Stop ignoring"], function() set_ignored({id}, false); end);
        else
            description:CreateButton(L["Ignore spell"], function() set_ignored({id}, true); end);
            local ranks = {};
            for _, rank_id in ipairs(sc.rank_seqs[spells[id].base_id] or {}) do
                if spells[rank_id] and learnable(rank_id) then
                    table.insert(ranks, rank_id);
                end
            end
            if #ranks > 1 then
                description:CreateButton(L["Ignore all ranks"], function() set_ignored(ranks, true); end);
            end
        end
    end);
end

local function row_on_click(self, button)
    local item = self.item;
    if not item or not item.spell_id then
        return;
    end
    if button == "RightButton" then
        open_ignore_menu(self, item.spell_id);
        return;
    end
    if IsModifiedClick("CHATLINK") then
        local link = C_Spell.GetSpellLink(item.spell_id);
        if link then
            ChatFrameUtil.InsertLink(link);
        end
    end
end

local LIST_WIDTH = PAGE_WIDTH - 20;

local function create_row(page)
    local width = LIST_WIDTH;
    local row = CreateFrame("Button", nil, page.list);
    row:SetSize(width, ROW_HEIGHT);

    row.band = row:CreateTexture(nil, "BACKGROUND");
    row.band:SetAllPoints();
    row.band:SetTexture(skin.band);

    row.heading = row:CreateFontString(nil, "OVERLAY", "SystemFont_Med3");
    row.heading:SetPoint("LEFT", 8, 0);
    row.heading:SetShadowColor(unpack(colors.shadow));
    row.heading:SetShadowOffset(1, -1);

    row.icon = row:CreateTexture(nil, "ARTWORK");
    row.icon:SetPoint("TOPLEFT", 8, -2);
    row.icon:SetSize(24, 24);
    row.icon_border = row:CreateTexture(nil, "OVERLAY");
    row.icon_border:SetTexture(skin.icon_border);
    row.icon_border:SetPoint("CENTER", row.icon, "CENTER");
    row.icon_border:SetSize(40, 40);

    row.name = label(row, "SystemFont_Med3", 38, -7);
    row.name:SetWidth(page.rank_x - 46);
    row.rank = label(row, "SystemFont_Med3", page.rank_x, -7);
    row.rank:SetWidth(page.level_x - page.rank_x - 8);
    row.level = label(row, "SystemFont_Med3", page.level_x, -7);
    row.level:SetWidth(width - page.level_x - 8);

    row.separator = row:CreateTexture(nil, "BACKGROUND");
    row.separator:SetColorTexture(unpack(colors.separator));
    row.separator:SetPoint("BOTTOMLEFT", 38, 0);
    row.separator:SetPoint("BOTTOMRIGHT", -8, 0);
    row.separator:SetHeight(1);

    local highlight = row:CreateTexture(nil, "HIGHLIGHT");
    highlight:SetAllPoints();
    highlight:SetColorTexture(unpack(colors.highlight));
    row:SetHighlightTexture(highlight);

    row:RegisterForClicks("LeftButtonUp", "RightButtonUp");
    row:SetScript("OnEnter", row_on_enter);
    row:SetScript("OnLeave", hide_tooltip);
    row:SetScript("OnHide", hide_tooltip);
    row:SetScript("OnClick", row_on_click);
    return row;
end

local function show_heading(row, item)
    local c = colors.sections[item.heading];
    row:SetHeight(HEADING_HEIGHT);
    row.band:SetVertexColor(c[1], c[2], c[3]);
    row.band:Show();
    row.heading:SetText(L[section_names[item.heading]].." • "..item.count);
    row.heading:SetTextColor(c[4], c[5], c[6]);
    row.heading:Show();
    for _, region in ipairs({row.icon, row.icon_border, row.name, row.rank, row.level, row.separator}) do
        region:Hide();
    end
    row:GetHighlightTexture():SetAlpha(0);
end

local function show_spell(row, item)
    local id = item.spell_id;
    local spell = spells[id];
    row:SetHeight(ROW_HEIGHT);
    row.band:Hide();
    row.heading:Hide();
    row.icon:SetTexture(GetSpellTexture(id));
    local name, subtext = GetSpellInfo(id);
    row.name:SetText(name or "");
    if spell.rank and spell.rank ~= 0 then
        row.rank:SetText(L["Rank"].." "..spell.rank);
    else
        -- spells new in Forever carry no rank in the data; the client's own
        -- rank text stands in
        row.rank:SetText(subtext or "");
    end
    local text_color = item.section == "ignored" and colors.dim or colors.body;
    row.name:SetTextColor(unpack(text_color));
    row.rank:SetTextColor(unpack(text_color));
    if item.section == "available" then
        row.level:SetText("—");
        row.level:SetTextColor(unpack(colors.body));
    elseif item.section == "missing" then
        local prev = missing_rank(id);
        row.level:SetText(prev and string.format(L["Needs rank %d"], spells[prev].rank) or "—");
        row.level:SetTextColor(unpack(colors.level_missing));
    elseif item.section == "ignored" then
        row.level:SetText(L["Level"].." "..spell.lvl_req);
        row.level:SetTextColor(unpack(colors.dim));
    else
        row.level:SetText(L["Level"].." "..spell.lvl_req);
        row.level:SetTextColor(unpack(item.section == "soon" and colors.level_soon or colors.level_later));
    end
    for _, region in ipairs({row.icon, row.icon_border, row.name, row.rank, row.level, row.separator}) do
        region:Show();
    end
    row:GetHighlightTexture():SetAlpha(1);
end

-- places items from `first` on until the page is full; returns the first
-- item that did not fit
local function layout_page(page, first)
    for _, row in ipairs(page.rows) do
        row:Hide();
        row.item = nil;
    end
    local height = page.list:GetHeight();
    local y, used, i = 0, 0, first;
    while items[i] do
        local item = items[i];
        local gap = (item.heading and y > 0) and HEADING_GAP or 0;
        local h = item.heading and HEADING_HEIGHT or ROW_HEIGHT;
        -- a heading needs room for itself and one spell
        local needed = item.heading and h + ROW_HEIGHT or h;
        if y + gap + needed > height then
            break;
        end
        used = used + 1;
        local row = page.rows[used] or create_row(page);
        page.rows[used] = row;
        row.item = item;
        if item.heading then
            show_heading(row, item);
        else
            show_spell(row, item);
        end
        row:ClearAllPoints();
        row:SetPoint("TOPLEFT", page.list, "TOPLEFT", 0, -(y + gap));
        row:Show();
        y = y + gap + h;
        i = i + 1;
    end
    return i;
end

local function layout()
    local left, right = pages[1], pages[2];
    if left.list:GetHeight() <= 0 then
        -- not laid out yet on the first frame the page shows
        RunNextFrame(layout);
        return;
    end
    offset = math.max(1, math.min(offset, #items));
    local next_item = layout_page(left, offset);
    if right:IsShown() then
        layout_page(right, next_item);
    end
end

refresh = function()
    local costs = build_items();
    local total = total_price(costs, best_discount());
    pages[1].total:SetText(total > 0 and string.format(L["Available total: %s"], GetCoinTextureString(total)) or "");
    pages[1].total_area.costs = costs;
    pages[1].empty:SetShown(#items == 0);
    layout();
end

-- the total's tooltip: the trainer towns, the standing there and what it saves
local function total_on_enter(self)
    local costs = self.costs;
    local base = costs and total_price(costs, 0) or 0;
    if base <= 0 then
        return;
    end
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT");
    GameTooltip:SetText(L["Reputation discount"]);
    for _, option in ipairs(discount_options()) do
        local right = option.pct > 0 and GetCoinTextureString(total_price(costs, option.pct)).."  (-"..option.pct.."%)"
            or GetCoinTextureString(base);
        GameTooltip:AddDoubleLine(option.name.." |cFF808080("..option.standing..")|r", right, 1, 1, 1, 1, 1, 1);
    end
    GameTooltip:AddLine(" ");
    GameTooltip:AddDoubleLine(L["Base price"], GetCoinTextureString(base), 0.6, 0.6, 0.6, 0.6, 0.6, 0.6);
    GameTooltip:AddLine(L["Discount from Honored with the trainer's town"], 0.5, 0.5, 0.5, true);
    GameTooltip:Show();
end

local function wheel(_, delta)
    offset = offset - delta * SCROLL_STEP;
    layout();
end

-------------------------------------------------------------------------------
-- frames

local function make_tab(name, parent)
    local button = CreateFrame("Button", name, parent);
    button:SetSize(44, 32);
    button.icon = button:CreateTexture(nil, "ARTWORK");
    button.icon:SetSize(34, 33);
    button.icon:SetPoint("BOTTOM", -1, 0);
    button.icon:SetTexture(skin.icon);
    local function frame_art(atlas, y)
        local texture = button:CreateTexture(nil, "ARTWORK", nil, 1);
        texture:SetAtlas(atlas, true);
        texture:SetPoint("BOTTOM", 0, y);
        return texture;
    end
    button.normal = frame_art(skin.tab, 1);
    button.active = frame_art(skin.tab_active, 1);
    button.glow = frame_art(skin.tab_glow, 0);
    return button;
end

local function select_tab(button, selected)
    button.normal:SetShown(not selected);
    button.active:SetShown(selected);
    button.glow:SetShown(selected);
end

-- parchment that eats the mouse over the native book
local function cover()
    local frame = CreateFrame("Frame", nil, root);
    frame:SetClipsChildren(true);
    frame:EnableMouse(true);
    frame:EnableMouseWheel(true);
    frame:SetScript("OnMouseWheel", wheel);
    local backing = frame:CreateTexture(nil, "BACKGROUND");
    backing:SetAllPoints();
    backing:SetColorTexture(unpack(colors.backing));
    local art = CreateFrame("Frame", nil, frame);
    art:SetAllPoints(root);
    local function page_art(atlas, from, to)
        local texture = art:CreateTexture(nil, "BACKGROUND");
        texture:SetAtlas(atlas);
        texture:SetPoint("TOPLEFT", root, from);
        texture:SetPoint("BOTTOMRIGHT", root, to);
        return texture;
    end
    frame.whole = page_art(skin.page_right, "TOPLEFT", "BOTTOMRIGHT");
    frame.left = page_art(skin.page_left, "TOPLEFT", "BOTTOM");
    frame.right = page_art(skin.page_right, "TOP", "BOTTOMRIGHT");
    table.insert(covers, frame);
    return frame;
end

local function create_page(header_x, title)
    local page = CreateFrame("Frame", nil, root);
    page:SetWidth(PAGE_WIDTH);
    page:EnableMouseWheel(true);
    page:SetScript("OnMouseWheel", wheel);

    local header = CreateFrame("Frame", nil, page, "SpellBookHeaderTemplate");
    header:SetWidth(680);
    header:ClearAllPoints();
    header:SetPoint("TOPLEFT", page, "TOPLEFT", header_x, -5);
    header.Text:SetText(title);
    header.Backplate:SetWidth(math.max(416, header.Text:GetStringWidth() * 2.5));
    page.header = header;

    page.rank_x, page.level_x = PAGE_WIDTH - 20 - 260, PAGE_WIDTH - 20 - 155;
    -- on a child frame, so the labels draw above the cover's parchment
    page.columns = CreateFrame("Frame", nil, page);
    page.columns:SetAllPoints();
    local spell_col = label(page.columns, "SystemFont_Med3", 38, -62);
    spell_col:SetText(L["Spell"]);
    local rank_col = label(page.columns, "SystemFont_Med3", page.rank_x, -62);
    rank_col:SetText(L["Rank"]);
    local level_col = label(page.columns, "SystemFont_Med3", page.level_x, -62);
    level_col:SetText(L["Required level"]);

    page.list = CreateFrame("Frame", nil, page);
    page.list:SetPoint("TOPLEFT", page, "TOPLEFT", 0, LIST_TOP);
    page.list:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -20, LIST_BOTTOM);
    page.rows = {};
    return page;
end

local function sync()
    local tabs = book.CategoryTabSystem;
    local gamepad = InputUtil and InputUtil.IsGamepadUIEnabled and InputUtil.IsGamepadUIEnabled();
    if gamepad or tabs.selectedTabID ~= shown_tab or book.SearchBox:HasFocus()
        or (book.SearchPreviewContainer and book.SearchPreviewContainer:IsShown()) then
        active = false;
    end
    if gamepad or not book:IsVisible() or not enabled() then
        root:Hide();
        launcher:Hide();
        return;
    end

    local window = _G.PlayerSpellsFrame;
    local scale = book:GetEffectiveScale() / window:GetEffectiveScale();
    local strata, level = window:GetFrameStrata(), window.NineSlice:GetFrameLevel() - 10;
    for _, frame in ipairs({root, launcher}) do
        frame:SetScale(scale);
        frame:SetFrameStrata(strata);
        frame:SetFrameLevel(level);
    end
    launcher:SetFrameLevel(level + 5);
    return_tab:SetFrameLevel(level + 5);
    search:SetFrameLevel(level + 5);
    settings:SetFrameLevel(level + 5);
    for _, page in ipairs(pages) do
        page:SetFrameLevel(level + 2);
    end

    -- next to the last category tab, or as a bookmark on the book's edge
    -- when the search box leaves no room for it
    local search_left, tabs_right = book.SearchBox:GetLeft(), tabs:GetRight();
    local bookmark = search_left and tabs_right and search_left - tabs_right < 52 or false;
    if launcher.bookmark ~= bookmark then
        launcher.bookmark = bookmark;
        launcher:ClearAllPoints();
        if bookmark then
            launcher:SetPoint("BOTTOMLEFT", book, "TOPRIGHT", 0, tabs:GetBottom() - book:GetTop());
        else
            launcher:SetPoint("LEFT", tabs, "RIGHT", 8, 0);
        end
        attic:SetPoint("LEFT", bookmark and tabs or launcher, "RIGHT");
    end

    select_tab(launcher, active);
    launcher:Show();
    if not active then
        root:Hide();
        return;
    end

    local minimized = book.isMinimized;
    for _, frame in ipairs(covers) do
        frame.whole:SetShown(minimized);
        frame.left:SetShown(not minimized);
        frame.right:SetShown(not minimized);
    end
    pages[2]:SetShown(not minimized);

    -- the native selected tab, under our cover: a copy of it takes us back
    local native = tabs.selectedTabID and tabs:GetTabButton(tabs.selectedTabID);
    return_tab:SetShown(native ~= nil);
    if native then
        return_tab:ClearAllPoints();
        return_tab:SetPoint("CENTER", native);
        return_tab.icon:SetTexture(native.Icon:GetTexture());
    end

    local opening = not root:IsShown();
    root:Show();
    -- the search box takes the room between the tabs and the settings button
    local room_left, room_right = (launcher.bookmark and tabs or launcher):GetRight(), search:GetRight();
    if room_left and room_right then
        search:SetWidth(math.max(1, math.min(300, room_right - room_left - 10)));
    end
    if opening then
        offset = 1;
        refresh();
    else
        layout();
    end
end

local function deferred_sync()
    queued = false;
    sync();
end

local function request()
    if queued then
        return;
    end
    queued = true;
    RunNextFrame(deferred_sync);
end

local function create()
    root = CreateFrame("Frame", "__sc_spellbook_page", _G.PlayerSpellsFrame);
    root:SetAllPoints(book);
    root:Hide();

    local content = cover();
    content:SetPoint("TOPLEFT", root, "TOPLEFT", 0, -HEADER_HEIGHT);
    content:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT");

    launcher = make_tab("__sc_frame_spellbook_tab", _G.PlayerSpellsFrame);
    launcher:Hide();
    launcher:RegisterForClicks("LeftButtonUp", "RightButtonUp");
    launcher:SetScript("OnClick", function(_, button)
        if button == "RightButton" then
            sc.ui.sw_activate_frame("spells_frame");
            return;
        end
        active = not active;
        if active then
            shown_tab = book.CategoryTabSystem.selectedTabID;
            PlaySound(SOUNDKIT.IG_SPELLBOOK_OPEN);
        end
        sync();
    end);
    launcher:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
        GameTooltip:SetText("SpellCoda |cFF9B6CFFForever|r");
        GameTooltip:AddLine("|cFF9CD6DE"..L["Left click"]..":|r "..L["Spells to learn"], 1, 1, 1);
        GameTooltip:AddLine("|cFF9CD6DE"..L["Right click"]..":|r "..L["Open SpellCoda"], 1, 1, 1);
        GameTooltip:Show();
    end);
    launcher:SetScript("OnLeave", hide_tooltip);
    launcher:SetScript("OnHide", hide_tooltip);

    -- covers the native search box and settings dropdown; left edge set by sync
    attic = cover();
    attic:SetPoint("TOP", root, "TOP");
    attic:SetPoint("BOTTOM", content, "TOP");
    attic:SetPoint("RIGHT", root, "RIGHT");

    return_tab = make_tab(nil, root);
    select_tab(return_tab, false);
    cover():SetAllPoints(return_tab);
    return_tab:SetScript("OnClick", function()
        active = false;
        sync();
    end);

    local left = create_page(20, "SpellCoda |cFF9B6CFFForever|r");
    left:SetPoint("TOPLEFT", root, "TOPLEFT", 65, PAGE_TOP);
    left:SetPoint("BOTTOMLEFT", root, "BOTTOMLEFT", 65, PAGE_BOTTOM);
    left.total = label(left.columns, "SystemFont_Med3", 0, 0);
    left.total:ClearAllPoints();
    -- level with the title, above the header's rule
    left.total:SetPoint("TOPRIGHT", left, "TOPRIGHT", -28, -12);
    left.total:SetJustifyH("RIGHT");
    left.total_area = CreateFrame("Frame", nil, left.columns);
    left.total_area:SetAllPoints(left.total);
    left.total_area:EnableMouse(true);
    left.total_area:SetScript("OnEnter", total_on_enter);
    left.total_area:SetScript("OnLeave", hide_tooltip);
    left.empty = label(left.list, "SystemFont_Med3", 8, -8);
    left.empty:SetText(L["Nothing left to learn"]);

    -- settings and search where the book's own sit (those are under the attic)
    settings = CreateFrame("DropdownButton", nil, root, "SpellBookSettingsDropdownTemplate");
    settings:ClearAllPoints();
    settings:SetPoint("TOPRIGHT", root, "TOPRIGHT", -30, -27);
    settings:SetupMenu(function(_, description)
        description:CreateCheckbox(string.format(L["Show ignored spells (%d)"], ignored_count()),
            function() return show_ignored; end,
            function()
                show_ignored = not show_ignored;
                offset = 1;
                refresh();
            end);
        description:CreateButton(L["Stop ignoring all"], function()
            local ids = {};
            for id in pairs(sc.config.settings.spells_ignore_list) do
                if spells[id] and learnable(id) then
                    table.insert(ids, id);
                end
            end
            set_ignored(ids, false);
        end);
    end);

    search = CreateFrame("EditBox", nil, root, "SearchBoxTemplate");
    search:SetSize(300, 30);
    search:SetAutoFocus(false);
    search:SetPoint("RIGHT", settings, "LEFT", -5, 4);
    search:HookScript("OnTextChanged", function()
        offset = 1;
        if root:IsShown() then
            refresh();
        end
    end);
    search:HookScript("OnHide", function(self)
        self:ClearFocus();
    end);

    local right = create_page(11, L["Spells"]);
    right:SetPoint("TOPRIGHT", root, "TOPRIGHT", -45, PAGE_TOP);
    right:SetPoint("BOTTOMRIGHT", root, "BOTTOMRIGHT", -45, PAGE_BOTTOM);
    right:Hide();
    pages = { left, right };

    -- learning or levelling changes the list while it is open
    -- PLAYER_LEVEL_UP fires while UnitLevel still returns the old level
    root:RegisterEvent("SPELLS_CHANGED");
    root:RegisterEvent("PLAYER_LEVEL_CHANGED");
    root:SetScript("OnEvent", function()
        if root:IsShown() then
            refresh();
        end
    end);
end

-- once the load-on-demand spellbook window exists (ADDON_LOADED in core)
local function attach()
    local window = _G.PlayerSpellsFrame;
    if root or not window or not window.SpellBookFrame then
        return;
    end
    book = window.SpellBookFrame;
    create();

    -- tab clicks, paging and data updates all end in DisplayedSpellsChanged;
    -- minimizing resizes the book
    for _, event in ipairs({"SpellBookFrame.Show", "SpellBookFrame.Hide", "SpellBookFrame.DisplayedSpellsChanged"}) do
        EventRegistry:RegisterCallback("PlayerSpellsFrame."..event, request, root);
    end
    EventRegistry:RegisterCallback("SpellSearchBox.FocusedGained", request, root);
    EventRegistry:RegisterCallback("SpellSearchPreview.FocusedGained", request, root);
    book:HookScript("OnSizeChanged", request);
    book:HookScript("OnShow", function()
        sync();
        request();
    end);
    book:HookScript("OnHide", sync);
    launcher:RegisterEvent("UI_SCALE_CHANGED");
    launcher:RegisterEvent("DISPLAY_SIZE_CHANGED");
    launcher:SetScript("OnEvent", request);
    request();
end

sc.spellbook_page = {
    attach = attach,
    -- the Spells tab changed the shared ignore list
    refresh = function()
        if root and root:IsShown() then
            refresh();
        end
    end,
    -- the settings checkbox shows or hides the tab
    sync = function()
        if root then
            sync();
        end
    end,
};
