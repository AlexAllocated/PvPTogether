local addonName, addonTable = ...
local LibChev = assert(addonTable and addonTable.LibChev, "libchev must load before Core.lua")

local PvPTogether = _G.PvPTogether or addonTable or {}
_G.PvPTogether = PvPTogether
PvPTogether.LibChev = LibChev

local raw_issecretvalue = type(issecretvalue) == "function" and issecretvalue or nil
local raw_canaccessvalue = type(canaccessvalue) == "function" and canaccessvalue or nil
local raw_canaccesstable = type(canaccesstable) == "function" and canaccesstable or nil

PvPTogether.addonName = addonName or "PvPTogether"

local STYLE_MODERN = Enum and Enum.NamePlateStyle and Enum.NamePlateStyle.Modern or 0
local STYLE_THIN = Enum and Enum.NamePlateStyle and Enum.NamePlateStyle.Thin or 1
local STYLE_BLOCK = Enum and Enum.NamePlateStyle and Enum.NamePlateStyle.Block or 2
local STYLE_HEALTH_FOCUS = Enum and Enum.NamePlateStyle and Enum.NamePlateStyle.HealthFocus or 3
local STYLE_CAST_FOCUS = Enum and Enum.NamePlateStyle and Enum.NamePlateStyle.CastFocus or 4
local STYLE_LEGACY = Enum and Enum.NamePlateStyle and Enum.NamePlateStyle.Legacy or 5
local STYLE_CLASSIC = Enum and Enum.NamePlateStyle and Enum.NamePlateStyle.Classic

-- Rendering capability is separate from the choices offered by this client.
local supportedOverrideStyles = {
	[STYLE_MODERN] = true,
	[STYLE_THIN] = true,
	[STYLE_BLOCK] = true,
	[STYLE_HEALTH_FOCUS] = true,
	[STYLE_CAST_FOCUS] = true,
	[STYLE_LEGACY] = true,
}
PvPTogether.nameplateStyleOrder = {}

PvPTogether.nameplateStyleLabels = {
	[STYLE_MODERN] = UNIT_NAMEPLATES_STYLE_MODERN or "Modern",
	[STYLE_THIN] = UNIT_NAMEPLATES_STYLE_THIN or "Thin",
	[STYLE_BLOCK] = UNIT_NAMEPLATES_STYLE_BLOCK or "Block",
	[STYLE_HEALTH_FOCUS] = UNIT_NAMEPLATES_STYLE_HEALTH_FOCUS or "Health Focus",
	[STYLE_CAST_FOCUS] = UNIT_NAMEPLATES_STYLE_CAST_FOCUS or "Cast Focus",
	[STYLE_LEGACY] = UNIT_NAMEPLATES_STYLE_LEGACY or "Legacy",
}
if STYLE_CLASSIC then
	PvPTogether.nameplateStyleLabels[STYLE_CLASSIC] = UNIT_NAMEPLATES_STYLE_CLASSIC or "Classic"
end

PvPTogether.DEFAULTS = {
	enabled = true,
	partyMemberBorderEnabled = false,
	partyMemberBorderColor = {
		r = 0.0,
		g = 1.0,
		b = 0.0,
	},
	friendlyPlayerBorderEnabled = false,
	friendlyPlayerBorderColor = {
		r = 0.0,
		g = 1.0,
		b = 1.0,
	},
	enemyPlayerBorderEnabled = false,
	enemyPlayerBorderColor = {
		r = 1.0,
		g = 0.0,
		b = 0.0,
	},
	styleSeeded = false,
	partyMemberStyleSeeded = false,
}

PvPTogether.isInitialized = PvPTogether.isInitialized or false
PvPTogether.hasLoggedIn = PvPTogether.hasLoggedIn or false
PvPTogether.isEnabled = PvPTogether.isEnabled or false
PvPTogether.db = PvPTogether.db or nil
PvPTogether.trackedNamePlateFrames = PvPTogether.trackedNamePlateFrames or LibChev.WeakKeys()

local function IsNonEmptyString(value)
	return type(value) == "string" and PvPTogether:CanAccessValue(value) and value ~= ""
end

local function ClampColorComponent(value, fallback)
	local numericValue = PvPTogether:SafeToNumber(value)
	if numericValue == nil then
		return fallback
	end
	if numericValue < 0 then
		return 0
	end
	if numericValue > 1 then
		return 1
	end
	return numericValue
end

