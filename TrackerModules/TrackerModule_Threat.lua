local Recount = _G.Recount

local GetTime = GetTime
local GetNumGroupMembers = GetNumGroupMembers
local GetNumPartyMembers = GetNumPartyMembers or GetNumSubgroupMembers
local IsInRaid = IsInRaid
local IsInGroup = IsInGroup
local UnitExists = UnitExists
local UnitName = UnitName
local UnitDetailedThreatSituation = UnitDetailedThreatSituation
local UnitCanAttack = UnitCanAttack
local math_floor = math.floor
local math_max = math.max

--[[
    Threat Tracker Module
    Polls UnitDetailedThreatSituation once per second (hooked into Recount:TimeTick).

    TimeData["Threat"] stores TPS in raw threat/s (same units as TimeData["Damage"] DPS),
    This makes it directly comparable to TimeData["Damage"] (DPS rate) in the graph:

        Graph, no toggles  → DPS vs TPS  (both rates, same shape language)
        Graph + Integrate  → cumulative Damage vs cumulative Threat over the fight
        Graph + Integrate
             + Normalize   → both scaled 0-100% regardless of magnitude difference

    ThreatPeak in FightData is tracked separately as the max cumulative k-threat,
    used only for the bar chart display (e.g. "629k").
]]

-- Per-player state: last cumulative k-threat and sample time, reset each combat.
local lastSample = {}   -- [name] = { val = cumulative_k_threat, time = timestamp }

local function CheckUnit(unit, dbCombatants, Time)
    if not UnitExists(unit) then return end
    local targetUnit = unit .. "target"
    if not UnitExists(targetUnit) then return end
    if not UnitCanAttack("player", targetUnit) then return end

    local _, _, _, _, threatValue =
        UnitDetailedThreatSituation(unit, targetUnit)
    if not threatValue or threatValue <= 0 then return end

    local name = UnitName(unit)
    if not name then return end
    local who = dbCombatants[name]
    if not who then return end

    -- k-threat with one decimal (e.g. 629.4)
    local val = math_floor(threatValue / 100 + 0.5) / 10

    -- ── ThreatPeak (bar chart) ────────────────────────────────────────────────
    -- Tracked as max cumulative k-threat so the bar shows the true total.
    if who.Fights then
        if who.Fights.CurrentFightData then
            if val > (who.Fights.CurrentFightData.ThreatPeak or 0) then
                who.Fights.CurrentFightData.ThreatPeak = val
            end
        end
        if who.Fights.OverallData then
            if val > (who.Fights.OverallData.ThreatPeak or 0) then
                who.Fights.OverallData.ThreatPeak = val
            end
        end
    end

    -- ── TPS time series (graph) ───────────────────────────────────────────────
    -- Only record if the user has "Record Time Data" enabled (same gate Recount
    -- uses for Damage/Healing time series).  Without this guard TPS would be the
    -- ONLY series in the graph when time data recording is off.
    if Recount.TickTimeData then
        local last = lastSample[name]
        if last and (Time - last.time) > 0 and (Time - last.time) <= 10 then
            local deltaTime = Time - last.time
            -- Multiply by 1000 to convert k-threat/s → raw threat/s so the
            -- time-series is in the same units as TimeData["Damage"] (raw values).
            -- Integration will then yield raw cumulative threat, matching bar chart totals.
            local tps = math_max(0, (val - last.val) / deltaTime * 1000)

            who.TimeData = who.TimeData or {}
            who.TimeData["Threat"] = who.TimeData["Threat"] or {{}, {}}
            local td = who.TimeData["Threat"]
            -- Rate data; store every point (1/s × 5 min = 300 points max).
            td[1][#td[1] + 1] = Time
            td[2][#td[2] + 1] = tps
        end
        lastSample[name] = { val = val, time = Time }
    end
end

local function PollThreat()
    if not Recount.db or not Recount.db.profile then return end
    if not Recount.db.profile.GlobalDataCollect then return end
    if not Recount.CurrentDataCollect then return end
    if not Recount.InCombat then return end
    if not Recount.db.profile.Modules.Threat then return end

    local dbCombatants = Recount.db2 and Recount.db2.combatants
    if not dbCombatants then return end

    local Time = Recount.CurTime or GetTime()

    if IsInRaid() then
        local num = GetNumGroupMembers()
        for i = 1, num do
            CheckUnit("raid" .. i, dbCombatants, Time)
        end
    elseif IsInGroup() then
        CheckUnit("player", dbCombatants, Time)
        local num = GetNumPartyMembers()
        for i = 1, num do
            CheckUnit("party" .. i, dbCombatants, Time)
        end
    else
        CheckUnit("player", dbCombatants, Time)
    end
end

local function OnCombatStart()
    -- Clear stale per-player samples so the first TPS delta of a new fight is clean.
    for k in pairs(lastSample) do
        lastSample[k] = nil
    end
end

-- Hook into the existing 1s repeating timer — no second timer needed.
hooksecurefunc(Recount, "TimeTick", PollThreat)

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:RegisterEvent("PLAYER_REGEN_DISABLED")
eventFrame:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_DISABLED" then
        OnCombatStart()
    else
        PollThreat()  -- final snapshot before MoveFights rotates the data
    end
end)
