local PvPTogether = _G.PvPTogether
if not PvPTogether then
	return
end
local LibChev = PvPTogether.LibChev

-- All bookkeeping belongs to the addon. Never call Blizzard's setup/reset mixins:
-- those write shared option tables and frame fields even outside combat.
PvPTogether.nameplateStateByFrame = {}
PvPTogether.nameplateFrameByUnitToken = {}
PvPTogether.nameplateBorderTintByUnitFrame = LibChev.WeakKeys()
PvPTogether.nameplateStateByUnitFrame = LibChev.WeakKeys()

local function Field(object, key)
	local value = PvPTogether:SafeGetField(object, key)
	return value
end

local function Method(object, key)
	local value = Field(object, key)
	return type(value) == "function" and value or nil
end

local function Call(object, key, ...)
	local method = Method(object, key)
	if not method then
		return false
	end
	return pcall(method, object, ...)
end

local function BooleanCall(fn, ...)
	if type(fn) ~= "function" then
		return nil
	end
	local ok, value = pcall(fn, ...)
	if not ok then
		return nil
	end
	return PvPTogether:SafeToBoolean(value)
end

local function SafetyAPI(namespace, name)
	if not PvPTogether:CanAccessValue(namespace) then
		return nil, false
	end
	if namespace == nil then
		return nil, true
	end
	local api, readable = PvPTogether:SafeGetField(namespace, name)
	if not readable or (api ~= nil and type(api) ~= "function") then
		return nil, false
	end
	return api, true
end

local function IsToken(value)
	return PvPTogether:CanAccessValue(value) and type(value) == "string" and value ~= ""
end

function PvPTogether:CanAccessNameplateFrame(frame)
	if not self:CanAccessValue(frame) or (type(frame) ~= "table" and type(frame) ~= "userdata") then
		return false
	end
	local forbidden = Method(frame, "IsForbidden")
	return forbidden ~= nil and BooleanCall(forbidden, frame) == false
end

function PvPTogether:IsNameplateAugmentationBlockedInCurrentContext()
	if self:IsInCombatLockdown() then
		return true
	end
	local getState, readable = SafetyAPI(C_RestrictedActions, "GetAddOnRestrictionState")
	if not readable then
		return true
	end
	if type(getState) ~= "function" then
		return false
	end
	local restrictionTypes = Field(Enum, "AddOnRestrictionType")
	if not self:CanAccessTable(restrictionTypes) then
		return true
	end
	local inactive = Field(Field(Enum, "AddOnRestrictionState"), "Inactive") or 0
	for _, name in ipairs({ "Combat", "Encounter", "ChallengeMode", "PvPMatch", "Map" }) do
		local restrictionType, typeReadable = self:SafeGetField(restrictionTypes, name)
		if not typeReadable then
			return true
		end
		if restrictionType ~= nil then
			local ok, value = pcall(getState, restrictionType)
			local state = ok and self:SafeToNumber(value) or nil
			if state == nil or state ~= inactive then
				return true
			end
		end
	end
	return false
end

function PvPTogether:CanMutateNameplateFrame(frame)
	if not self:CanAccessNameplateFrame(frame) then
		return false, "frame-access"
	end
	local protected, readable = self:SafeGetField(frame, "IsProtected")
	if not readable or (protected ~= nil and type(protected) ~= "function") then
		return false, "protection-query"
	end
	local protection = protected and BooleanCall(protected, frame)
	if protected and protection == nil then
		return false, "protection-result"
	end
	local restricted = self:IsNameplateAugmentationBlockedInCurrentContext()
	if restricted and protection ~= false then
		return false, "protected-context"
	end
	local allow, permissionReadable = SafetyAPI(C_RestrictedActions, "CheckAllowProtectedFunctions")
	if not permissionReadable then
		return false, "permission-query"
	end
	if type(allow) == "function" and BooleanCall(allow, frame, true) ~= true then
		return false, "permission-denied"
	end
	if restricted and type(allow) ~= "function" then
		return false, "permission-unavailable"
	end
	return true
end

