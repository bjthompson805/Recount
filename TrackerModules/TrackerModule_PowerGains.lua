local Recount = _G.Recount

local AceLocale = LibStub("AceLocale-3.0")
local L = AceLocale:GetLocale( "Recount" )

local revision = tonumber(string.sub("$Revision: 1453 $", 12, -3))
if Recount.Version < revision then
	Recount.Version = revision
end

local GameTooltip = GameTooltip

local dbCombatants
-- No srcRetention / dstRetention file-locals here, unlike the sibling modules.
-- AddGain is reached from two handlers with opposite src/dst orientations, so
-- those two names have no single correct meaning in this file; the retention
-- pair is a parameter instead. See the note above SpellEnergize.

local DetailTitles = { }
DetailTitles.Gained = {
	TopNames = L["Ability"],
	TopCount = "",
	TopAmount = L["Gained"],
	BotNames = L["From"],
	BotMin = "",
	BotAvg = "",
	BotMax = "",
	BotAmount = L["Gained"]
}

DetailTitles.GainedFrom = {
	TopNames = L["From"],
	TopCount = "",
	TopAmount = L["Gained"],
	BotNames = L["Ability"],
	BotMin = "",
	BotAvg = "",
	BotMax = "",
	BotAmount = L["Gained"]
}

-- The giving side. Mirrors Gained/GainedFrom with the roles swapped, so the
-- detail window reads the same way whichever direction you came from.
DetailTitles.Given = {
	TopNames = L["Ability"],
	TopCount = "",
	TopAmount = L["Given"],
	BotNames = L["To"],
	BotMin = "",
	BotAvg = "",
	BotMax = "",
	BotAmount = L["Given"]
}

DetailTitles.GivenTo = {
	TopNames = L["To"],
	TopCount = "",
	TopAmount = L["Given"],
	BotNames = L["Ability"],
	BotMin = "",
	BotAvg = "",
	BotMax = "",
	BotAmount = L["Given"]
}

local POWERTYPE_MANA = 0
local POWERTYPE_RAGE = 1
local POWERTYPE_FOCUS = 2
local POWERTYPE_ENERGY = 3
local POWERTYPE_HAPPINESS = 4
local POWERTYPE_RUNES = 5
local POWERTYPE_RUNIC_POWER = 6
local POWERTYPE_LUNAR_POWER = 8
local POWERTYPE_MAELSTROM = 11
local POWERTYPE_FURY = 17
local POWERTYPE_PAIN = 18

local PowerTypeName = { -- Elsia: Do NOT localize this, it breaks functionality!!! If you need this localized contact me on WowAce or Curse.
	[POWERTYPE_MANA] = "Mana",
	[POWERTYPE_RAGE] = "Rage",
	[POWERTYPE_ENERGY] = "Energy",
	[POWERTYPE_FOCUS] = "Focus",
	[POWERTYPE_HAPPINESS] = "Happiness",
	[POWERTYPE_RUNES] = "Runes",
	[POWERTYPE_RUNIC_POWER] = "Runic Power",
	[POWERTYPE_LUNAR_POWER] = "Astral Power",
	[POWERTYPE_MAELSTROM] = "Maelstorm",
	[POWERTYPE_FURY] = "Fury",
	[POWERTYPE_PAIN] = "Pain",
}

-- AddGain's `source` is whoever GAINS the power and `victim` whoever it came
-- from, and the two callers below reach that from OPPOSITE ends of the combat
-- log: an energize is the caster granting power to someone else, a leech is the
-- caster taking it. Every name, GUID and flag pair is therefore ordered by the
-- caller -- and so, since the fix for finding 7, are the two retention flags.
--
-- They used to be read from Recount.srcRetention / Recount.dstRetention inside
-- AddGain, which cannot work: those are set once per event from the COMBAT LOG's
-- src and dst (Tracker.lua:1195-1196), so a single fixed choice is right for one
-- caller and inverted for the other. It was inverted for SpellEnergize for
-- years, and the fix that corrected that inverted SpellLeech instead -- a
-- warlock with mob tracking off then lost their own drained mana entirely. The
-- orientation is a property of the caller, so the caller passes it.
-- Both handlers are dispatched POSITIONALLY, so each declares the client's full
-- argument list whether or not it reads every name. Unread positions carry a
-- leading underscore: the name still documents what the slot holds, and the
-- prefix is what tells luacheck the omission is deliberate.
function Recount:SpellEnergize(_timestamp, _eventtype, srcGUID, srcName, srcFlags, dstGUID, dstName, dstFlags, spellId, spellName, _spellSchool, amount, _overEnergized, powerType)
	Recount:AddGain(dstName, srcName, spellName, amount, PowerTypeName[powerType], dstGUID, dstFlags, srcGUID, srcFlags, spellId,
		Recount.dstRetention, Recount.srcRetention, true)
