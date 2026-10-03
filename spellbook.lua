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
    icon        = "Interface\\Icons\\spell_fire_elementaldevastation",
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
        soon      = {0.08, 0.18, 0.29, 0.55, 0.84, 1},
        later     = {0.30, 0.07, 0.04, 1, 0.55, 0.45},
    },
    level_soon  = {0.08, 0.22, 0.50},
    level_later = {0.45, 0.09, 0.04},
};

local section_order = { "available", "soon", "later" };
local section_names = {
    available = "Now available",
    soon = "Coming soon",
    later = "Not yet available",
};

local book, root, launcher, attic, return_tab, pages;
local covers = {};
local active, shown_tab, queued = false, nil, false;
local items, offset = {}, 1;

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

local function learnable(id)
    local spell = spells[id];
    if not spell or spell.train == 0 then
        return false;
    end
    if bit.band(spell.flags, bit.bor(spell_flags.talent, spell_flags.pet)) ~= 0 then
        return false;
    end
    if spell.race_flags and bit.band(spell.race_flags, bit.lshift(1, sc.race-1)) == 0 then
        return false;
    end
    if sc.config.settings.spells_ignore_list[id] then
        return false;
    end
    return not spell_known(id);
end

-- items: section headings followed by their spells, in level order
local function build_items()
    local lvl = UnitLevel("player");
    local next_lvl = lvl % 2 == 0 and lvl + 2 or lvl + 1;
    local sections = { available = {}, soon = {}, later = {} };
    local available_cost = 0;

    for _, id in ipairs(sc.spells_lvl_ordered) do
        if learnable(id) then
            local req = spells[id].lvl_req;
            local key = (req <= lvl and "available") or (req <= next_lvl and "soon") or "later";
            table.insert(sections[key], id);
            if key == "available" and spells[id].train > 0 then
                available_cost = available_cost + spells[id].train;
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
    return available_cost;
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

local function row_on_enter(self)
    local item = self.item;
    if not item or not item.spell_id then
        return;
    end
    local spell = spells[item.spell_id];
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT");
    GameTooltip:SetSpellByID(item.spell_id);
    if spell.train > 0 then
        GameTooltip:AddLine(" ");
        GameTooltip:AddDoubleLine(L["Training cost"], GetCoinTextureString(spell.train), 1, 0.82, 0, 1, 1, 1);
    elseif spell.train < -1 then
        local item_name = C_Item.GetItemNameByID(-spell.train);
        if item_name then
            GameTooltip:AddLine(" ");
            GameTooltip:AddDoubleLine(L["Learned from"], item_name, 1, 0.82, 0, 1, 1, 1);
        end
    end
    GameTooltip:Show();
end

local function row_on_click(self)
    local item = self.item;
    if item and item.spell_id and IsModifiedClick("CHATLINK") then
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
    row.name:SetText(GetSpellInfo(id) or "");
    if spell.rank and spell.rank ~= 0 then
        row.rank:SetText(L["Rank"].." "..spell.rank);
    else
        row.rank:SetText("");
    end
    if item.section == "available" then
        row.level:SetText("—");
        row.level:SetTextColor(unpack(colors.body));
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

local function refresh()
    local cost = build_items();
    pages[1].total:SetText(cost > 0 and string.format(L["Available total: %s"], GetCoinTextureString(cost)) or "");
    pages[1].empty:SetShown(#items == 0);
    layout();
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
    left.empty = label(left.list, "SystemFont_Med3", 8, -8);
    left.empty:SetText(L["Nothing left to learn"]);

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
    -- the settings checkbox shows or hides the tab
    sync = function()
        if root then
            sync();
        end
    end,
};
