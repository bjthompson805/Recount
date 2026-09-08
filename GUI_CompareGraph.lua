--[[
    GUI_CompareGraph.lua
    A dedicated compare graph window with accumulative player+metric filter system.

    Usage:
      • Click the compare button (↕) in the main window header to open.
      • Choose a player from the first dropdown and a metric from the second, then
        click "Add" to plot that series.  Repeat as many times as you like.
      • Each filter appears in the list on the right with a Remove button.
      • Normalize: scales all lines to 0-100% (useful when DPS >> TPS numerically).
      • Integrate: converts per-second rates into running cumulative totals.
      • The existing Shift+Click graph window is completely untouched.
]]

local Recount = _G.Recount

local Graph      = LibStub:GetLibrary("LibGraph-2.0")
local AceLocale  = LibStub("AceLocale-3.0")
local L          = AceLocale:GetLocale("Recount")

local math   = math
local table  = table
local pairs  = pairs
local ipairs = ipairs

local CreateFrame          = CreateFrame
local UIParent             = UIParent
local GameTooltip          = GameTooltip
local UIDropDownMenu_Initialize   = UIDropDownMenu_Initialize
local UIDropDownMenu_CreateInfo   = UIDropDownMenu_CreateInfo
local UIDropDownMenu_AddButton    = UIDropDownMenu_AddButton
local UIDropDownMenu_SetSelectedValue = UIDropDownMenu_SetSelectedValue
local UIDropDownMenu_SetText      = UIDropDownMenu_SetText
local UIDropDownMenu_SetWidth     = UIDropDownMenu_SetWidth

-- ── Metric definitions ─────────────────────────────────────────────────────
-- { display label , TimeData key (nil = no time data) , GraphColors key , autoIntegrate }
-- autoIntegrate=true: TimeData stores per-second rates; integrate to show running totals
local Metrics = {
    { "Damage Done",   "Damage",       "Damage",       true  },
    { "DPS",           "Damage",       "Damage",       false },
    { "Friendly Fire", nil,            "FriendlyFire", true  },
    { "Damage Taken",  "DamageTaken",  "DamageTaken",  true  },
    { "Healing Done",  "Healing",      "Healing",      true  },
    { "Absorbs",       nil,            "Absorbs",      true  },
    { "Healing Taken", "HealingTaken", "HealingTaken", true  },
    { "Overhealing",   "Overhealing",  "Overhealing",  true  },
    { "Deaths",        nil,            "Deaths",       false },
    { "DOT Uptime",    nil,            "DOTUptime",    false },
    { "HOT Uptime",    nil,            "HOTUptime",    false },
    { "Activity",      nil,            "Activity",     false },
    { "Threat (TPS)",   "Threat",       "Threat",       false },
    { "Threat (Total)", "Threat",       "Threat",       true  },
}

local GraphColors = {
    Damage       = {1.0,  0.0,  0.0 },
    DamageTaken  = {1.0,  1.0,  0.0 },
    Healing      = {0.0,  1.0,  0.0 },
    HealingTaken = {0.0,  1.0,  1.0 },
    Overhealing  = {0.5,  0.0,  1.0 },
    Threat       = {1.0,  0.5,  0.0 },
    FriendlyFire = {1.0,  0.4,  0.4 },
    Absorbs      = {0.3,  0.6,  1.0 },
    Deaths       = {0.6,  0.0,  0.0 },
    DOTUptime    = {1.0,  0.65, 0.2 },
    HOTUptime    = {0.2,  0.8,  0.4 },
    Activity     = {0.7,  0.7,  0.7 },
}

local ShadeVariant = {1.0, 0.6, 0.8, 0.4, 0.7, 0.5, 0.3, 0.9}

-- ── Module-level state ──────────────────────────────────────────────────────
local activeFilters  = {}   -- {player, dataKey, metricLabel, label, color={r,g,b,1}}
local metricCount    = {}   -- [colorKey] = number of filters using that color, for shading
local renderedSeries = {}   -- [{times,values,label,color}] rebuilt each RefreshCompareGraph for crosshair use

local selectedPlayer = nil
local selectedFightIdx = 0  -- 0 = show all data; >0 = index into CombatTimes
local selectedMetricIdx = 1