end

function Recount:SpellLeech(_timestamp, _eventtype, srcGUID, srcName, srcFlags, dstGUID, dstName, dstFlags,spellId, spellName, _spellSchool, _amount, powerType, extraAmount)
	-- recordGiving is FALSE here, deliberately. The giving-side record answers
	-- "how much mana did my ability grant the group", and a leech grants nobody
	-- anything -- it takes. Filing the drained mob under "Mana Given" would put a
	-- boss on that bar for mana that was taken from it, which reads as the
	-- opposite of what happened.
	Recount:AddGain(srcName, dstName, spellName, extraAmount, PowerTypeName[powerType], srcGUID, srcFlags, dstGUID, dstFlags, spellId,
		Recount.srcRetention, Recount.dstRetention, false)
end

local DataAmount, DataTable, DataTable2
-- The giving-side field names. These are file-locals reused across calls exactly
-- like the three above, so they MUST be cleared for every power type that does
-- not set them -- otherwise a Rage gain immediately after a Mana one would still
-- see "ManaGiven" here and file rage under the mana totals.
local DataAmountGiven, DataTableGiven, DataTableGiven2
-- gainerRetention / giverRetention are the caller's own ordering of
-- Recount.srcRetention and Recount.dstRetention; see the note above the two
-- callers for why they cannot be read from the globals here. recordGiving says
-- whether a giving-side record is meaningful for this event at all.
function Recount:AddGain(source, victim, ability, amount, attribute,srcGUID,srcFlags,dstGUID,dstFlags,_spellId, gainerRetention, giverRetention, recordGiving)

	DataAmountGiven, DataTableGiven, DataTableGiven2 = nil, nil, nil

	if attribute == "Mana" then
		DataAmount = "ManaGain"
		DataTable = "ManaGained"
		DataTable2 = "ManaGainedFrom"
		-- Mana is the only power type one player routinely grants another
		-- (Judgement of Wisdom, Vampiric Touch, Innervate, Mana Tide Totem).
		-- Rage, Energy, Focus and the rest are self-generated, so a giving-side
		-- view of them would be permanently empty and would double the mode list
		-- for nothing. Adding one later is three lines in the matching branch.
		DataAmountGiven = "ManaGiven"
		DataTableGiven = "ManaGives"
		DataTableGiven2 = "ManaGivenTo"
	elseif attribute == "Energy" or attribute == "Focus" then -- Elsia: Focus for pet.
		DataAmount = "EnergyGain"
		DataTable = "EnergyGained"
		DataTable2 = "EnergyGainedFrom"
	elseif attribute == "Rage" then
		DataAmount = "RageGain"
		DataTable = "RageGained"
		DataTable2 = "RageGainedFrom"
	elseif attribute == "Runic Power" then
		DataAmount = "RunicPowerGain"
		DataTable = "RunicPowerGained"
		DataTable2 = "RunicPowerGainedFrom"
	elseif attribute == "Astral Power" then
		DataAmount = "AstralPowerGain"
		DataTable = "AstralPowerGained"
		DataTable2 = "AstralPowerGainedFrom"
	elseif attribute == "Maelstorm" then
		DataAmount = "MaelstormGain"
		DataTable = "MaelstormGained"
		DataTable2 = "MaelstormGainedFrom"
	elseif attribute == "Fury" then
		DataAmount = "FuryGain"
		DataTable = "FuryGained"
		DataTable2 = "FuryGainedFrom"
	elseif attribute == "Pain" then
		DataAmount = "PainGain"
		DataTable = "PainGained"
		DataTable2 = "PainGainedFrom"
	else
		return
	end

	-- Name and ID of pet owners
	local sourceowner
	local sourceownerID
	local victimowner
	local victimownerID

	source, sourceowner, sourceownerID = Recount:DetectPet(source, srcGUID, srcFlags)
	victim, victimowner, victimownerID = Recount:DetectPet(victim, dstGUID, dstFlags)

	if gainerRetention then

		if not dbCombatants[source] then
			Recount:AddCombatant(source, sourceowner, srcGUID, srcFlags, sourceownerID)
		end -- Elsia: Until here is if pets heal anybody.
		local sourceData = dbCombatants[source]
		Recount:SetActive(sourceData)

		Recount:AddAmount(sourceData,DataAmount,amount)
		Recount:AddTableDataSum(sourceData, DataTable, ability, victim, amount)
		Recount:AddTableDataSum(sourceData, DataTable2, victim, ability, amount)
	end

	-- The giving side, mirroring how healing records both directions: a healer
	-- gets Healing/Heals/HealedWho and the target gets HealingTaken/WhoHealed.
	-- Power gains only ever recorded the receiving half, so "how much mana did MY
	-- Judgement of Wisdom give the raid" had no answer -- every point of it was
	-- filed under whoever received it.
	--
	-- SetActive is a LIVENESS STAMP, not an activity accumulator: its whole body
	-- is `who.LastActive = Recount.CurTime` (Tracker.lua:1203), and LastActive has
	-- exactly one reader -- the idle sweep at Recount.lua:1607, which DELETES a
	-- combatant it classifies as an idler after 30 seconds without one. The
	-- per-second denominator is ActiveTime, written only by AddTimeEvent, which
	-- this block does not call and must not. So stamping here costs nothing on the
	-- per-second numbers and is what stops a giver's whole record -- ManaGiven
	-- included -- being collected out from under this mode. The retention test and
	-- the idler test are NOT the same predicate, so an admitted giver can be an
	-- idler: retention admits a trivial mob when EITHER mob filter is on, while
	-- the sweep consults that mob's own type.
	if recordGiving and giverRetention and DataAmountGiven then

		if not dbCombatants[victim] then
			Recount:AddCombatant(victim, victimowner, dstGUID, dstFlags, victimownerID)
		end
		local victimData = dbCombatants[victim]
		Recount:SetActive(victimData)

		Recount:AddAmount(victimData, DataAmountGiven, amount)
		Recount:AddTableDataSum(victimData, DataTableGiven, ability, source, amount)
		Recount:AddTableDataSum(victimData, DataTableGiven2, source, ability, amount)
	end
