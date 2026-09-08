local Recount = _G.Recount

local revision = tonumber(string.sub("$Revision: 1516 $", 12, -3))
if Recount.Version < revision then
	Recount.Version = revision
end

local C_Scenario = C_Scenario
local GetInstanceInfo = GetInstanceInfo
local GetNumPartyMembers = GetNumPartyMembers or GetNumSubgroupMembers
local GetNumRaidMembers = GetNumRaidMembers or GetNumGroupMembers
local IsInInstance = IsInInstance
local IsInRaid = IsInRaid
local IsInScenarioGroup = IsInScenarioGroup
local UnitIsGhost = UnitIsGhost

local WOW_RETAIL = WOW_PROJECT_ID == WOW_PROJECT_MAINLINE

--[[local TOC
do
	-- Because GetBuildInfo() still returns 40000 on the PTR
	local major, minor, rev = strsplit(".", (GetBuildInfo()))
	TOC = major * 10000 + minor * 100
end]]

function Recount:DetectInstanceChange() -- Elsia: With thanks to Loggerhead

	--local zone = GetRealZoneText()
	local zone = GetInstanceInfo() -- Elsia: GetInstanceInfo() is robust at PEW!

	if zone == "" then
		-- zone hasn't been loaded yet, try again in 5 secs.
		self:ScheduleTimer("DetectInstanceChange", 5)
		return
	end

	if UnitIsGhost(Recount.PlayerName) then
		return
	end

	-- `instanceType` was declared alongside this and never read: the second return
	-- of IsInInstance goes to `zone` here, and the later call at :81 wants only
	-- the first. The value assigned in this block is likewise overwritten at :81
	-- before anything reads it -- kept because C_Scenario.IsInScenario's result is
	-- printed by the DPrint below, which is the only consumer of it.
	local inInstance
	local _
	if zone == nil then
		-- Only the zone is wanted from this call: `inInstance` is re-read from a
		-- fresh IsInInstance() at :81 before anything tests it.
		_, zone = IsInInstance()
		if zone == nil then
			inInstance, zone = C_Scenario.IsInScenario()
			Recount:DPrint((inInstance or "nil") .. " : ".. (zone or "nil"))
		end
	end

	--[[local groupType

	if Recount.inRaid then
		groupType = 2
	elseif Recount.inGroup then
		groupType = 1
	else
		groupType = 0
	end

	local inInstance, instanceType = IsInInstance()
	if Recount.SetZoneGroupFilter and not UnitIsGhost(Recount.PlayerName) then Recount:SetZoneGroupFilter(instanceType, groupType) end -- Use zone-based filters.]]
	Recount:UpdateZoneGroupFilter()

	if not Recount.db.profile.AutoDeleteNewInstance then
		return
	end

	-- "is the combatant table non-empty" -- `next` answers that directly. The old
	-- form was a pairs() loop with an unconditional `break`, which luacheck reads
	-- as a loop that runs at most once because that is exactly what it is.
	local hasCombatants = next(Recount.db2.combatants) ~= nil
	if not hasCombatants then -- Elsia: Already deleted
		return
	end

	inInstance = IsInInstance()

	if inInstance and (not Recount.db.profile.DeleteNewInstanceOnly or Recount.db.profile.LastInstanceName ~= zone) and Recount.CurrentDataCollect then
		if Recount.db.profile.ConfirmDeleteInstance == true then
			--Recount:DPrint("Instance based deletion: Old: "..Recount.db.profile.LastInstanceName.." New: "..zone)
			Recount:ShowReset() -- Elsia: Confirm & Delete!
		else
			Recount:ResetData() -- Elsia: Delete!
		end
		Recount.db.profile.LastInstanceName = zone -- Elsia: We'll set the instance even if the user opted to not delete...
	end
end

-- Elsia: For delete on join raid/group