function PvPTogether:GetNameplateCapabilities()
	local plates = type(Field(C_NamePlate, "GetNamePlates")) == "function"
		and type(Field(C_NamePlate, "GetNamePlateForUnit")) == "function"
	return {
		borderTint = plates,
		reason = plates and "Native layout with custom borders" or "Nameplate APIs unavailable",
	}
end

-- Unknown classification is never treated as an enemy. Resolve anew on every pass;
-- no GUID or unit-kind cache can leak across recycled tokens or pooled unit frames.
function PvPTogether:ResolveNameplateUnitKind(unitToken)
	if not IsToken(unitToken) then
		return nil
	end
	local player = BooleanCall(UnitIsPlayer, unitToken)
	if player == nil then
		return nil
	end
	if not player then
		return "npc"
	end
	local friend = BooleanCall(UnitIsFriend, "player", unitToken)
	if friend == nil then
		return nil
	end
	if not friend then
		return "enemyPlayer"
	end
	local own = BooleanCall(UnitIsUnit, unitToken, "player")
	if own == nil then
		return nil
	end
	if not own then
		local inParty = BooleanCall(UnitInParty, unitToken, LE_PARTY_CATEGORY_HOME or 1)
		if inParty == nil then
			return nil
		end
		if inParty then
			return "partyMember"
		end
	end
	return "friendlyPlayer"
end

local function LiveUnit(frame)
	if not PvPTogether:CanAccessNameplateFrame(frame) then
		return nil
	end
	local ok, token = Call(frame, "GetUnit")
	if not ok or not IsToken(token) then
		return nil
	end
	local getPlate = Field(C_NamePlate, "GetNamePlateForUnit")
	if type(getPlate) ~= "function" then
		return nil
	end
	local found, current = pcall(getPlate, token, false)
	if not found or not PvPTogether:CanAccessValue(current) or current ~= frame then
		return nil
	end
	return token
end

local function IsWithinAnchorRoot(object, root)
	if not PvPTogether:CanAccessNameplateFrame(root) then
		return false
	end
	-- Only walk a bounded, access-checked parent chain. A restricted plate may
	-- anchor its own children together, never into another plate or UIParent.
	for _ = 1, 16 do
		if not PvPTogether:CanAccessNameplateFrame(object) then
			return false
		end
		if object == root then
			return true
		end
		local ok, parent = Call(object, "GetParent")
		if not ok or not PvPTogether:CanAccessValue(parent) then
			return false
		end
		object = parent
	end
	return false
end

local function CanAnchor(object, root)
	if not PvPTogether:CanAccessNameplateFrame(object) then
		return false
	end
	for _, name in ipairs({ "IsAnchoringRestricted", "IsAnchoringSecret" }) do
		local predicate, readable = PvPTogether:SafeGetField(object, name)
		if not readable then
			return false
		end
		if predicate ~= nil then
			if type(predicate) ~= "function" then
				return false
			end
			local restricted = BooleanCall(predicate, object)
			if restricted == nil then
				return false
			end
			if restricted and (name == "IsAnchoringSecret" or not IsWithinAnchorRoot(object, root)) then
				return false
			end
		end
	end
	return true
end
local function CanAnchorBorder(texture, anchor, root)
	return PvPTogether:CanMutateNameplateFrame(texture)
		and Method(texture, "ClearAllPoints") ~= nil
		and Method(texture, "SetPoint") ~= nil
		and CanAnchor(texture, root)
		and CanAnchor(anchor, root)
		and IsWithinAnchorRoot(texture, root)
		and IsWithinAnchorRoot(anchor, root)
end

local function Child(frame, key)
	if not PvPTogether:CanAccessNameplateFrame(frame) then
		return nil
	end
	local child = Field(frame, key)
	if PvPTogether:CanAccessNameplateFrame(child) then
		return child
	end
	return nil
end