end

local DataModes = { }

function DataModes:ManaGained(data, num)
	if not data then
		return 0
	end
	if num == 1 then
		return (data.Fights[Recount.db.profile.CurDataSet].ManaGain or 0)
	end
	return (data.Fights[Recount.db.profile.CurDataSet].ManaGain or 0), {{data.Fights[Recount.db.profile.CurDataSet].ManaGained, L["'s Mana Gained"], DetailTitles.Gained}, {data.Fights[Recount.db.profile.CurDataSet].ManaGainedFrom, L["'s Mana Gained From"], DetailTitles.GainedFrom}}
end

-- The inverse of ManaGained: bars are the players who GAVE mana, so a paladin's
-- Judgement of Wisdom or a priest's Vampiric Touch shows up as one number for the
-- whole group instead of being scattered across every recipient's record.
function DataModes:ManaGiven(data, num)
	if not data then
		return 0
	end
	if num == 1 then
		return (data.Fights[Recount.db.profile.CurDataSet].ManaGiven or 0)
	end
	return (data.Fights[Recount.db.profile.CurDataSet].ManaGiven or 0), {{data.Fights[Recount.db.profile.CurDataSet].ManaGives, L["'s Mana Given"], DetailTitles.Given}, {data.Fights[Recount.db.profile.CurDataSet].ManaGivenTo, L["'s Mana Given To"], DetailTitles.GivenTo}}
