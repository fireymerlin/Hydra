--[[--------------------------------------------------------------------
	Hydra
	Multibox leveling helper.
	Copyright (c) 2010-2015 Phanx <addons@phanx.net>. All rights reserved.
	http://www.wowinterface.com/downloads/info17572-Hydra.html
	http://www.curse.com/addons/wow/hydra
	https://github.com/Phanx/Hydra
------------------------------------------------------------------------
	Hydra Assist
	* /assistme commands all party members to set you as their assist target.
----------------------------------------------------------------------]]

--[[
	1. PartyA sends AssistMe command.
	2. PartyB registers PartyA as assist target.
	3a. If out of combat, update assist macro.
	3b. If in combat, send CombatErr message, register PLAYER_REGEN_ENABLED.
	4. On leaving combat, update assist macro.
--]]

local _, Hydra = ...
local L = Hydra.L
local STATE_SOLO, STATE_INSECURE, STATE_SECURE, STATE_LEADER = Hydra.STATE_SOLO, Hydra.STATE_INSECURE, Hydra.STATE_SECURE, Hydra.STATE_LEADER
local PLAYER_FULLNAME = Hydra.PLAYER_FULLNAME

local Assist = Hydra:NewModule("Assist")
Assist.defaults = { respond = true, verbose = true }

local COMMAND_REQUEST, ALERT_SET, ALERT_SET_F, ALERT_UNSET, ALERT_COMBAT, ALERT_NOTRUST, ALERT_ERROR = "REQUEST", "SET", "SET %s", "UNSET", "COMBAT", "NOTRUST", "ERROR"
local MACRO_NAME, MACRO_ICON, MACRO_BODY = L.AssistMacro, "Spell_Priest_VowofUnity", "/click HydraAssistButton"
local assisters, assisting, pending = {}

local statusText = {
	[ALERT_COMBAT]  = L.AssistFailedCombat,
	[ALERT_ERROR]   = L.AssistFailed,
	[ALERT_NOTRUST] = L.AssistFailedTrust,
	[ALERT_SET]     = L.AssistSet,
	[ALERT_UNSET]   = L.AssistUnset,
}

------------------------------------------------------------------------

function Assist:ShouldEnable()
	return Hydra.state > STATE_SOLO
end

function Assist:OnDisable(silent)
	assisters, assisting, pending = wipe(assisters), nil, nil
end

------------------------------------------------------------------------

local button = CreateFrame("Button", "HydraAssistButton", nil, "SecureActionButtonTemplate")
button:RegisterForClicks("AnyUp")
button:SetAttribute("type", "macro")

function Assist:GetMacro()
	local index = GetMacroIndexByName(MACRO_NAME)
	if InCombatLockdown() then
		return index
	elseif index == 0 then
		-- Macro doesn't exist yet. Create it.
		self:Debug("GetMacro: macro doesn't exist yet, creating...")
		return CreateMacro(MACRO_NAME, MACRO_ICON, MACRO_BODY, 0)
	else
		-- Macro already exists. Update it.
		self:Debug("GetMacro: editing...")
		return EditMacro(index, MACRO_NAME, MACRO_ICON, MACRO_BODY)
	end
end

function Assist:SetAssist(name)
	self:Debug("SetAssist", name)

	if InCombatLockdown() then
		-- Player in combat. Queue change for end of combat, and inform the requester.
		self:Debug("in combat")
		self:RegisterEvent("PLAYER_REGEN_ENABLED")
		pending = name
		if name then
			self:SendAddonMessage(ALERT_COMBAT, name)
		end

	elseif not name then
		-- Clear the assist target.
		self:Debug("clear")
		button:SetAttribute("macrotext", nil)
		assisting = nil

	elseif not Hydra:IsTrusted(name) then
		-- Requester not trusted. Inform them.
		self:Debug("not trusted")
		self:SendAddonMessage(ALERT_NOTRUST, name)

	else
		-- Set the requester to be assisted.
		self:Debug("success")
		button:SetAttribute("macrotext", SLASH_ASSIST1.." "..name)
		assisting = name
		self:SendAddonMessage(format(ALERT_SET_F, name))
	end

	-- Clear pending if there was one.
	pending = nil