function PvPTogether:HideBorderTintForUnitFrame(unitFrame)
	local overlay = self.nameplateBorderTintByUnitFrame[unitFrame]
	if not overlay then
		return true
	end
	if overlay.visible == false then
		return true
	end
	-- This region belongs to us. Harmless Hide on an accessible, unprotected
	-- texture must remain possible during combat, or the unit-frame pool can
	-- display the previous unit's tint on its next occupant.
	if not self:CanAccessNameplateFrame(overlay.Texture) then
		return false
	end
	local protected, readable = self:SafeGetField(overlay.Texture, "IsProtected")
	if not readable or (protected ~= nil and type(protected) ~= "function") then
		return false
	end
	local protection = protected and BooleanCall(protected, overlay.Texture)
	if protected and protection == nil then
		return false
	end
	local allow, permissionReadable = SafetyAPI(C_RestrictedActions, "CheckAllowProtectedFunctions")
	if not permissionReadable then
		return false
	end
	if type(allow) == "function" then
		if BooleanCall(allow, overlay.Texture, true) ~= true then
			return false
		end
	elseif self:IsNameplateAugmentationBlockedInCurrentContext() and protection ~= false then
		return false
	end
	local hidden = Call(overlay.Texture, "Hide")
	if hidden then
		overlay.visible = false
	end
	return hidden
end

function PvPTogether:ApplyBorderTintForUnitFrame(unitFrame, unitKind)
	if not self.isEnabled or not unitKind or not self:IsBorderColorOverrideEnabledForUnitKind(unitKind) then
		return self:HideBorderTintForUnitFrame(unitFrame)
	end
	local healthBar = Child(Child(unitFrame, "HealthBarsContainer"), "healthBar")
	if not self:CanMutateNameplateFrame(healthBar) then
		return false
	end
	local ok, shown = Call(healthBar, "IsShown")
	if not ok or self:SafeToBoolean(shown) ~= true then
		return self:HideBorderTintForUnitFrame(unitFrame)
	end
	local overlay = self.nameplateBorderTintByUnitFrame[unitFrame]
	if overlay and overlay.HealthBar ~= healthBar then
		if not self:HideBorderTintForUnitFrame(unitFrame) then
			return false
		end
		overlay = nil -- A texture never migrates to a replacement Blizzard health bar.
	end
	if not overlay then
		local created, texture = Call(healthBar, "CreateTexture", nil, "OVERLAY", nil, 2)
		if not created or not self:CanMutateNameplateFrame(texture) then
			return false
		end
		overlay = { Texture = texture, HealthBar = healthBar }
		self.nameplateBorderTintByUnitFrame[unitFrame] = overlay
		if not Call(texture, "Hide") then
			return false
		end
		overlay.visible = false
	end
	if not self:CanMutateNameplateFrame(overlay.Texture) then
		return false
	end
	if not overlay.ready then
		if not Call(overlay.Texture, "SetAtlas", "UI-HUD-Nameplates-Selected", true) then
			return false
		end
		overlay.ready = true
	end
	local anchor = Child(healthBar, "bgTexture") or healthBar
	if not CanAnchorBorder(overlay.Texture, anchor, healthBar) then
		return false
	end
	local color = self:GetConfiguredBorderColorForUnitKind(unitKind)
	-- Parent alpha already applies to the texture. Reading/multiplying it would
	-- both double-fade the tint and branch on a potentially secret alpha.
	local anchored = Call(overlay.Texture, "ClearAllPoints")
		and Call(overlay.Texture, "SetPoint", "TOPLEFT", anchor, "TOPLEFT", -1, 1)
		and Call(overlay.Texture, "SetPoint", "BOTTOMRIGHT", anchor, "BOTTOMRIGHT", -3, 3)
	if not anchored or not Call(overlay.Texture, "SetVertexColor", color.r, color.g, color.b, 1) then
		return false
	end
	local displayed = Call(overlay.Texture, "Show")
	if displayed then
		overlay.visible = true
	end
	return displayed
end

function PvPTogether:HideAllBorderTintOverrides()
	local complete = true
	for unitFrame in pairs(self.nameplateBorderTintByUnitFrame) do
		if not self:HideBorderTintForUnitFrame(unitFrame) then
			complete = false
		end
	end
	return complete
end