end

function DataModes:EnergyGained(data, num)
	if not data then
		return 0
	end
	if num == 1 then
		return (data.Fights[Recount.db.profile.CurDataSet].EnergyGain or 0)
	end
	return (data.Fights[Recount.db.profile.CurDataSet].EnergyGain or 0), {{data.Fights[Recount.db.profile.CurDataSet].EnergyGained, L["'s Energy Gained"], DetailTitles.Gained}, {data.Fights[Recount.db.profile.CurDataSet].EnergyGainedFrom, L["'s Energy Gained From"], DetailTitles.GainedFrom}}
end

function DataModes:RageGained(data, num)
	if not data then
		return 0
	end
	if num == 1 then
		return (data.Fights[Recount.db.profile.CurDataSet].RageGain or 0)
	end
	return (data.Fights[Recount.db.profile.CurDataSet].RageGain or 0), {{data.Fights[Recount.db.profile.CurDataSet].RageGained, L["'s Rage Gained"], DetailTitles.Gained}, {data.Fights[Recount.db.profile.CurDataSet].RageGainedFrom, L["'s Rage Gained From"], DetailTitles.GainedFrom}}
end

function DataModes:RunicPowerGained(data, num)
	if not data then
		return 0
	end
	if num == 1 then
		return (data.Fights[Recount.db.profile.CurDataSet].RunicPowerGain or 0)
	end
	return (data.Fights[Recount.db.profile.CurDataSet].RunicPowerGain or 0), {{data.Fights[Recount.db.profile.CurDataSet].RunicPowerGained, L["'s Runic Power Gained"], DetailTitles.Gained}, {data.Fights[Recount.db.profile.CurDataSet].RunicPowerGainedFrom, L["'s Runic Power Gained From"], DetailTitles.GainedFrom}}
end

function DataModes:AstralPowerGained(data, num)
	if not data then
		return 0
	end
	if num == 1 then
		return (data.Fights[Recount.db.profile.CurDataSet].AstralPowerGain or 0)
	end
	return (data.Fights[Recount.db.profile.CurDataSet].AstralPowerGain or 0), {{data.Fights[Recount.db.profile.CurDataSet].AstralPowerGained, L["'s Astral Power Gained"], DetailTitles.Gained}, {data.Fights[Recount.db.profile.CurDataSet].AstralPowerGainedFrom, L["'s Astral Power Gained From"], DetailTitles.GainedFrom}}
end

function DataModes:MaelstormGained(data, num)
	if not data then
		return 0
	end
	if num == 1 then
		return (data.Fights[Recount.db.profile.CurDataSet].MaelstormGain or 0)
	end
	return (data.Fights[Recount.db.profile.CurDataSet].MaelstormGain or 0), {{data.Fights[Recount.db.profile.CurDataSet].MaelstormGained, L["'s Maelstorm Gained"], DetailTitles.Gained}, {data.Fights[Recount.db.profile.CurDataSet].MaelstormGainedFrom, L["'s Maelstorm Gained From"], DetailTitles.GainedFrom}}
end

function DataModes:FuryGained(data, num)
	if not data then
		return 0
	end
	if num == 1 then
		return (data.Fights[Recount.db.profile.CurDataSet].FuryGain or 0)
	end
	return (data.Fights[Recount.db.profile.CurDataSet].FuryGain or 0), {{data.Fights[Recount.db.profile.CurDataSet].FuryGained, L["'s Fury Gained"], DetailTitles.Gained}, {data.Fights[Recount.db.profile.CurDataSet].FuryGainedFrom, L["'s Fury Gained From"], DetailTitles.GainedFrom}}
end

function DataModes:PainGained(data, num)
	if not data then
		return 0
	end
	if num == 1 then
		return (data.Fights[Recount.db.profile.CurDataSet].PainGain or 0)
	end
	return (data.Fights[Recount.db.profile.CurDataSet].PainGain or 0), {{data.Fights[Recount.db.profile.CurDataSet].PainGained, L["'s Pain Gained"], DetailTitles.Gained}, {data.Fights[Recount.db.profile.CurDataSet].PainGainedFrom, L["'s Pain Gained From"], DetailTitles.GainedFrom}}