local function ColorsNearlyEqual(left, right)
	local leftNumber = PvPTogether:SafeToNumber(left)
	local rightNumber = PvPTogether:SafeToNumber(right)
	return leftNumber ~= nil and rightNumber ~= nil and math.abs(leftNumber - rightNumber) < 0.001
end

local function ColorTablesEqual(left, right)
	if not PvPTogether:CanAccessTable(left) or not PvPTogether:CanAccessTable(right) then
		return false
	end
	return ColorsNearlyEqual(PvPTogether:SafeGetField(left, "r"), PvPTogether:SafeGetField(right, "r"))
		and ColorsNearlyEqual(PvPTogether:SafeGetField(left, "g"), PvPTogether:SafeGetField(right, "g"))
		and ColorsNearlyEqual(PvPTogether:SafeGetField(left, "b"), PvPTogether:SafeGetField(right, "b"))
end

function PvPTogether:IsSecretValue(value)
	if not raw_issecretvalue then
		return false
	end
	local ok, isSecret = pcall(raw_issecretvalue, value)
	return not ok or isSecret ~= false
end

function PvPTogether:CanAccessValue(value)
	if self:IsSecretValue(value) then
		return false
	end
	if raw_canaccessvalue then
		local ok, accessible = pcall(raw_canaccessvalue, value)
		if not ok or accessible ~= true then
			return false
		end
	end
	return true
end

function PvPTogether:CanAccessTable(value)
	if type(value) ~= "table" or not self:CanAccessValue(value) then
		return false
	end
	if raw_canaccesstable then
		local ok, accessible = pcall(raw_canaccesstable, value)
		if not ok or accessible ~= true then
			return false
		end
	end
	return true
end

-- Contain access failures without treating pcall as a taint boundary. Callers
-- must still reject forbidden frames before reading any other frame members.
function PvPTogether:SafeGetField(object, key)
	if not self:CanAccessValue(object) or not self:CanAccessValue(key) then
		return nil, false
	end
	local objectType = type(object)
	if
		(objectType ~= "table" and objectType ~= "userdata")
		or (objectType == "table" and not self:CanAccessTable(object))
	then
		return nil, false
	end
	local ok, value = pcall(function()
		return object[key]
	end)
	if not ok or not self:CanAccessValue(value) then
		return nil, false
	end
	return value, true
end

function PvPTogether:SafeToBoolean(value)
	if not self:CanAccessValue(value) or type(value) ~= "boolean" then
		return nil
	end
	return value
end

function PvPTogether:SafeToNumber(value)
	if not self:CanAccessValue(value) or (type(value) ~= "number" and type(value) ~= "string") then
		return nil
	end
	local ok, numericValue = pcall(tonumber, value)
	if not ok then
		return nil
	end
	if
		type(numericValue) ~= "number"
		or not self:CanAccessValue(numericValue)
		or numericValue ~= numericValue
		or numericValue == math.huge
		or numericValue == -math.huge
	then
		return nil
	end
	return numericValue
end

function PvPTogether:SafeToString(value, fallback)
	local safeFallback = type(fallback) == "string" and self:CanAccessValue(fallback) and fallback or ""
	if not self:CanAccessValue(value) then
		return safeFallback
	end
	local valueType = type(value)
	if valueType == "string" then
		return value
	end
	if valueType == "number" or valueType == "boolean" then
		return tostring(value)
	end
	-- Do not invoke foreign __tostring metamethods from diagnostic paths.
	return safeFallback
end

function PvPTogether:DeepCopy(value)
	if type(value) ~= "table" then
		return value
	end

	local copy = {}
	for key, item in pairs(value) do
		copy[key] = self:DeepCopy(item)
	end
	return copy
end

function PvPTogether:ApplyDefaults(destination, defaults)
	if type(destination) ~= "table" or type(defaults) ~= "table" then
		return destination
	end

	for key, defaultValue in pairs(defaults) do
		if destination[key] == nil then
			destination[key] = self:DeepCopy(defaultValue)
		elseif type(defaultValue) == "table" and type(destination[key]) == "table" then
			self:ApplyDefaults(destination[key], defaultValue)
		end
	end

	return destination
end

function PvPTogether:IsInCombatLockdown()
	if not self:CanAccessValue(InCombatLockdown) then
		return true
	end
	if type(InCombatLockdown) ~= "function" then
		return InCombatLockdown ~= nil
	end

	local ok, inCombat = pcall(InCombatLockdown)
	if not ok or not self:CanAccessValue(inCombat) then
		return true
	end
	-- Older clients may return nil outside combat.
	return inCombat ~= nil and inCombat ~= false