end

------------------------------------------------------------------------

function Assist:PLAYER_REGEN_ENABLED()
	self:Debug("combat ended, trying again...")
	self:UnregisterEvent("PLAYER_REGEN_ENABLED")
	self:SetAssist(pending)
end

function Assist:OnAddonMessage(message, channel, sender)
	self:Debug("AddonMessage", channel, sender, message)
	local message, detail = strsplit(" ", message, 2)

	if message == COMMAND_REQUEST then
		-- sender wants to be the assist target
		return self:SetAssist(sender)
	end

	if message == ALERT_SET then
		if detail == PLAYER_FULLNAME then
			-- sender is now assisting the player
			assisters[sender] = true
		elseif assisters[sender] then
			-- sender was assisting the player, but now someone else
			assisters[sender] = nil
			message = ALERT_UNSET
		else
			-- irrelevant
			return
		end
	end

	if self.db.verbose then
		local report = statusText[message]
		if report then
			self:Print(report, sender, detail)
		end
	end
end

------------------------------------------------------------------------

SLASH_HYDRA_ASSIST1 = "/assistme"
SLASH_HYDRA_ASSIST2 = L.SlashAssistMe

function SlashCmdList.HYDRA_ASSIST(command)
	if not Assist.enabled then return end
	command = command and strlower(strtrim(command))

	if command == "who" then
		if not next(assisting) then
			return self:Print(L.NobodyAssisting)
		end
		for name in pairs(assisting) do
			self:Print(statusText[ALERT_SET], name)
		end
	else
		self:SendAddonMessage(COMMAND_REQUEST)
	end
end

------------------------------------------------------------------------

_G["BINDING_NAME_CLICK HydraAssistButton"] = L.AssistMacro
BINDING_NAME_HYDRA_REQUEST_ASSIST = L.RequestAssist

------------------------------------------------------------------------

Assist.displayName = L.Assist
function Assist:SetupOptions(panel)
	local title, notes = panel:CreateHeader(L.Assist, L.Assist_Info)

	local respond = panel:CreateCheckbox(L.AssistRespond, L.AssistRespond_Info)
	respond:SetPoint("TOPLEFT", notes, "BOTTOMLEFT", 0, -12)
	function respond:OnValueChanged(value)
		Assist.db.respond = value
		Assist:Refresh()
	end

	local verbose = panel:CreateCheckbox(L.Verbose, L.Verbose_Info)
	verbose:SetPoint("TOPLEFT", respond, "BOTTOMLEFT", 0, -8)
	function verbose:OnValueChanged(value)
		Assist.db.verbose = value
	end

	local usemacro = panel:CreateKeyBinding(L.AssistMacro, L.AssistMacro_Info, "CLICK HydraAssistButton")
	usemacro:SetPoint("TOPLEFT", notes, "BOTTOM", -8, -8)
	usemacro:SetPoint("TOPRIGHT", notes, "BOTTOMRIGHT", 0, -8)

	local request = panel:CreateKeyBinding(L.RequestAssist, L.RequestAssist_Info, "HYDRA_REQUEST_ASSIST")
	request:SetPoint("TOPLEFT", usemacro, "BOTTOMLEFT", 0, -8)
	request:SetPoint("TOPRIGHT", usemacro, "BOTTOMRIGHT", 0, -8)

	local help = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	help:SetPoint("BOTTOMLEFT", 16, 16)
	help:SetPoint("BOTTOMRIGHT", -16, 16)
	help:SetHeight(112)
	help:SetJustifyH("LEFT")
	help:SetJustifyV("BOTTOM")
	help:SetText(L.AssistHelpText)

	local getmacro = panel:CreateButton(L.AssistGetMacro, L.AssistGetMacro_Info)
	getmacro:SetPoint("BOTTOMRIGHT", help, "TOPRIGHT", 0, 24)
	function getmacro:OnClicked(button)
		PickupMacro(Assist:GetMacro())
	end

	panel.refresh = function()
		respond:SetChecked(Assist.db.respond)
		verbose:SetChecked(Assist.db.verbose)
		usemacro:RefreshValue()
		request:RefreshValue()
	end
end