end

local TooltipFuncs = { }

function TooltipFuncs:ManaGained(name, data)
	--local SortedData, total
	GameTooltip:ClearLines()
	GameTooltip:AddLine(name)
	Recount:AddSortedTooltipData(L["Top 3"].." "..L["Mana Abilities"], data and data.Fights[Recount.db.profile.CurDataSet] and data.Fights[Recount.db.profile.CurDataSet].ManaGained, 3)
	Recount:AddSortedTooltipData(L["Top 3"].." "..L["Mana Sources"], data and data.Fights[Recount.db.profile.CurDataSet] and data.Fights[Recount.db.profile.CurDataSet].ManaGainedFrom, 3)
	GameTooltip:AddLine("<"..L["Click for more Details"]..">", 0, 0.9, 0)
end

function TooltipFuncs:ManaGiven(name, data)
	GameTooltip:ClearLines()
	GameTooltip:AddLine(name)
	Recount:AddSortedTooltipData(L["Top 3"].." "..L["Mana Given Abilities"], data and data.Fights[Recount.db.profile.CurDataSet] and data.Fights[Recount.db.profile.CurDataSet].ManaGives, 3)
	Recount:AddSortedTooltipData(L["Top 3"].." "..L["Mana Given Recipients"], data and data.Fights[Recount.db.profile.CurDataSet] and data.Fights[Recount.db.profile.CurDataSet].ManaGivenTo, 3)
	GameTooltip:AddLine("<"..L["Click for more Details"]..">", 0, 0.9, 0)
end

function TooltipFuncs:EnergyGained(name, data)
	--local SortedData, total
	GameTooltip:ClearLines()
	GameTooltip:AddLine(name)
	Recount:AddSortedTooltipData(L["Top 3"].." "..L["Energy Abilities"], data and data.Fights[Recount.db.profile.CurDataSet] and data.Fights[Recount.db.profile.CurDataSet].EnergyGained, 3)
	Recount:AddSortedTooltipData(L["Top 3"].." "..L["Energy Sources"], data and data.Fights[Recount.db.profile.CurDataSet] and data.Fights[Recount.db.profile.CurDataSet].EnergyGainedFrom, 3)
	GameTooltip:AddLine("<"..L["Click for more Details"]..">", 0, 0.9, 0)
end

function TooltipFuncs:RageGained(name, data)
	--local SortedData, total
	GameTooltip:ClearLines()
	GameTooltip:AddLine(name)
	Recount:AddSortedTooltipData(L["Top 3"].." "..L["Rage Abilities"], data and data.Fights[Recount.db.profile.CurDataSet] and data.Fights[Recount.db.profile.CurDataSet].RageGained, 3)
	Recount:AddSortedTooltipData(L["Top 3"].." "..L["Rage Sources"], data and data.Fights[Recount.db.profile.CurDataSet] and data.Fights[Recount.db.profile.CurDataSet].RageGainedFrom, 3)
	GameTooltip:AddLine("<"..L["Click for more Details"]..">", 0, 0.9, 0)
end

function TooltipFuncs:RunicPowerGained(name, data)
	--local SortedData, total
	GameTooltip:ClearLines()
	GameTooltip:AddLine(name)
	Recount:AddSortedTooltipData(L["Top 3"].." "..L["Runic Power Abilities"], data and data.Fights[Recount.db.profile.CurDataSet] and data.Fights[Recount.db.profile.CurDataSet].RunicPowerGained, 3)
	Recount:AddSortedTooltipData(L["Top 3"].." "..L["Runic Power Sources"], data and data.Fights[Recount.db.profile.CurDataSet] and data.Fights[Recount.db.profile.CurDataSet].RunicPowerGainedFrom, 3)
	GameTooltip:AddLine("<"..L["Click for more Details"]..">", 0, 0.9, 0)
end

