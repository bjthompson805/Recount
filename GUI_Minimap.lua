local Recount = _G.Recount

local LibDBIcon = LibStub("LibDBIcon-1.0")
local LibDataBroker = LibStub("LibDataBroker-1.1")

local UIParent = UIParent

local RecountMinimapDB

-- Mirrors LibDBIcon-1.0's own `getAnchors`
-- (libs/LibDBIcon-1.0/LibDBIcon-1.0.lua:61-67), which is a file-local and so
-- cannot be called from here. Copied deliberately rather than re-invented: the
-- line this replaces was a hand-rolled version with three defects.
--
--   1. NO NIL GUARD. GetCenter() returns nil for a frame with no rectangle, and
--      the old line compared `nil > number` and raised inside a tooltip handler.
--   2. IT READ THE WRONG FRAME. OnEnter here is a LibDataBroker data-object
--      callback, so ANY broker display -- Titan, Bazooka, ChocolateBar, an ElvUI
--      datatext -- invokes it with ITS OWN frame as `self`. The old line ignored
--      `self` and asked LibDBIcon where the MINIMAP BUTTON was, so the tooltip
--      was owned by one frame and cornered by the position of another.
--   3. IT ONLY CHOSE LEFT vs RIGHT, on halves, and always TOP. A launcher on a
--      bottom-of-screen panel got a tooltip anchored by its top edge and drawn
--      off the bottom of the screen. The library picks TOP vs BOTTOM too, and
--      uses thirds horizontally so a centred frame gets no horizontal bias.
--
-- The third return value is the RELATIVE point, which is what puts the tooltip
-- beside the frame rather than on top of it; the old two-argument call anchored
-- the tooltip's own corner to the same corner of the button.
local function tooltipAnchors(frame)
	local x, y = frame:GetCenter()
	-- The library returns bare "CENTER" here; the frame is passed as well so the
	-- tooltip stays attached to the thing being hovered, which it owns anyway.
	if not x or not y then
		return "CENTER", frame, "CENTER"
	end
	local hhalf = (x > UIParent:GetWidth() * 2 / 3) and "RIGHT"
		or (x < UIParent:GetWidth() / 3) and "LEFT" or ""
	local vhalf = (y > UIParent:GetHeight() / 2) and "TOP" or "BOTTOM"
	return vhalf .. hhalf, frame, (vhalf == "TOP" and "BOTTOM" or "TOP") .. hhalf
end

local iconObject = LibDataBroker:NewDataObject("Recount", {
	type = "launcher",
	text = "Recount",
	icon = "Interface\\AddOns\\Recount\\textures\\Recount_MMB_Icon",
	OnEnter = function(self)
		GameTooltip:SetOwner(self, "ANCHOR_NONE")
		GameTooltip:SetPoint(tooltipAnchors(self))
		GameTooltip:AddLine("Recount", 1, 1, 1)
		GameTooltip:AddDoubleLine("Left-Click", "Toggle window", 1, 1, 1, 0.8, 0.8, 0.8)
		GameTooltip:AddDoubleLine("Shift+Left-Click", "Toggle config", 1, 1, 1, 0.8, 0.8, 0.8)
		GameTooltip:AddDoubleLine("Right-Click", "Toggle addon settings", 1, 1, 1, 0.8, 0.8, 0.8)
		GameTooltip:Show()
	end,
	OnLeave = function()
		GameTooltip:Hide()
	end,
	OnClick = function(_, button)
		if button == "RightButton" then
			if Settings and Settings.OpenToCategory then
				if SettingsPanel and SettingsPanel:IsShown() then
					SettingsPanel:Hide()
				else
					Settings.OpenToCategory(Recount.BlizOptionsCategory or "Recount")
				end
			elseif _G.InterfaceOptionsFrame_OpenToCategory then
				local category = Recount.BlizOptionsCategory or "Recount"
				if InterfaceOptionsFrame:IsShown() then
					InterfaceOptionsFrame:Hide()
				else
					_G.InterfaceOptionsFrame_OpenToCategory(category)
					_G.InterfaceOptionsFrame_OpenToCategory(category)
				end
			end
		elseif IsShiftKeyDown() then
			if Recount.ConfigWindow and Recount.ConfigWindow:IsShown() then
				Recount.ConfigWindow:Hide()
			else
				Recount:ShowConfig()
			end
		else
			if Recount.MainWindow:IsShown() then
				Recount.MainWindow:Hide()
			else
				Recount.MainWindow:Show()
			end
		end
	end,
})

function Recount:InitMinimapButton()
	RecountMinimapDB = Recount.db.profile.minimapButton or { hide = false }
	Recount.db.profile.minimapButton = RecountMinimapDB
	LibDBIcon:Register("Recount", iconObject, RecountMinimapDB)
end

function Recount:ToggleMinimapButton(show)
	if show then
		RecountMinimapDB.hide = false
		LibDBIcon:Show("Recount")
	else
		RecountMinimapDB.hide = true
		LibDBIcon:Hide("Recount")
	end
end