-- ── Helper: sorted combatant list ──────────────────────────────────────────
local function GetCombatants()
    local list = {}
    local db = Recount.db2 and Recount.db2.combatants
    if db then
        for name in pairs(db) do
            list[#list + 1] = name
        end
        table.sort(list)
    end
    return list
end

-- ── Helper: assign a shaded color ──────────────────────────────────────────
local function MakeColor(colorKey)
    metricCount[colorKey] = (metricCount[colorKey] or 0) + 1
    local shade = ShadeVariant[metricCount[colorKey]] or ShadeVariant[#ShadeVariant]
    local base = GraphColors[colorKey] or {1, 1, 1}
    return {shade * base[1], shade * base[2], shade * base[3], 1}
end

-- ── Rebuild all colors so they stay consistent after a removal ─────────────
local function ReassignColors()
    for k in pairs(metricCount) do metricCount[k] = nil end
    for _, f in ipairs(activeFilters) do
        local colorKey
        for _, m in ipairs(Metrics) do
            if m[1] == f.metricLabel then colorKey = m[3]; break end
        end
        metricCount[colorKey] = (metricCount[colorKey] or 0) + 1
        local shade = ShadeVariant[metricCount[colorKey]] or ShadeVariant[#ShadeVariant]
        local base = GraphColors[colorKey] or {1, 1, 1}
        f.color = {shade * base[1], shade * base[2], shade * base[3], 1}
    end
end

-- ── Filter list UI refresh ─────────────────────────────────────────────────
local function RefreshFilterRows()
    local win = Recount.CompareWindow
    if not win then return end

    for i = 1, #win.FilterRows do
        win.FilterRows[i]:Hide()
    end

    for i, f in ipairs(activeFilters) do
        local row = win.FilterRows[i]
        if not row then break end
        row.Key:SetVertexColor(f.color[1], f.color[2], f.color[3], 1)
        row.Name:SetText(f.label)
        row.RemoveBtn.filterIdx = i
        row:Show()
    end
end

-- ── Graph rendering ─────────────────────────────────────────────────────────
local function FilterByTime(data, lower, upper)
    if not data or not data[1] or #data[1] == 0 then return nil end
    local out = {{}, {}}

    if not lower or not upper then
        for i = 1, #data[1] do
            out[1][i] = data[1][i]
            out[2][i] = data[2][i]
        end
        return out
    end

    local first = true
    local last  = 0
    for k, v in ipairs(data[1]) do
        if v >= lower and v <= upper then
            if first then
                if k ~= 1 then
                    local w = (lower - data[1][k-1]) / (data[1][k] - data[1][k-1])
                    out[2][#out[2]+1] = w * data[2][k] + (1-w) * data[2][k-1]
                else
                    out[2][#out[2]+1] = 0
                end
                out[1][#out[1]+1] = lower
                first = false
            end
            out[1][#out[1]+1] = v
            out[2][#out[2]+1] = data[2][k]
            last = k
        end
    end
    if last ~= 0 then
        if data[1][last+1] then
            local w = (upper - data[1][last]) / (data[1][last+1] - data[1][last])
            out[2][#out[2]+1] = w * data[2][last+1] + (1-w) * data[2][last]
        else
            out[2][#out[2]+1] = 0
        end
        out[1][#out[1]+1] = upper
    end
    return out
end

local function FindMax(data)
    local mn, mx = data[2][1] or 0, data[2][1] or 0
    for _, v in ipairs(data[2]) do
        if v > mx then mx = v end
        if v < mn then mn = v end
    end
    return mn, mx
end

local function IntegrateData(data)
    local sum, prev, first = 0, 0, true
    for k, v in ipairs(data[1]) do
        if first then
            prev = data[2][k]; data[2][k] = 0; first = false
        else
            sum = sum + 0.5 * (data[2][k] + prev) * (v - data[1][k-1])
            prev = data[2][k]; data[2][k] = sum
        end
    end
end

local function NormalizeData(data)
    local mn, mx = FindMax(data)
    local width = mx - mn
    if width == 0 then return end
    for k in ipairs(data[2]) do
        data[2][k] = 100 * (data[2][k] - mn) / width
    end
end

local function ApplyGridSpacing(lg, span, maxAmt)
    local gridY
    if     maxAmt < 100  then gridY = 10
    elseif maxAmt < 250  then gridY = 25
    elseif maxAmt < 500  then gridY = 50
    elseif maxAmt < 1500 then gridY = 100
    elseif maxAmt < 3000 then gridY = 200
    else                      gridY = 100 * math.floor(maxAmt / 1000) end
    if     span < 60  then lg:SetGridSpacing(5,  gridY)
    elseif span < 180 then lg:SetGridSpacing(15, gridY)
    elseif span < 400 then lg:SetGridSpacing(30, gridY)
    elseif span < 600 then lg:SetGridSpacing(60, gridY)
    else                   lg:SetGridSpacing(math.floor(span/100)*10, gridY) end
end

local function RefreshCompareGraph()
    local win = Recount.CompareWindow
    if not win or not win:IsShown() then return end
    local lg = win.LineGraph
    local status = win.StatusText
    local db = Recount.db2 and Recount.db2.combatants
    if not db then
        if status then status:SetText("Recount data unavailable") end
        return
    end

    lg:ResetData()
    for k in pairs(renderedSeries) do renderedSeries[k] = nil end  -- clear crosshair data

    if #activeFilters == 0 then
        lg:SetXAxis(5, 30); lg:SetYAxis(0, 100); lg:SetGridSpacing(15, 25)
        if status then status:SetText("") end
        return
    end

    -- ── Per-Fight mode ─────────────────────────────────────────────────────
    -- One composite line per filter.  Each fight produces a "hump" that rises
    -- from 0 as damage/healing accumulates then snaps back to 0 at fight end.
    -- X axis = seconds since the first recorded fight (absolute session timeline).
    -- Out-of-combat gaps appear as flat-zero stretches between humps.
    if win.PerFightOn then
        local ct = Recount.db2 and Recount.db2.CombatTimes
        if not ct or #ct == 0 then
            lg:SetXAxis(0, 30); lg:SetYAxis(0, 100); lg:SetGridSpacing(15, 25)
            if status then status:SetText("No fights recorded yet") end
            return
        end

        -- Offset all timestamps so x=0 is the start of the first recorded fight
        local sessionBase = ct[1][1]
        local xMax = math.max(ct[#ct][2] - sessionBase, 1)
        local maxAmt = 0
        local seriesDrawn = 0

        for _, f in ipairs(activeFilters) do
            if f.dataKey then
                local td = db[f.player] and db[f.player].TimeData and db[f.player].TimeData[f.dataKey]
                if td and td[1] and #td[1] > 0 then
                    local compT = {}
                    local compV = {}

                    for i, v in ipairs(ct) do
                        -- No pre-padding: slice exactly the fight window so integration starts at 0
                        local filt = FilterByTime(td, v[1], v[2] + 2)
                        if filt and #filt[1] > 0 then
                            if f.autoIntegrate or win.IntegrateOn then
                                IntegrateData(filt)
                                -- Subtract the baseline so every hump starts at y=0
                                local base0 = filt[2][1] or 0
                                if base0 ~= 0 then
                                    for k = 1, #filt[2] do filt[2][k] = filt[2][k] - base0 end
                                end
                            end
                            if win.NormalizeOn then NormalizeData(filt) end
                            for k, vv in ipairs(filt[2]) do if vv < 0 then filt[2][k] = 0 end end

                            local _, mx = FindMax(filt)
                            if mx > maxAmt then maxAmt = mx end

                            -- Append this fight's points (session-relative time)
                            for k = 1, #filt[1] do
                                compT[#compT + 1] = filt[1][k] - sessionBase
                                compV[#compV + 1] = filt[2][k]
                            end

                            -- Sawtooth reset: snap back to 0 at fight end
                            local fightEndRel = v[2] - sessionBase
                            compT[#compT + 1] = fightEndRel + 0.1
                            compV[#compV + 1] = 0

                            -- Hold 0 until the next fight starts
                            if ct[i + 1] then
                                local nextStartRel = ct[i + 1][1] - sessionBase
                                if nextStartRel - 0.2 > fightEndRel + 0.1 then
                                    compT[#compT + 1] = nextStartRel - 0.1
                                    compV[#compV + 1] = 0
                                end
                            end
                        end
                    end

                    if #compT > 0 then
                        lg:AddDataSeries({compT, compV}, f.color, true)
                        renderedSeries[#renderedSeries + 1] = {
                            times  = compT,
                            values = compV,
                            label  = f.label,
                            color  = f.color,
                        }
                        seriesDrawn = seriesDrawn + 1
                    end
                end
            end
        end

        if maxAmt == 0 then maxAmt = 1 end
        lg:SetXAxis(0, xMax)
        lg:SetYAxis(0, maxAmt * 1.1)
        if status then
            if seriesDrawn > 0 then
                status:SetText(#ct .. " fights  |  " .. seriesDrawn .. " series")
            else
                status:SetText("No time-data found for selected series")
            end
        end
        ApplyGridSpacing(lg, xMax, maxAmt)
        return
    end

    -- ── Normal (session-timeline) mode ─────────────────────────────────────
    -- If a specific fight is selected, clamp to its window (+30s padding)
    local fightLower, fightUpper
    do
        local ct = Recount.db2 and Recount.db2.CombatTimes
        if selectedFightIdx > 0 and ct and ct[selectedFightIdx] then
            fightLower = ct[selectedFightIdx][1] - 30
            fightUpper = ct[selectedFightIdx][2] + 30
        end
    end

    local lower, upper
    for _, f in ipairs(activeFilters) do
        if f.dataKey then
            local td = db[f.player] and db[f.player].TimeData and db[f.player].TimeData[f.dataKey]
            if td and td[1] and #td[1] > 0 then
                local t0, t1 = td[1][1], td[1][#td[1]]
                if not lower or t0 < lower then lower = t0 end
                if not upper or t1 > upper then upper = t1 end
            end
        end
    end

    if not lower then
        lg:SetXAxis(5, 30); lg:SetYAxis(0, 100); lg:SetGridSpacing(15, 25)
        if status then
            local hasNilKey = false
            for _, f in ipairs(activeFilters) do
                if not f.dataKey then hasNilKey = true; break end
            end
            if hasNilKey then
                status:SetText("Selected metric has no time-data")
            else
                status:SetText("No time-data. Enable 'Record Time Data' in Recount settings.")
            end
        end
        return
    end

    if lower == upper then upper = lower + 1 end

    if fightLower then
        lower = math.max(lower, fightLower)
        upper = math.min(upper, fightUpper)
        if lower >= upper then lower = fightLower; upper = fightUpper end
    end

    lg:SetXAxis(lower, upper)

    local maxAmt = 0
    local seriesDrawn = 0

    for _, f in ipairs(activeFilters) do
        if f.dataKey then
            local td = db[f.player] and db[f.player].TimeData and db[f.player].TimeData[f.dataKey]
            if td and td[1] and #td[1] > 0 then
                local filt = FilterByTime(td, lower, upper)
                if filt and #filt[1] > 0 then
                    if f.autoIntegrate or win.IntegrateOn then IntegrateData(filt) end
                    if win.NormalizeOn then NormalizeData(filt) end
                    local _, mx = FindMax(filt)
                    if mx > maxAmt then maxAmt = mx end
                    for k, v in ipairs(filt[2]) do if v < 0 then filt[2][k] = 0 end end
                    lg:AddDataSeries(filt, f.color, true)
                    renderedSeries[#renderedSeries + 1] = {
                        times  = filt[1],
                        values = filt[2],
                        label  = f.label,
                        color  = f.color,
                    }
                    seriesDrawn = seriesDrawn + 1
                end
            end
        end
    end

    if maxAmt == 0 then maxAmt = 1 end
    lg:SetYAxis(0, maxAmt * 1.1)

    if status then
        if seriesDrawn > 0 then
            status:SetText("Showing " .. seriesDrawn .. " series")
        else
            status:SetText("No data in range")
        end
    end

    ApplyGridSpacing(lg, upper - lower, maxAmt)
end

-- ── Add / remove filter public API ─────────────────────────────────────────
local function AddFilter()
    if not selectedPlayer then return end
    local metric = Metrics[selectedMetricIdx]
    if not metric then return end

    -- Prevent duplicates by player + metric label (not dataKey, since multiple metrics share the same key)
    for _, f in ipairs(activeFilters) do
        if f.player == selectedPlayer and f.metricLabel == metric[1] then return end
    end

    local color = MakeColor(metric[3])
    activeFilters[#activeFilters + 1] = {
        player        = selectedPlayer,
        dataKey       = metric[2],
        metricLabel   = metric[1],
        colorKey      = metric[3],
        autoIntegrate = metric[4] == true,
        label         = selectedPlayer .. "'s " .. metric[1],
        color         = color,
    }

    RefreshFilterRows()
    RefreshCompareGraph()
end

local function RemoveFilter(idx)
    table.remove(activeFilters, idx)
    ReassignColors()
    RefreshFilterRows()
    RefreshCompareGraph()
end

local function ClearAllFilters()
    for k in pairs(metricCount) do metricCount[k] = nil end
    for i = #activeFilters, 1, -1 do activeFilters[i] = nil end
    RefreshFilterRows()
    RefreshCompareGraph()
end

-- ── Public opener ───────────────────────────────────────────────────────────
function Recount:OpenCompareWindow()
    if not Recount.CompareWindow then
        Recount:CreateCompareWindow()
    end
    Recount.CompareWindow:Show()
    Recount:SetWindowTop(Recount.CompareWindow)
    -- Refresh player dropdown in case combatants changed
    UIDropDownMenu_Initialize(Recount.CompareWindow.PlayerDropDown,
        Recount.CompareWindow.PlayerDropDownInit)
end

-- ── Window creation ─────────────────────────────────────────────────────────
function Recount:CreateCompareWindow()
    local win = CreateFrame("Frame", "Recount_CompareWindow", UIParent,
        BackdropTemplateMixin and "BackdropTemplate")
    Recount.CompareWindow = win

    win:ClearAllPoints()
    win:SetPoint("CENTER", UIParent)
    win:SetWidth(660)
    win:SetHeight(480)
    win:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background", tile = true, tileSize = 16,
        edgeFile = "Interface\\AddOns\\Recount\\textures\\otravi-semi-full-border", edgeSize = 32,
        insets   = {left=1, right=1, top=20, bottom=1},
    })
    win:SetBackdropBorderColor(1.0, 0.0, 0.0)
    win:SetBackdropColor(24/255, 24/255, 24/255)
    Recount.Colors:RegisterBorder("Other Windows", "Title", win)
    Recount.Colors:RegisterBackground("Other Windows", "Background", win)

    win:EnableMouse(true); win:SetMovable(true)
    win:SetScript("OnMouseDown", function(this, btn)
        if btn == "LeftButton" and not this.isLocked then
            Recount:SetWindowTop(this); this:StartMoving(); this.isMoving = true
        end
    end)
    win:SetScript("OnMouseUp", function(this)
        if this.isMoving then this:StopMovingOrSizing(); this.isMoving = false end
    end)

    -- Title
    win.Title = win:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    win.Title:SetPoint("TOPLEFT", win, "TOPLEFT", 6, -15)
    win.Title:SetTextColor(1, 1, 1)
    win.Title:SetText("Compare Graph")
    Recount.Colors:RegisterFont("Other Windows", "Title Text", win.Title)

    -- Close
    local close = CreateFrame("Button", nil, win)
    close:SetNormalTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Up")
    close:SetPushedTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Down")
    close:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight")
    close:SetWidth(20); close:SetHeight(20)
    close:SetPoint("TOPRIGHT", win, "TOPRIGHT", -4, -12)
    close:SetScript("OnClick", function() win:Hide() end)

    -- ── Graph (left side) ──────────────────────────────────────────────────
    win.LineGraph = Graph:CreateGraphLine(
        "Recount_CompareWindow_LineGraph", win, "TOPLEFT", "TOPLEFT", 1, -32, 400, 438)
    local lg = win.LineGraph
    lg:SetYAxis(0, 100)
    lg:SetXAxis(5, 30)
    lg:SetGridSpacing(15, 25)
    lg:SetYLabels(true, true)
    lg:SetFrameLevel(win:GetFrameLevel() + 2)

    -- Status / diagnostic text shown inside the graph area
    -- Must be created on lg (not win) so it renders above LibGraph's ARTWORK lines
    win.StatusText = lg:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    win.StatusText:SetPoint("BOTTOM", lg, "BOTTOM", 0, 6)
    win.StatusText:SetPoint("LEFT",   lg, "LEFT",   4, 0)
    win.StatusText:SetPoint("RIGHT",  lg, "RIGHT", -4, 0)
    win.StatusText:SetJustifyH("CENTER")
    win.StatusText:SetTextColor(1, 0.8, 0.2, 1)

    -- ── Crosshair cursor ───────────────────────────────────────────────────
    -- We need mouse events on lg itself.  LibGraph already sets EnableMouse on
    -- the TextFrame child, but not on lg.  Set it here so OnUpdate sees the mouse.
    lg:EnableMouse(true)

    -- Vertical hairline texture (reused every frame; hidden when mouse leaves)
    local hairline = lg:CreateTexture(nil, "OVERLAY")
    hairline:SetTexture("Interface\\Buttons\\WHITE8X8")
    hairline:SetVertexColor(1, 1, 1, 0.35)
    hairline:SetWidth(1)
    hairline:Hide()
    win.Crosshair = hairline

    local function FormatVal(v)
        if     v >= 1e6  then return string.format("%.2fm", v / 1e6)
        elseif v >= 1e3  then return string.format("%.1fk", v / 1e3)
        else                  return string.format("%.1f",  v) end
    end

    -- Linearly interpolate y for a given x in a {times,values} series
    local function InterpY(times, values, x)
        local n = #times
        if n == 0 then return nil end
        if x < times[1] or x > times[n] then return nil end
        if n == 1 then return values[1] end
        for i = 2, n do
            if times[i] >= x then
                local dt = times[i] - times[i-1]
                if dt == 0 then return values[i] end
                local w = (x - times[i-1]) / dt
                return values[i-1] + w * (values[i] - values[i-1])
            end
        end
        return values[n]
    end

    -- `graph`, not `self`: the enclosing window-builder already has a `self`, and
    -- every script below is about the LibGraph frame rather than the window.
    lg:SetScript("OnUpdate", function(graph)
        -- Let LibGraph do its own NeedsUpdate work first
        if graph.NeedsUpdate and graph.RefreshGraph then
            graph:RefreshGraph()
            graph.NeedsUpdate = false
        end

        -- graph:IsMouseOver(), not the MouseIsOver global: retail 12.0 dropped
        -- the global. See LibGraph-2.0.lua's PieChart_OnUpdate for the full note.
        if not graph:IsMouseOver() or #renderedSeries == 0 then
            hairline:Hide()
            return
        end

        local w   = graph:GetWidth()
        local h   = graph:GetHeight()
        local xMin = graph.XMin or 0
        local xMax = graph.XMax or 1
        local xRange = xMax - xMin
        if xRange == 0 then hairline:Hide(); return end

        -- Mouse position relative to lg BOTTOMLEFT. Only the horizontal offset is
        -- used -- the hairline is vertical and spans the full height.
        local mX = GetCursorPosition()
        local scale  = graph:GetEffectiveScale()
        local lX = graph:GetLeft()
        local relX = mX / scale - lX   -- pixels from left edge

        -- Clamp to graph area
        relX = math.max(0, math.min(w, relX))

        -- Convert pixel → data x
        local dataX = xMin + (relX / w) * xRange

        -- Draw crosshair
        hairline:ClearAllPoints()
        hairline:SetPoint("BOTTOMLEFT",  self, "BOTTOMLEFT",  relX, 0)
        hairline:SetPoint("TOPLEFT",     self, "BOTTOMLEFT",  relX, h)
        hairline:Show()

        -- Build tooltip
        GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
        -- Format the X label: if XMin looks like a GetTime() absolute value (>10000),
        -- show relative seconds; otherwise already relative (per-fight mode)
        local xLabel
        if xMin > 10000 then
            xLabel = string.format("T + %.1fs", dataX - xMin)
        else
            xLabel = string.format("T + %.1fs", dataX)
        end
        GameTooltip:SetText(xLabel, 1, 1, 1)

        local anyFound = false
        for _, s in ipairs(renderedSeries) do
            local y = InterpY(s.times, s.values, dataX)
            if y then
                local r, g, b = s.color[1], s.color[2], s.color[3]
                GameTooltip:AddDoubleLine(s.label, FormatVal(y), r, g, b, r, g, b)
                anyFound = true
            end
        end
        if not anyFound then
            GameTooltip:AddLine("(no data at cursor)", 0.6, 0.6, 0.6)
        end
        GameTooltip:Show()
    end)

    lg:SetScript("OnLeave", function()
        hairline:Hide()
        GameTooltip:Hide()
    end)

    -- ── Right panel ────────────────────────────────────────────────────────
    local PANEL_X = -246  -- from right edge
    local PANEL_W = 240

    -- Section: Add Series ──────────────────────────────────────────────────
    local secLabel = win:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    secLabel:SetPoint("TOPRIGHT", win, "TOPRIGHT", -4, -34)
    secLabel:SetText("Add Series")

    -- Player dropdown
    local pdLabel = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    pdLabel:SetPoint("TOPRIGHT", win, "TOPRIGHT", -4, -54)
    pdLabel:SetText("Player:")
    pdLabel:SetJustifyH("RIGHT")

    local playerDD = CreateFrame("Frame", "RecountCompare_PlayerDropDown", win,
        "UIDropDownMenuTemplate")
    UIDropDownMenu_SetWidth(playerDD, 155)
    playerDD:SetPoint("TOPRIGHT", win, "TOPRIGHT", -4, -64)

    win.PlayerDropDown = playerDD
    win.PlayerDropDownInit = function(_dropdown, level)
        local players = GetCombatants()
        if #players == 0 then
            local info = UIDropDownMenu_CreateInfo()
            info.text = "(no data yet)"
            info.disabled = true
            UIDropDownMenu_AddButton(info, level)
            return
        end
        for _, name in ipairs(players) do
            local info = UIDropDownMenu_CreateInfo()
            info.text  = name
            info.value = name
            info.func  = function(self2)
                selectedPlayer = self2.value
                UIDropDownMenu_SetSelectedValue(playerDD, self2.value)
                UIDropDownMenu_SetText(playerDD, self2.value)
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end
    UIDropDownMenu_Initialize(playerDD, win.PlayerDropDownInit)
    UIDropDownMenu_SetText(playerDD, "Select Player")
    playerDD:SetScript("OnEnter", function()
        GameTooltip:SetOwner(playerDD, "ANCHOR_TOPRIGHT")
        GameTooltip:SetText("Player", 1, 1, 1)
        GameTooltip:AddLine("Choose the player whose data you want to plot.", nil, nil, nil, true)
        GameTooltip:Show()
    end)
    playerDD:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Metric dropdown
    local mdLabel = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    mdLabel:SetPoint("TOPRIGHT", win, "TOPRIGHT", -4, -100)
    mdLabel:SetText("Metric:")
    mdLabel:SetJustifyH("RIGHT")

    local metricDD = CreateFrame("Frame", "RecountCompare_MetricDropDown", win,
        "UIDropDownMenuTemplate")
    UIDropDownMenu_SetWidth(metricDD, 155)
    metricDD:SetPoint("TOPRIGHT", win, "TOPRIGHT", -4, -110)

    win.MetricDropDown = metricDD
    UIDropDownMenu_Initialize(metricDD, function(_dropdown, level)
        for i, m in ipairs(Metrics) do
            local info = UIDropDownMenu_CreateInfo()
            info.text  = m[1]
            info.value = i
            info.func  = function(self2)
                selectedMetricIdx = self2.value
                UIDropDownMenu_SetSelectedValue(metricDD, self2.value)
                UIDropDownMenu_SetText(metricDD, Metrics[self2.value][1])
            end
            UIDropDownMenu_AddButton(info, level)
        end
    end)
    UIDropDownMenu_SetText(metricDD, Metrics[1][1])
    selectedMetricIdx = 1
    metricDD:SetScript("OnEnter", function()
        GameTooltip:SetOwner(metricDD, "ANCHOR_TOPRIGHT")
        GameTooltip:SetText("Metric", 1, 1, 1)
        GameTooltip:AddLine("Choose what to graph for the selected player.\n\n|cffffd700Damage Done / Healing Done|r — cumulative total (requires Record Time Data).\n|cffffd700DPS / TPS|r — per-second rate over time.\n|cffffd700Normalize|r both series to compare shapes regardless of scale.", nil, nil, nil, true)
        GameTooltip:Show()
    end)
    metricDD:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Fight dropdown
    local fdLabel = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fdLabel:SetPoint("TOPRIGHT", win, "TOPRIGHT", -4, -136)
    fdLabel:SetText("Fight:")
    fdLabel:SetJustifyH("RIGHT")

    local fightDD = CreateFrame("Frame", "RecountCompare_FightDropDown", win,
        "UIDropDownMenuTemplate")
    UIDropDownMenu_SetWidth(fightDD, 155)
    fightDD:SetPoint("TOPRIGHT", win, "TOPRIGHT", -4, -146)
    win.FightDropDown = fightDD

    local function RebuildFightDropdown(_dropdown, level)
        local ct = Recount.db2 and Recount.db2.CombatTimes
        -- "All Fights" entry
        local info = UIDropDownMenu_CreateInfo()
        info.text  = "All Fights"
        info.value = 0
        info.func  = function()
            selectedFightIdx = 0
            UIDropDownMenu_SetSelectedValue(fightDD, 0)
            UIDropDownMenu_SetText(fightDD, "All Fights")
            RefreshCompareGraph()
        end
        UIDropDownMenu_AddButton(info, level)
        if ct then
            for i, v in ipairs(ct) do
                info = UIDropDownMenu_CreateInfo()
                local dur = math.floor(v[2] - v[1])
                info.text  = "Fight " .. i .. "  (" .. dur .. "s)"
                info.value = i
                info.func  = function(self2)
                    selectedFightIdx = self2.value
                    UIDropDownMenu_SetSelectedValue(fightDD, self2.value)
                    local vv = Recount.db2.CombatTimes[self2.value]
                    UIDropDownMenu_SetText(fightDD, "Fight " .. self2.value .. "  (" .. math.floor(vv[2]-vv[1]) .. "s)")
                    RefreshCompareGraph()
                end
                UIDropDownMenu_AddButton(info, level)
            end
        end
    end
    UIDropDownMenu_Initialize(fightDD, RebuildFightDropdown)
    UIDropDownMenu_SetText(fightDD, "All Fights")
    selectedFightIdx = 0
    fightDD:SetScript("OnEnter", function()
        GameTooltip:SetOwner(fightDD, "ANCHOR_TOPRIGHT")
        GameTooltip:SetText("Fight Filter", 1, 1, 1)
        GameTooltip:AddLine("Restrict the graph to a specific combat encounter.\nSelect 'All Fights' to show the full session history.", nil, nil, nil, true)
        GameTooltip:Show()
    end)
    fightDD:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Add button
    local addBtn = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    addBtn:SetWidth(80); addBtn:SetHeight(22)
    addBtn:SetPoint("TOPRIGHT", win, "TOPRIGHT", -80, -196)
    addBtn:SetText("Add")
    addBtn:SetScript("OnClick", AddFilter)
    addBtn:SetScript("OnEnter", function()
        GameTooltip:SetOwner(addBtn, "ANCHOR_LEFT")
        GameTooltip:SetText("Add Series", 1, 1, 1)
        GameTooltip:AddLine("Adds the selected player + metric combination as a new line on the graph.\nYou can add multiple series to compare them side by side.", nil, nil, nil, true)
        GameTooltip:Show()
    end)
    addBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Clear button
    local clearBtn = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    clearBtn:SetWidth(70); clearBtn:SetHeight(22)
    clearBtn:SetPoint("RIGHT", addBtn, "LEFT", -4, 0)
    clearBtn:SetText("Clear All")
    clearBtn:SetScript("OnClick", ClearAllFilters)
    clearBtn:SetScript("OnEnter", function()
        GameTooltip:SetOwner(clearBtn, "ANCHOR_LEFT")
        GameTooltip:SetText("Clear All Series", 1, 1, 1)
        GameTooltip:AddLine("Removes all plotted series and resets the graph.", nil, nil, nil, true)
        GameTooltip:Show()
    end)
    clearBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Separator
    local sep = win:CreateTexture(nil, "BACKGROUND")
    sep:SetHeight(1)
    sep:SetPoint("TOPLEFT",  win, "TOPRIGHT", PANEL_X + 5, -226)
    sep:SetPoint("TOPRIGHT", win, "TOPRIGHT", -4,          -226)
    sep:SetColorTexture(0.5, 0.5, 0.5, 0.8)

    -- Active filters header
    local filterLabel = win:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    filterLabel:SetPoint("TOPRIGHT", win, "TOPRIGHT", -4, -234)
    filterLabel:SetText("Active Series")

    -- Filter rows (up to 9 visible — leaves room for options below)
    win.FilterRows = {}
    local MAX_FILTER_ROWS = 9
    for i = 1, MAX_FILTER_ROWS do
        local row = CreateFrame("Frame", nil, win)
        row:SetWidth(PANEL_W)
        row:SetHeight(16)
        row:SetPoint("TOPRIGHT", win, "TOPRIGHT", -4, -234 - i * 18)

        row.Key = row:CreateTexture(nil, "OVERLAY")
        row.Key:SetTexture("Interface\\Buttons\\WHITE8X8.blp")
        row.Key:SetWidth(10); row.Key:SetHeight(10)
        row.Key:SetPoint("LEFT", row, "LEFT", 0, 0)

        row.Name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.Name:SetPoint("LEFT", row, "LEFT", 14, 0)
        row.Name:SetPoint("RIGHT", row, "RIGHT", -18, 0)
        row.Name:SetJustifyH("LEFT")
        row.Name:SetTextColor(1, 1, 1)

        row.RemoveBtn = CreateFrame("Button", nil, row)
        row.RemoveBtn:SetWidth(14); row.RemoveBtn:SetHeight(14)
        row.RemoveBtn:SetPoint("RIGHT", row, "RIGHT", 0, 0)
        row.RemoveBtn:SetNormalTexture("Interface\\Buttons\\UI-StopButton")
        row.RemoveBtn:SetHighlightTexture("Interface\\Buttons\\UI-Panel-MinimizeButton-Highlight")
        row.RemoveBtn:SetScript("OnClick", function(button)
            RemoveFilter(button.filterIdx)
        end)

        row:Hide()
        win.FilterRows[i] = row
    end

    -- ── Graph options (right panel, below active series list) ──────────────
    -- Second separator
    local sep2 = win:CreateTexture(nil, "BACKGROUND")
    sep2:SetHeight(1)
    sep2:SetPoint("TOPLEFT",  win, "TOPRIGHT", PANEL_X + 5, -408)
    sep2:SetPoint("TOPRIGHT", win, "TOPRIGHT", -4,          -408)
    sep2:SetColorTexture(0.5, 0.5, 0.5, 0.8)

    local function MakeCheckbox(parent, labelText, yOfs)
        local frame = CreateFrame("Frame", nil, parent)
        frame:SetWidth(PANEL_W); frame:SetHeight(18)
        frame:SetPoint("TOPRIGHT", parent, "TOPRIGHT", -4, yOfs)

        frame.Check = CreateFrame("CheckButton", nil, frame)
        frame.Check:SetWidth(18); frame.Check:SetHeight(18)
        frame.Check:SetPoint("LEFT", frame, "LEFT", 0, 0)
        frame.Check:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
        frame.Check:SetPushedTexture("Interface\\Buttons\\UI-CheckBox-Down")
        frame.Check:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
        frame.Check:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight")
        frame.Check:SetChecked(false)

        frame.Text = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        frame.Text:SetPoint("LEFT", frame.Check, "RIGHT", 4, 0)
        frame.Text:SetText(labelText)

        return frame
    end

    win.Normalize = MakeCheckbox(win, L["Normalize"], -416)
    win.Normalize.Check:SetScript("OnClick", function(this)
        win.NormalizeOn = this:GetChecked() and true or false
        RefreshCompareGraph()
    end)
    win.Normalize:SetScript("OnEnter", function()
        GameTooltip:SetOwner(win.Normalize, "ANCHOR_LEFT")
        GameTooltip:SetText("Normalize", 1, 1, 1)
        GameTooltip:AddLine("Rescales all series to 0-100% of their own peak.\nUseful when comparing metrics with very different magnitudes,\ne.g. DPS vs Threat on the same graph.", nil, nil, nil, true)
        GameTooltip:Show()
    end)
    win.Normalize:SetScript("OnLeave", function() GameTooltip:Hide() end)

    win.Integrate = MakeCheckbox(win, L["Integrate"], -438)
    win.Integrate.Check:SetScript("OnClick", function(this)
        win.IntegrateOn = this:GetChecked() and true or false
        RefreshCompareGraph()
    end)
    win.Integrate:SetScript("OnEnter", function()
        GameTooltip:SetOwner(win.Integrate, "ANCHOR_LEFT")
        GameTooltip:SetText("Integrate", 1, 1, 1)
        GameTooltip:AddLine("Converts per-second rates into running cumulative totals.\nForced on automatically for Damage Done, Healing Done, etc.\nEnable manually to integrate DPS or TPS into total values.", nil, nil, nil, true)
        GameTooltip:Show()
    end)
    win.Integrate:SetScript("OnLeave", function() GameTooltip:Hide() end)

    win.PerFight = MakeCheckbox(win, "Per Fight", -460)
    win.PerFight.Check:SetScript("OnClick", function(this)
        win.PerFightOn = this:GetChecked() and true or false
        RefreshCompareGraph()
    end)
    win.PerFight:SetScript("OnEnter", function()
        GameTooltip:SetOwner(win.PerFight, "ANCHOR_LEFT")
        GameTooltip:SetText("Per Fight", 1, 1, 1)
        GameTooltip:AddLine("Plots ALL fights as a continuous sawtooth line.\n\nEach fight rises from 0 as damage/healing accumulates,\nthen snaps back to 0 at fight end. Out-of-combat gaps\nappear as flat-zero stretches between humps.\n\nX axis = seconds since first recorded fight.\nUseful for comparing output across an entire raid session.", nil, nil, nil, true)
        GameTooltip:Show()
    end)
    win.PerFight:SetScript("OnLeave", function() GameTooltip:Hide() end)

    -- Refresh button
    local refreshBtn = CreateFrame("Button", nil, win)
    refreshBtn:SetNormalTexture("Interface\\Buttons\\UI-RotationLeft-Button-Up")
    refreshBtn:SetPushedTexture("Interface\\Buttons\\UI-RotationLeft-Button-Down")
    refreshBtn:SetWidth(20); refreshBtn:SetHeight(20)
    refreshBtn:SetPoint("TOPRIGHT", close, "TOPLEFT", -2, 0)
    refreshBtn:SetScript("OnClick", RefreshCompareGraph)
    refreshBtn:SetScript("OnEnter", function()
        GameTooltip:SetOwner(refreshBtn, "ANCHOR_BOTTOMRIGHT")
        GameTooltip:SetText("Refresh Graph", 1, 1, 1)
        GameTooltip:AddLine("Redraws the graph from the latest recorded data.", nil, nil, nil, true)
        GameTooltip:Show()
    end)
    refreshBtn:SetScript("OnLeave", function() GameTooltip:Hide() end)

    win.NormalizeOn = false
    win.IntegrateOn = false
    win.PerFightOn  = false

    Recount:AddWindow(win)
    win:Hide()
end