function TooltipFuncs:AstralPowerGained(name, data)
	--local SortedData, total
	GameTooltip:ClearLines()
	GameTooltip:AddLine(name)
	Recount:AddSortedTooltipData(L["Top 3"].." "..L["Astral Power Abilities"], data and data.Fights[Recount.db.profile.CurDataSet] and data.Fights[Recount.db.profile.CurDataSet].AstralPowerGained, 3)
	Recount:AddSortedTooltipData(L["Top 3"].." "..L["Astral Power Sources"], data and data.Fights[Recount.db.profile.CurDataSet] and data.Fights[Recount.db.profile.CurDataSet].AstralPowerGainedFrom, 3)
	GameTooltip:AddLine("<"..L["Click for more Details"]..">", 0, 0.9, 0)
end

function TooltipFuncs:MaelstormGained(name, data)
	--local SortedData, total
	GameTooltip:ClearLines()
	GameTooltip:AddLine(name)
	Recount:AddSortedTooltipData(L["Top 3"].." "..L["Maelstorm Abilities"], data and data.Fights[Recount.db.profile.CurDataSet] and data.Fights[Recount.db.profile.CurDataSet].MaelstormGained, 3)
	Recount:AddSortedTooltipData(L["Top 3"].." "..L["Maelstorm Sources"], data and data.Fights[Recount.db.profile.CurDataSet] and data.Fights[Recount.db.profile.CurDataSet].MaelstormGainedFrom, 3)
	GameTooltip:AddLine("<"..L["Click for more Details"]..">", 0, 0.9, 0)
end

function TooltipFuncs:FuryGained(name, data)
	--local SortedData, total
	GameTooltip:ClearLines()
	GameTooltip:AddLine(name)
	Recount:AddSortedTooltipData(L["Top 3"].." "..L["Fury Abilities"], data and data.Fights[Recount.db.profile.CurDataSet] and data.Fights[Recount.db.profile.CurDataSet].FuryGained, 3)
	Recount:AddSortedTooltipData(L["Top 3"].." "..L["Fury Sources"], data and data.Fights[Recount.db.profile.CurDataSet] and data.Fights[Recount.db.profile.CurDataSet].FuryGainedFrom, 3)
	GameTooltip:AddLine("<"..L["Click for more Details"]..">", 0, 0.9, 0)
end

function TooltipFuncs:PainGained(name, data)
	--local SortedData, total
	GameTooltip:ClearLines()
	GameTooltip:AddLine(name)
	Recount:AddSortedTooltipData(L["Top 3"].." "..L["Pain Abilities"], data and data.Fights[Recount.db.profile.CurDataSet] and data.Fights[Recount.db.profile.CurDataSet].PainGained, 3)
	Recount:AddSortedTooltipData(L["Top 3"].." "..L["Pain Sources"], data and data.Fights[Recount.db.profile.CurDataSet] and data.Fights[Recount.db.profile.CurDataSet].PainGainedFrom, 3)
	GameTooltip:AddLine("<"..L["Click for more Details"]..">", 0, 0.9, 0)
end

Recount:AddModeTooltip(L["Mana Gained"], DataModes.ManaGained, TooltipFuncs.ManaGained)
Recount:AddModeTooltip(L["Mana Given"], DataModes.ManaGiven, TooltipFuncs.ManaGiven)
Recount:AddModeTooltip(L["Energy Gained"], DataModes.EnergyGained, TooltipFuncs.EnergyGained)
Recount:AddModeTooltip(L["Rage Gained"], DataModes.RageGained, TooltipFuncs.RageGained)
Recount:AddModeTooltip(L["Runic Power Gained"], DataModes.RunicPowerGained, TooltipFuncs.RunicPowerGained)
Recount:AddModeTooltip(L["Astral Power Gained"], DataModes.AstralPowerGained, TooltipFuncs.AstralPowerGained)
Recount:AddModeTooltip(L["Maelstorm Gained"], DataModes.MaelstormGained, TooltipFuncs.MaelstormGained)
Recount:AddModeTooltip(L["Fury Gained"], DataModes.FuryGained, TooltipFuncs.FuryGained)
Recount:AddModeTooltip(L["Pain Gained"], DataModes.PainGained, TooltipFuncs.PainGained)

local oldlocalizer = Recount.LocalizeCombatants
function Recount.LocalizeCombatants()
	dbCombatants = Recount.db2.combatants
	oldlocalizer()
end