local function ReleaseState(addon, state)
	if addon.nameplateStateByUnitFrame[state.unitFrame] == state then
		addon.nameplateStateByUnitFrame[state.unitFrame] = nil
	end
	if addon.nameplateStateByFrame[state.frame] == state then
		addon.nameplateStateByFrame[state.frame] = nil
		addon.trackedNamePlateFrames[state.frame] = nil
	end
	if addon.nameplateFrameByUnitToken[state.token] == state.frame then
		addon.nameplateFrameByUnitToken[state.token] = nil
	end
end

function PvPTogether:RefreshNameplateFrame(frame)
	if not self.isEnabled or not self:CanAccessValue(frame) or frame == nil then
		return false
	end
	local state = self.nameplateStateByFrame[frame]
	local token = LiveUnit(frame)
	local unitFrame = Child(frame, "UnitFrame")
	if not token or not unitFrame then
		if state and not self:HideBorderTintForUnitFrame(state.unitFrame) then
			self.pendingBorderCleanup = true
		end
		return false
	end
	local previousOwner = self.nameplateStateByUnitFrame[unitFrame]
	if previousOwner and previousOwner ~= state then
		if not self:HideBorderTintForUnitFrame(unitFrame) then
			self.pendingBorderCleanup = true
			return false
		end
		ReleaseState(self, previousOwner)
	end
	if state and (state.token ~= token or state.unitFrame ~= unitFrame) then
		if not self:HideBorderTintForUnitFrame(state.unitFrame) then
			self.pendingBorderCleanup = true
			return false
		end
		ReleaseState(self, state)
		state = nil
	end
	if not state then
		state = { token = token, unitFrame = unitFrame, frame = frame }
		self.nameplateStateByFrame[frame] = state
		self.nameplateStateByUnitFrame[unitFrame] = state
		self.nameplateFrameByUnitToken[token] = frame
		self.trackedNamePlateFrames[frame] = true
	end
	local unitKind = self:ResolveNameplateUnitKind(token)
	if not unitKind then
		self:RecordDiagnostic("classification-unavailable")
		self.pendingBorderRefresh = true
		if not self:HideBorderTintForUnitFrame(unitFrame) then
			self.pendingBorderCleanup = true
		end
		return false
	end
	local applied = self:ApplyBorderTintForUnitFrame(unitFrame, unitKind)
	if not applied then
		-- An old tint must not outlive an inaccessible or changed category.
		if not self:HideBorderTintForUnitFrame(unitFrame) then
			self.pendingBorderCleanup = true
		end
		self.pendingBorderRefresh = true
		self:RecordDiagnostic("border-unavailable")
	end
	return applied
end

function PvPTogether:RefreshNameplateForUnit(token)
	if not IsToken(token) then
		return false
	end
	local getPlate = Field(C_NamePlate, "GetNamePlateForUnit")
	if type(getPlate) ~= "function" then
		return false
	end
	local ok, frame = pcall(getPlate, token, false)
	return ok and self:CanAccessNameplateFrame(frame) and self:RefreshNameplateFrame(frame) or false
end

function PvPTogether:HandleNameplateRemoved(token)
	if not IsToken(token) then
		return
	end
	local frame = self.nameplateFrameByUnitToken[token]
	self.nameplateFrameByUnitToken[token] = nil
	local state = frame and self.nameplateStateByFrame[frame]
	if not state or state.token ~= token then
		return
	end
	if self:HideBorderTintForUnitFrame(state.unitFrame) then
		ReleaseState(self, state)
	else
		self.pendingBorderCleanup = true
	end
end

function PvPTogether:ClearNameplateBorders()
	local complete = true
	for _, state in pairs(self.nameplateStateByFrame) do
		if self:HideBorderTintForUnitFrame(state.unitFrame) then
			ReleaseState(self, state)
		else
			complete = false
		end
	end
	if not self:HideAllBorderTintOverrides() then
		complete = false
	end
	self.pendingBorderCleanup = not complete
	return complete
end