end

local function GetRegisteredStyleProvider(addon)
	-- Older clients keep the options callback on the registered dropdown.
	-- Inspect its data without constructing, showing, or changing Settings UI.
	local function PlainField(object, key)
		if addon:CanAccessTable(object) then
			local value = rawget(object, key)
			if addon:CanAccessValue(value) then
				return value
			end
		end
	end
	local forbidden = addon:SafeGetField(SettingsPanel, "IsForbidden")
	if type(forbidden) ~= "function" then
		return nil
	end
	local checked, isForbidden = pcall(forbidden, SettingsPanel)
	if not checked or addon:SafeToBoolean(isForbidden) ~= false then
		return nil
	end
	local getSetting = addon:SafeGetField(Settings, "GetSetting")
	local getCategory = addon:SafeGetField(Settings, "GetCategory")
	local categoryID = addon:SafeGetField(Settings, "NAMEPLATE_OPTIONS_CATEGORY_ID")
	local getLayout = addon:SafeGetField(SettingsPanel, "GetLayout")
	if
		type(getSetting) ~= "function"
		or type(getCategory) ~= "function"
		or type(getLayout) ~= "function"
		or (type(categoryID) ~= "number" and type(categoryID) ~= "string")
	then
		return nil
	end
	local gotSetting, setting = pcall(getSetting, "nameplateStyle")
	local gotCategory, category = pcall(getCategory, categoryID)
	if not gotSetting or not addon:CanAccessTable(setting) or not gotCategory or not addon:CanAccessTable(category) then
		return nil
	end
	local gotLayout, layout = pcall(getLayout, SettingsPanel, category)
	local initializers = gotLayout and PlainField(layout, "initializers") or nil
	if not addon:CanAccessTable(initializers) then
		return nil
	end
	for index = 1, 128 do
		local initializer = PlainField(initializers, index)
		if not initializer then
			return nil
		end
		local data = PlainField(initializer, "data")
		if PlainField(data, "setting") == setting then
			return PlainField(data, "options")
		end
	end
end