function Recount:PartyMembersChanged()
	-- "is the combatant table non-empty" -- `next` answers that directly. The old
	-- form was a pairs() loop with an unconditional `break`, which luacheck reads
	-- as a loop that runs at most once because that is exactly what it is.
	local hasCombatants = next(Recount.db2.combatants) ~= nil

	if hasCombatants and Recount.db.profile.DeleteJoinRaid and not Recount.inRaid and not Recount.inScenario and GetNumRaidMembers() > 0 and IsInRaid() and Recount.CurrentDataCollect then
		if Recount.db.profile.ConfirmDeleteRaid then
			--Recount:DPrint("Raid based deletion")
			Recount:ShowReset() -- Elsia: Confirm & Delete!
		else
			Recount:ResetData() -- Elsia: Delete!
		end

		--[[if Recount.RequestVersion then
			Recount:RequestVersion()
		end]] -- Elsia: If LazySync is present request version when entering raid
	end

	if hasCombatants and Recount.db.profile.DeleteJoinGroup and not Recount.inGroup and GetNumPartyMembers() > 0 and not IsInRaid() and Recount.CurrentDataCollect then
		if Recount.db.profile.ConfirmDeleteGroup then
			--Recount:DPrint("Group based deletion")
			Recount:ShowReset() -- Elsia: Confirm & Delete!
		else
			Recount:ResetData() -- Elsia: Delete!
		end

		--[[if Recount.RequestVersion then
			Recount:RequestVersion()
		end]] -- Elsia: If LazySync is present request version when entering party
	end

	-- No `= false` initialiser: the party/raid branch immediately below assigns
	-- `change` on both arms, so the initial value could never be read.
	local change

	if GetNumPartyMembers() > 0 and not IsInRaid() then -- Elsia: This seems to be always true -> or UnitInParty("player")
		change = not Recount.inGroup
		Recount.inGroup = true
	else
		change = Recount.inGroup
		Recount.inGroup = false
	end

	if IsInRaid() and not (WOW_RETAIL and IsInScenarioGroup()) then
		change = change or not Recount.inRaid
		Recount.inRaid = true
	else
		change = change or Recount.inRaid
		Recount.inRaid = false
	end

	if WOW_RETAIL and IsInRaid() and IsInScenarioGroup() then
		change = change or not Recount.inScenario
		Recount.inScenario = true
	else
		change = change or Recount.inScenario
		Recount.inScenario = false
	end

	if change then
		Recount:UpdateZoneGroupFilter()
	end

	if Recount.GroupCheck then
		Recount:GroupCheck()
	end -- Elsia: Reevaluate group flagging on group changes.
end

function Recount:GROUP_ROSTER_UPDATE()
	Recount:PartyMembersChanged()
end

function Recount:InitPartyBasedDeletion()
	Recount.inGroup = false
	Recount.inRaid = false

	if (not IsInRaid() and GetNumPartyMembers() > 0) or (WOW_RETAIL and IsInScenarioGroup()) then
		Recount.inGroup = true
	end
	if IsInRaid() and GetNumRaidMembers() > 0 and not (WOW_RETAIL and IsInScenarioGroup()) then
		Recount.inRaid = true
	end

	--[[if TOC >= 50000 then
		Recount:RegisterEvent("GROUP_ROSTER_UPDATE", "PartyMembersChanged")
	else
		Recount:RegisterEvent("PARTY_MEMBERS_CHANGED","PartyMembersChanged")

		Recount:RegisterEvent("RAID_ROSTER_UPDATE","PartyMembersChanged")
	end]]
	Recount.events:RegisterEvent("GROUP_ROSTER_UPDATE")
	Recount:UpdateZoneGroupFilter()
end

function Recount:ReleasePartyBasedDeletion()
	if Recount.db.profile.DeleteJoinGroup == false and Recount.db.profile.DeleteJoinRaid == false then
		Recount.events:UnregisterEvent("GROUP_ROSTER_UPDATE")
		--Recount:UnregisterEvent("PARTY_MEMBERS_CHANGED")
		--Recount:UnregisterEvent("RAID_ROSTER_UPDATE")
	end
end