function PvPTogether:RefreshNameplates()
	if not self.isEnabled then
		return
	end
	if self.pendingBorderCleanup then
		self:ClearNameplateBorders()
	end
	self.pendingBorderRefresh = false
	local getPlates = Field(C_NamePlate, "GetNamePlates")
	if type(getPlates) ~= "function" then
		return
	end
	local ok, frames = pcall(getPlates, false)
	if not ok or not self:CanAccessTable(frames) then
		return
	end
	for _, frame in pairs(frames) do
		self:RefreshNameplateFrame(frame)
	end
end

function PvPTogether:ScheduleNameplateRefresh(delay)
	if not self.isEnabled or self.nameplateRefreshScheduled then
		return
	end
	local after = Field(C_Timer, "After")
	if type(after) ~= "function" then
		self:RefreshNameplates()
		return
	end
	self.nameplateRefreshScheduled = true
	after(
		math.max(0, self:SafeToNumber(delay) or 0),
		LibChev.Fence(self, { "nameplateRefreshGeneration" }, function()
			PvPTogether.nameplateRefreshScheduled = false
			PvPTogether:RefreshNameplates()
		end)
	)
end

function PvPTogether:HandleNameplateContextChange()
	if self.RefreshOptionsWindow then
		self:RefreshOptionsWindow()
	end
	if self.pendingBorderCleanup then
		self:ClearNameplateBorders()
	end
	if self.isEnabled then
		self:ScheduleNameplateRefresh(0)
	end
end

function PvPTogether:EnsureNameplateEventFrame()
	if self.nameplateEventFrame then
		return self.nameplateEventFrame
	end
	local frame = CreateFrame("Frame")
	frame:SetScript("OnEvent", function(_, event, ...)
		if event == "NAME_PLATE_UNIT_REMOVED" then
			PvPTogether:HandleNameplateRemoved(...)
		elseif event == "NAME_PLATE_UNIT_ADDED" then
			if PvPTogether.isEnabled then
				PvPTogether:RefreshNameplateForUnit(...)
				PvPTogether:ScheduleNameplateRefresh(0)
			end
		elseif event == "CVAR_UPDATE" then
			local name = ...
			if IsToken(name) and name:lower():find("nameplate", 1, true) then
				PvPTogether:ScheduleNameplateRefresh(0)
			end
		elseif event == "ADDON_LOADED" then
			local name = ...
			if IsToken(name) and name == "Blizzard_NamePlates" then
				PvPTogether:HandleNameplateContextChange()
			end
		else
			PvPTogether:HandleNameplateContextChange()
		end
	end)
	-- Retain cleanup events while disabled; never register native layout hooks.
	for _, event in ipairs({
		"ADDON_LOADED",
		"NAME_PLATE_UNIT_ADDED",
		"NAME_PLATE_UNIT_REMOVED",
		"PLAYER_ENTERING_WORLD",
		"ZONE_CHANGED_NEW_AREA",
		"CVAR_UPDATE",
		"GROUP_ROSTER_UPDATE",
		"UNIT_FACTION",
		"PLAYER_REGEN_ENABLED",
		"PLAYER_REGEN_DISABLED",
		"ENCOUNTER_END",
		"CHALLENGE_MODE_COMPLETED",
		"CHALLENGE_MODE_RESET",
	}) do
		pcall(frame.RegisterEvent, frame, event)
	end
	if type(Field(C_RestrictedActions, "GetAddOnRestrictionState")) == "function" then
		pcall(frame.RegisterEvent, frame, "ADDON_RESTRICTION_STATE_CHANGED")
	end
	self.nameplateEventFrame = frame
	return frame
end

local function InvalidateDeferred(addon)
	LibChev.Advance(addon, "nameplateRefreshGeneration")
	addon.nameplateRefreshScheduled = false
	addon.pendingBorderRefresh = false
end

function PvPTogether:EnableNameplateModule()
	InvalidateDeferred(self)
	self:EnsureNameplateEventFrame()
	self:HandleNameplateContextChange()
end

function PvPTogether:DisableNameplateModule()
	InvalidateDeferred(self)
	self:ClearNameplateBorders()
end