function PvPTogether:RefreshNameplateStyleOptions()
	self.nameplateStyleOrder = {}
	self.nameplateStyleOptionsAvailable = false
	-- The same provider supplies Blizzard's global nameplateStyle dropdown.
	-- It creates fresh option data; never invoke the settings setup/mutation path.
	local provider, readable = self:SafeGetField(NameplatesOverrides, "GetNameplateStyleOptions")
	if provider == nil and ((self:CanAccessValue(NameplatesOverrides) and NameplatesOverrides == nil) or readable) then
		provider = GetRegisteredStyleProvider(self)
	end
	if type(provider) ~= "function" then
		return false
	end
	local ok, options = pcall(provider)
	if not ok or not self:CanAccessTable(options) then
		return false
	end
	local order, labels, seen = {}, {}, {}
	-- Read only bounded, access-checked plain fields; do not invoke row or array
	-- metamethods. Unknown renderers (including native-only Classic) are omitted.
	for index = 1, 32 do
		local entry = rawget(options, index)
		if not self:CanAccessValue(entry) then
			return false
		end
		if entry == nil then
			self.nameplateStyleOrder = order
			for value, label in pairs(labels) do
				self.nameplateStyleLabels[value] = label
			end
			self.nameplateStyleOptionsAvailable = true
			return true
		end
		if not self:CanAccessTable(entry) then
			return false
		end
		local value = self:SafeToNumber(rawget(entry, "value"))
		local label = rawget(entry, "label")
		if not self:CanAccessValue(label) or type(label) ~= "string" or label == "" then
			return false
		end
		if value == nil or value % 1 ~= 0 then
			return false
		end
		if supportedOverrideStyles[value] and not seen[value] then
			order[#order + 1], labels[value], seen[value] = value, label, true
		end
	end
	return false
end

function PvPTogether:GetCurrentGlobalNameplateStyle()
	if C_CVar and type(C_CVar.GetCVar) == "function" then
		local ok, rawValue = pcall(C_CVar.GetCVar, "nameplateStyle")
		local numericStyle = ok and self:SafeToNumber(rawValue) or nil
		if numericStyle then
			numericStyle = math.floor(numericStyle + 0.5)
			if self:IsGlobalNameplateStyle(numericStyle) then
				return numericStyle
			end
		end
	end

	return STYLE_MODERN
end

function PvPTogether:IsNameplateStyle(value)
	local numericStyle = self:SafeToNumber(value)
	if numericStyle == nil then
		return false
	end
	numericStyle = math.floor(numericStyle + 0.5)

	for _, styleValue in ipairs(self.nameplateStyleOrder) do
		if styleValue == numericStyle then
			return true
		end
	end

	return false
end

function PvPTogether:IsGlobalNameplateStyle(value)
	local numericStyle = self:SafeToNumber(value)
	return numericStyle ~= nil
		and (supportedOverrideStyles[numericStyle] == true or (STYLE_CLASSIC ~= nil and numericStyle == STYLE_CLASSIC))
end

function PvPTogether:NormalizeNameplateStyle(value, fallbackStyle)
	local fallback = self:SafeToNumber(fallbackStyle)
	if not self:IsGlobalNameplateStyle(fallback) then
		fallback = STYLE_MODERN
	end
	fallback = math.floor(fallback + 0.5)

	local numericStyle = self:SafeToNumber(value)
	if not self:IsNameplateStyle(numericStyle) then
		return fallback
	end
	return math.floor(numericStyle + 0.5)
end

function PvPTogether:GetNameplateStyleLabel(styleValue)
	local numericStyle = self:SafeToNumber(styleValue)
	if numericStyle and self:IsGlobalNameplateStyle(numericStyle) then
		return self.nameplateStyleLabels[numericStyle]
	end
	local normalizedStyle = self:NormalizeNameplateStyle(styleValue, STYLE_MODERN)
	return self.nameplateStyleLabels[normalizedStyle] or ("Style " .. self:SafeToString(normalizedStyle, "?"))
end

function PvPTogether:GetConfiguredStyleForUnitKind(unitKind)
	if not self.db then
		return self:GetCurrentGlobalNameplateStyle()
	end

	local styleKey = nil
	if unitKind == "partyMember" then
		styleKey = "partyMemberStyle"
	elseif unitKind == "friendlyPlayer" then
		styleKey = "friendlyPlayerStyle"
	elseif unitKind == "enemyPlayer" then
		styleKey = "enemyPlayerStyle"
	end

	if not styleKey then
		return self:GetCurrentGlobalNameplateStyle()
	end

	local configuredStyle = self.db[styleKey]
	return self:NormalizeNameplateStyle(configuredStyle, self:GetCurrentGlobalNameplateStyle())
end

function PvPTogether:GetBorderOverrideOptionKeysForUnitKind(unitKind)
	if unitKind == "partyMember" then
		return "partyMemberBorderEnabled", "partyMemberBorderColor"
	end
	if unitKind == "friendlyPlayer" then
		return "friendlyPlayerBorderEnabled", "friendlyPlayerBorderColor"
	end
	if unitKind == "enemyPlayer" then
		return "enemyPlayerBorderEnabled", "enemyPlayerBorderColor"
	end
	return nil, nil
end

function PvPTogether:GetDefaultBorderColorForUnitKind(unitKind)
	local _, colorKey = self:GetBorderOverrideOptionKeysForUnitKind(unitKind)
	if colorKey and type(self.DEFAULTS[colorKey]) == "table" then
		return self.DEFAULTS[colorKey]
	end
	return {
		r = 1.0,
		g = 1.0,
		b = 1.0,
	}
end

function PvPTogether:NormalizeColorRGB(colorValue, fallbackColor)
	return {
		r = ClampColorComponent(
			self:SafeGetField(colorValue, "r"),
			ClampColorComponent(self:SafeGetField(fallbackColor, "r"), 1)
		),
		g = ClampColorComponent(
			self:SafeGetField(colorValue, "g"),
			ClampColorComponent(self:SafeGetField(fallbackColor, "g"), 1)
		),
		b = ClampColorComponent(
			self:SafeGetField(colorValue, "b"),
			ClampColorComponent(self:SafeGetField(fallbackColor, "b"), 1)
		),
	}
end

function PvPTogether:IsBorderColorOverrideEnabledForUnitKind(unitKind)
	local enabledKey = self:GetBorderOverrideOptionKeysForUnitKind(unitKind)
	if not enabledKey or not self.db then
		return false
	end
	return self.db[enabledKey] == true
end

function PvPTogether:GetConfiguredBorderColorForUnitKind(unitKind)
	local _, colorKey = self:GetBorderOverrideOptionKeysForUnitKind(unitKind)
	local fallbackColor = self:GetDefaultBorderColorForUnitKind(unitKind)
	if not colorKey or not self.db then
		return self:NormalizeColorRGB(nil, fallbackColor)
	end
	return self:NormalizeColorRGB(self.db[colorKey], fallbackColor)
end

function PvPTogether:InitializeDatabase()
	self:RefreshNameplateStyleOptions()
	if type(_G.PvPTogetherDBChar) ~= "table" then
		_G.PvPTogetherDBChar = {}
	end

	self.db = _G.PvPTogetherDBChar
	self:ApplyDefaults(self.db, self.DEFAULTS)

	if self.db.styleSeeded ~= true then
		local globalStyle = self:GetCurrentGlobalNameplateStyle()
		-- Classic is a native-only global mode, not a per-type override. Keep
		-- inheritance instead of persisting a style the selectors cannot offer.
		if not self:IsNameplateStyle(globalStyle) then
			globalStyle = nil
		end
		if self.db.partyMemberStyle == nil then
			self.db.partyMemberStyle = globalStyle
		end
		if self.db.friendlyPlayerStyle == nil then
			self.db.friendlyPlayerStyle = globalStyle
		end
		if self.db.enemyPlayerStyle == nil then
			self.db.enemyPlayerStyle = globalStyle
		end
		self.db.styleSeeded = true
	end

	if self.db.partyMemberStyleSeeded ~= true then
		if self.db.partyMemberStyle == nil and self:IsNameplateStyle(self.db.friendlyPlayerStyle) then
			local fallbackGroupStyle =
				self:NormalizeNameplateStyle(self.db.friendlyPlayerStyle, self:GetCurrentGlobalNameplateStyle())
			self.db.partyMemberStyle = fallbackGroupStyle
		end
		self.db.partyMemberStyleSeeded = true
	end

	local fallbackStyle = self:GetCurrentGlobalNameplateStyle()
	local function NormalizeStoredStyle(value)
		if self:IsGlobalNameplateStyle(value) and not self:IsNameplateStyle(value) then
			-- A load-order delay must not erase a saved choice. Until the provider
			-- arrives it is inactive and behaves as inheritance.
			if not self.nameplateStyleOptionsAvailable and self:SafeToNumber(value) ~= STYLE_CLASSIC then
				return self:SafeToNumber(value)
			end
			return nil
		end
		local normalizedStyle = self:NormalizeNameplateStyle(value, fallbackStyle)
		return self:IsNameplateStyle(normalizedStyle) and normalizedStyle or nil
	end
	if self.db.partyMemberStyle ~= nil then
		self.db.partyMemberStyle = NormalizeStoredStyle(self.db.partyMemberStyle)
	end
	if self.db.friendlyPlayerStyle ~= nil then
		self.db.friendlyPlayerStyle = NormalizeStoredStyle(self.db.friendlyPlayerStyle)
	end
	if self.db.enemyPlayerStyle ~= nil then
		self.db.enemyPlayerStyle = NormalizeStoredStyle(self.db.enemyPlayerStyle)
	end
	self.db.partyMemberBorderEnabled = self.db.partyMemberBorderEnabled == true
	self.db.friendlyPlayerBorderEnabled = self.db.friendlyPlayerBorderEnabled == true
	self.db.enemyPlayerBorderEnabled = self.db.enemyPlayerBorderEnabled == true
	self.db.partyMemberBorderColor =
		self:NormalizeColorRGB(self.db.partyMemberBorderColor, self.DEFAULTS.partyMemberBorderColor)
	self.db.friendlyPlayerBorderColor =
		self:NormalizeColorRGB(self.db.friendlyPlayerBorderColor, self.DEFAULTS.friendlyPlayerBorderColor)
	self.db.enemyPlayerBorderColor =
		self:NormalizeColorRGB(self.db.enemyPlayerBorderColor, self.DEFAULTS.enemyPlayerBorderColor)
	self.db.enabled = self.db.enabled ~= false
end

function PvPTogether:GetOption(optionKey)
	if not self.db then
		return nil
	end
	return self.db[optionKey]
end

function PvPTogether:SetOption(optionKey, value)
	if not self.db or not IsNonEmptyString(optionKey) or not self:CanAccessValue(value) then
		return false
	end

	local normalizedValue = value
	if optionKey == "enabled" then
		normalizedValue = self:SafeToBoolean(value)
		if normalizedValue == nil then
			return false
		end
	elseif optionKey == "partyMemberStyle" or optionKey == "friendlyPlayerStyle" or optionKey == "enemyPlayerStyle" then
		if value == nil then
			normalizedValue = nil
		else
			if not self:IsNameplateStyle(value) then
				return false
			end
			local fallbackStyle = self:GetCurrentGlobalNameplateStyle()
			normalizedValue = self:NormalizeNameplateStyle(value, fallbackStyle)
			if not self:IsNameplateStyle(normalizedValue) then
				normalizedValue = nil
			end
		end
	elseif
		optionKey == "partyMemberBorderEnabled"
		or optionKey == "friendlyPlayerBorderEnabled"
		or optionKey == "enemyPlayerBorderEnabled"
	then
		normalizedValue = self:SafeToBoolean(value)
		if normalizedValue == nil then
			return false
		end
	elseif optionKey == "partyMemberBorderColor" then
		normalizedValue = self:NormalizeColorRGB(value, self.DEFAULTS.partyMemberBorderColor)
	elseif optionKey == "friendlyPlayerBorderColor" then
		normalizedValue = self:NormalizeColorRGB(value, self.DEFAULTS.friendlyPlayerBorderColor)
	elseif optionKey == "enemyPlayerBorderColor" then
		normalizedValue = self:NormalizeColorRGB(value, self.DEFAULTS.enemyPlayerBorderColor)
	else
		return false
	end

	if type(normalizedValue) == "table" and type(self.db[optionKey]) == "table" then
		if ColorTablesEqual(self.db[optionKey], normalizedValue) then
			return false
		end
	elseif self.db[optionKey] == normalizedValue then
		return false
	end

	if type(normalizedValue) == "table" then
		self.db[optionKey] = self:DeepCopy(normalizedValue)
	else
		self.db[optionKey] = normalizedValue
	end
	if normalizedValue == false and optionKey ~= "enabled" and self.InvalidateOptionsCallbacks then
		-- A picker opened for a border that was then disabled must not revive
		-- when the border is re-enabled, or cancel back over a later setting.
		self:InvalidateOptionsCallbacks()
	end

	if optionKey == "enabled" then
		if normalizedValue then
			self:Enable()
		else
			self:Disable()
		end
	elseif self.isEnabled then
		-- Coalesce slider/picker updates and let the module enforce restrictions.
		if self.ScheduleReapplyAllNameplateStyles then
			self:ScheduleReapplyAllNameplateStyles(0.02)
		elseif self.ReapplyAllNameplateStyles then
			self:ReapplyAllNameplateStyles("option:" .. optionKey)
		end
	end
	if self.RefreshOptionsWindow and self.optionsFrame then
		self:RefreshOptionsWindow()
	end

	return true
end

function PvPTogether:Print(message)
	local text = "|cff00ff98PvPTogether|r: " .. self:SafeToString(message, "")
	local chatFrame = DEFAULT_CHAT_FRAME
	if not self:CanAccessValue(chatFrame) then
		return
	end
	if chatFrame == nil then
		pcall(print, text)
		return
	end
	local isForbidden, readable = self:SafeGetField(chatFrame, "IsForbidden")
	local allowed = readable
	if type(isForbidden) == "function" then
		local ok, forbidden = pcall(isForbidden, chatFrame)
		allowed = ok and self:SafeToBoolean(forbidden) == false
	end
	if allowed then
		local addMessage = self:SafeGetField(chatFrame, "AddMessage")
		if type(addMessage) == "function" and pcall(addMessage, chatFrame, text) then
			return
		end
	end
end

-- Static reasons only: never retain foreign error text, unit tokens, GUIDs, or values.
-- Bound both the number of reasons and each count for long-running sessions.
function PvPTogether:RecordDiagnostic(reason)
	self.diagnosticCounterStore = self.diagnosticCounterStore or LibChev.NewCounters()
	local count = LibChev.Count(self.diagnosticCounterStore, reason)
	self.diagnosticCounts = self.diagnosticCounterStore.counts
	self.diagnosticReasonCount = self.diagnosticCounterStore.size
	-- Sample only static reasons; preserve the established no-identity policy.
	if count and (count <= 3 or count % 100 == 0) then
		self:GetDebugController():Append(reason .. " count=" .. count, "STATE")
	end
end

function PvPTogether:GetDiagnosticSnapshot()
	return LibChev.CounterSnapshot(self.diagnosticCounterStore or LibChev.NewCounters())
end

function PvPTogether:GetDiagnosticVersion()
	local addonVersion = "unknown"
	local getMetadata = self:SafeGetField(C_AddOns, "GetAddOnMetadata")
	if type(getMetadata) == "function" then
		local ok, value = pcall(getMetadata, self.addonName, "Version")
		if ok then
			addonVersion = self:SafeToString(value, addonVersion)
		end
	end
	return addonVersion
end

function PvPTogether:GetDiagnosticTime()
	local getTime = self:SafeGetField(_G, "GetTime")
	if type(getTime) == "function" then
		local ok, value = pcall(getTime)
		if ok then
			return LibChev.Number(value)
		end
	end
end

function PvPTogether:GetDiagnosticEnvironment()
	return LibChev.ReadEnvironment({ GetBuildInfo = GetBuildInfo, GetLocale = GetLocale })
end

function PvPTogether:NewDiagnosticReport()
	return LibChev.DiagnosticReport("PvPTogether", self:GetDiagnosticVersion(), self:GetDiagnosticEnvironment())
end

function PvPTogether:BuildDiagnostics()
	local report = self:NewDiagnosticReport()
	local function Add(label, value)
		report:Add(label, value)
	end
	local capabilities = self.GetNameplateCapabilities and self:GetNameplateCapabilities() or {}
	Add("enabled", self.isEnabled == true)
	Add("capability.styleOverrides", capabilities.styleOverrides == true)
	Add("capability.borderTint", capabilities.borderTint == true)
	Add("capability.reason", capabilities.reason or "none")
	Add(
		"runtimeRestricted",
		self.IsNameplateAugmentationBlockedInCurrentContext and self:IsNameplateAugmentationBlockedInCurrentContext()
			or self:IsInCombatLockdown()
	)
	Add("combat", self:IsInCombatLockdown())
	Add("secretGuards", (raw_issecretvalue or raw_canaccessvalue) ~= nil)
	local function Count(entries)
		local count = 0
		for _ in pairs(entries or {}) do
			count = count + 1
		end
		return count
	end
	Add("pendingCleanup", self.pendingNameplateResetAfterCombat == true)
	Add("pendingRefresh", self.pendingNameplateRefreshAfterCombat == true or self.nameplateRefreshScheduled == true)
	Add("queuedPlates", Count(self.nameplatePendingFrames))
	Add("retainedLayouts", Count(self.nameplateStateByFrame))
	Add("trackedPlates", Count(self.trackedNamePlateFrames))
	Add("borderOverlays", Count(self.nameplateBorderTintByUnitFrame))
	local failure = self.lastLayoutFailure
	if failure then
		Add("layoutFailure.step", failure.step)
		Add("layoutFailure.property", failure.property)
		Add("layoutFailure.stage", failure.stage)
		Add("layoutFailure.reason", failure.reason)
	end
	Add("globalStyle", self:GetNameplateStyleLabel(self:GetCurrentGlobalNameplateStyle()))
	for _, kind in ipairs({ "partyMember", "friendlyPlayer", "enemyPlayer" }) do
		local style = self:GetOption(kind .. "Style")
		Add(kind .. ".style", self:IsNameplateStyle(style) and self:GetNameplateStyleLabel(style) or "inherit global")
		Add(kind .. ".border", self:IsBorderColorOverrideEnabledForUnitKind(kind))
	end
	for _, entry in ipairs(self:GetDiagnosticSnapshot()) do
		Add("counter." .. entry.reason, entry.count)
	end
	return report:Text()
end

-- All generic debug state and UI behavior belongs to the private library.
-- Domain safety, counters, and the no-identity data policy stay in this addon.
function PvPTogether:GetDebugController()
	local controller = rawget(self, "debugController")
	if controller then
		return controller
	end
	controller = LibChev.NewDebugController({
		addonName = "PvPTogether",
		getLog = function()
			return self.diagnosticLog or LibChev.NewLog()
		end,
		commitLog = function(store)
			self.diagnosticLog = store
		end,
		limits = { maxLines = 60, maxEntry = 100 },
		clock = function()
			return self:GetDiagnosticTime()
		end,
		getTests = function()
			return self:GetInGameTests()
		end,
		getVersion = function()
			return self:GetDiagnosticVersion()
		end,
		getEnvironment = function()
			return self:GetDiagnosticEnvironment()
		end,
		buildReport = function()
			return self:BuildDiagnostics()
		end,
		print = function(text)
			self:Print(text)
		end,
		reload = type(ReloadUI) == "function" and ReloadUI or nil,
		failureDetails = false,
		ui = {
			parent = UIParent,
			createFrame = function(...)
				return CreateFrame(...)
			end,
			restricted = function()
				return not self.IsNameplateAugmentationBlockedInCurrentContext
					or self:IsNameplateAugmentationBlockedInCurrentContext()
			end,
			canMutate = function(region)
				return LibChev.CanMutateOwnedRegion(region)
					and type(self.CanMutateNameplateFrame) == "function"
					and self:CanMutateNameplateFrame(region)
			end,
		},
		onWindow = function(frame)
			self.diagnosticsWindow = frame
		end,
	})
	self.debugController = controller
	return controller
end

function PvPTogether:BuildDiagnosticExport()
	return self:GetDebugController():BuildDiagnosticExport()
end

function PvPTogether:ShowDiagnosticReport(report)
	return self:GetDebugController():ShowReport(report)
end

function PvPTogether:PrintDiagnostics()
	return self:GetDebugController():ShowDiagnostics()
end

function PvPTogether:RegisterSlashCommands()
	if self.slashCommandsRegistered then
		return
	end

	SLASH_PVPTOGETHER1 = "/pt"
	SLASH_PVPTOGETHER2 = "/pvptogether"
	SlashCmdList.PVPTOGETHER = function(message)
		local command = self:SafeToString(message, "")
		if self:GetDebugController():HandleCommand(command) then
			return
		end
		command = command:lower():gsub("^%s+", ""):gsub("%s+$", "")
		if command == "on" then
			self:SetOption("enabled", true)
			self:Print("Enabled.")
			return
		end
		if command == "off" then
			self:SetOption("enabled", false)
			self:Print("Disabled.")
			return
		end
		if command == "toggle" then
			self:SetOption("enabled", not self:GetOption("enabled"))
			self:Print(self:GetOption("enabled") and "Enabled." or "Disabled.")
			return
		end
		if not self:OpenOptionsWindow() then
			self:Print("Use /pt on, /pt off, /pt toggle, /pt debug, /pt dump, /pt diagnostics, or /pt test.")
		end
	end

	self.slashCommandsRegistered = true
end

function PvPTogether:Enable()
	if not self.hasLoggedIn or self.isEnabled then
		return
	end

	self.isEnabled = true

	if self.EnableNameplateModule then
		self:EnableNameplateModule()
	end
	if self.StartOptionsPreviewTicker then
		self:StartOptionsPreviewTicker()
	end
end

function PvPTogether:Disable()
	if not self.isEnabled then
		return
	end

	self.isEnabled = false
	if self.InvalidateOptionsCallbacks then
		self:InvalidateOptionsCallbacks()
	end
	if self.StopOptionsPreviewTicker then
		self:StopOptionsPreviewTicker()
	end

	if self.DisableNameplateModule then
		self:DisableNameplateModule()
	end
end

function PvPTogether:Initialize()
	if self.isInitialized then
		return
	end

	self:InitializeDatabase()
	self:RegisterSlashCommands()
	self.isInitialized = true
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:SetScript("OnEvent", function(_, eventName, ...)
	if eventName == "ADDON_LOADED" then
		local loadedAddonName = ...
		if loadedAddonName == PvPTogether.addonName then
			PvPTogether:Initialize()
		elseif loadedAddonName == "Blizzard_SettingsDefinitions_Frame" then
			PvPTogether:RefreshNameplateStyleOptions()
			if PvPTogether.isEnabled and PvPTogether.ScheduleReapplyAllNameplateStyles then
				PvPTogether:ScheduleReapplyAllNameplateStyles(0)
			end
		end
	elseif eventName == "PLAYER_LOGIN" then
		PvPTogether:RefreshNameplateStyleOptions()
		PvPTogether.hasLoggedIn = true
		if not PvPTogether.isInitialized then
			PvPTogether:Initialize()
		end
		if PvPTogether.InitializeOptionsWindow then
			PvPTogether:InitializeOptionsWindow()
		end

		if PvPTogether:GetOption("enabled") then
			PvPTogether:Enable()
		end
	end
end)
