-- Private offline fixtures. Never include this file in an addon TOC.
return function(root)
	local H = { cases = {}, root = root }
	function H.test(name, run)
		H.cases[#H.cases + 1] = { name = name, run = run }
	end
	function H.equal(actual, expected, message)
		assert(
			actual == expected,
			(message or "unexpected value") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual)
		)
	end
	function H.truthy(actual, message)
		assert(actual, message or "expected a truthy result")
	end
	function H.falsy(actual, message)
		assert(not actual, message or "expected a false/nil result")
	end
	function H.count(value)
		local count = 0
		for _ in pairs(value) do
			count = count + 1
		end
		return count
	end

	function H.new(options)
		options = options or {}
		local namespace = {}
		local state = {
			combat = false,
			instanceType = "none",
			restricted = {},
			now = 0,
			frames = {},
			frameData = {},
			mutations = {},
			foreignWrites = 0,
			secret = {},
			inaccessible = {},
			inaccessibleTables = {},
			queryErrors = {},
			units = {},
			plates = {},
			visible = {},
			timers = {},
			hooks = {},
			messages = {},
			cvars = {
				nameplateStyle = "0",
				nameplateSize = "2",
				nameplateAuraScale = "1",
				nameplateDebuffPadding = "0",
			},
			cvarWrites = {},
			driverUpdates = 0,
		}
		local env = {}
		for _, key in ipairs({
			"assert",
			"error",
			"getmetatable",
			"ipairs",
			"next",
			"pairs",
			"pcall",
			"rawequal",
			"rawget",
			"rawset",
			"select",
			"setmetatable",
			"tonumber",
			"tostring",
			"type",
			"unpack",
			"xpcall",
			"math",
			"string",
			"table",
			"coroutine",
		}) do
			env[key] = _G[key]
		end
		env.unpack = unpack or table.unpack
		env._G = env
		env.print = function(...)
			state.messages[#state.messages + 1] = { ... }
		end
		env.SlashCmdList = {}
		env.Enum = {
			NamePlateStyle = { Modern = 0, Thin = 1, Block = 2, HealthFocus = 3, CastFocus = 4, Legacy = 5 },
			NamePlateSize = { Small = 1, Medium = 2, Large = 3, ExtraLarge = 4, Huge = 5 },
			AddOnRestrictionType = { Combat = 0, Encounter = 1, ChallengeMode = 2, PvPMatch = 3, Map = 4 },
			AddOnRestrictionState = { Inactive = 0, Activating = 1, Active = 2 },
		}
		env.WOW_PROJECT_MAINLINE, env.WOW_PROJECT_ID = 1, 1
		env.LE_PARTY_CATEGORY_HOME = 1
		env.issecretvalue = function(value)
			if state.queryErrors.issecretvalue then
				error("secret query unavailable")
			end
			return state.secret[value] == true
		end
		env.canaccessvalue = function(value)
			if state.queryErrors.canaccessvalue then
				error("access query unavailable")
			end
			return not state.inaccessible[value]
		end
		env.canaccesstable = function(value)
			if state.queryErrors.canaccesstable then
				error("table access query unavailable")
			end
			return not state.inaccessibleTables[value]
		end
		env.GetTime = function()
			return state.now
		end
		env.InCombatLockdown = function()
			if state.queryErrors.InCombatLockdown then
				error("combat query unavailable")
			end
			return state.combat
		end
		env.IsInInstance = function()
			return state.instanceType ~= "none", state.instanceType
		end
		env.IsEncounterInProgress = function()
			return state.encounter == true
		end
		env.C_RestrictedActions = {
			GetAddOnRestrictionState = function(kind)
				if state.queryErrors.restrictions then
					error("restriction query unavailable")
				end
				return state.restricted[kind] or env.Enum.AddOnRestrictionState.Inactive
			end,
			IsAddOnRestrictionActive = function(kind)
				if state.queryErrors.restrictions then
					error("restriction query unavailable")
				end
				return state.restricted[kind] or false
			end,
			CheckAllowProtectedFunctions = function(frame)
				if state.queryErrors.protectedFunctions then
					error("protection query unavailable")
				end
				if state.allowProtectedFunctions ~= nil then
					return state.allowProtectedFunctions
				end
				return not state.combat and not state.frameData[frame].forbidden
			end,
		}
		env.C_ChallengeMode = {
			IsChallengeModeActive = function()
				return state.challenge == true
			end,
		}
		env.C_PvP = {
			IsActiveBattlefield = function()
				return state.battlefield == true
			end,
		}
		env.GetBuildInfo = function()
			return "12.1.0", "69933", "Sep 24 2026", 120100
		end
		env.C_AddOns = {
			GetAddOnMetadata = function()
				return "1.0.7"
			end,
			LoadAddOn = function()
				return true
			end,
		}
		env.C_CVar = {
			GetCVar = function(name)
				if state.queryErrors.cvar then
					error("CVar query unavailable")
				end
				return state.cvars[name]
			end,
			SetCVar = function(name, value)
				state.cvarWrites[#state.cvarWrites + 1] = { name, value }
				state.cvars[name] = value
			end,
		}
		env.GetCVar = env.C_CVar.GetCVar
		env.GetCVarBool = function(name)
			return env.C_CVar.GetCVar(name) == "1"
		end

		local frameMethods = {}
		local function data(frame)
			return assert(state.frameData[frame], "not a fixture frame")
		end
		local function result(frame, name, default)
			local config = data(frame)
			if config.errors[name] then
				error("fixture frame method unavailable: " .. name)
			end
			if config.results[name] ~= nil then
				return config.results[name]
			end
			return default
		end
		local function mutate(frame, method, ...)
			local config = data(frame)
			assert(not config.forbidden, "attempted " .. method .. " on a forbidden frame")
			assert(
				not state.inaccessible[frame] and not state.inaccessibleTables[frame],
				"attempted inaccessible frame mutation"
			)
			assert(not (config.protected and state.combat), "attempted protected mutation in combat")
			if config.errors[method] then
				error("fixture mutator failed: " .. method)
			end
			state.mutations[#state.mutations + 1] = { frame = frame, method = method, arguments = { ... } }
		end
		function frameMethods:IsForbidden()
			return result(self, "IsForbidden", data(self).forbidden or false)
		end
		function frameMethods:IsProtected()
			return result(self, "IsProtected", data(self).protected or false), data(self).explicitlyProtected or false
		end
		function frameMethods:IsShown()
			return result(self, "IsShown", data(self).shown ~= false)
		end
		function frameMethods:IsVisible()
			return self:IsShown()
		end
		function frameMethods:GetParent()
			return result(self, "GetParent", data(self).parent)
		end
		function frameMethods:GetUnit()
			return result(self, "GetUnit", data(self).unit)
		end
		function frameMethods:GetWidth()
			return result(self, "GetWidth", data(self).width or 200)
		end
		function frameMethods:GetHeight()
			return result(self, "GetHeight", data(self).height or 20)
		end
		function frameMethods:GetSize()
			return self:GetWidth(), self:GetHeight()
		end
		function frameMethods:GetScale()
			return result(self, "GetScale", data(self).scale or 1)
		end
		function frameMethods:GetAlpha()
			return result(self, "GetAlpha", data(self).alpha or 1)
		end
		function frameMethods:GetLineHeight()
			return result(self, "GetLineHeight", 12)
		end
		function frameMethods:GetTextHeight()
			return result(self, "GetTextHeight", 12)
		end
		function frameMethods:GetFrameLevel()
			return 1
		end
		function frameMethods:GetFrameStrata()
			return "MEDIUM"
		end
		function frameMethods:GetChecked()
			return data(self).checked == true
		end
		function frameMethods:SetChecked(value)
			data(self).checked = value
		end
		function frameMethods:SetEnabled(value)
			data(self).enabled = value
		end
		function frameMethods:SetupMenu(callback)
			data(self).menu = callback
		end
		function frameMethods:SetScrollChild(child)
			data(self).scrollChild = child
		end
		function frameMethods:GetFontObject()
			return result(self, "GetFontObject", data(self).fontObject or env.SystemFont_NamePlate)
		end
		function frameMethods:GetName()
			return data(self).name
		end
		function frameMethods:GetFont()
			return env.unpack(data(self).font or { "Fonts/FRIZQT__.TTF", data(self).textHeight or 12, "OUTLINE" })
		end
		function frameMethods:GetJustifyH()
			return result(self, "GetJustifyH", data(self).justify or "LEFT")
		end
		function frameMethods:GetNumPoints()
			return #data(self).points
		end
		function frameMethods:GetPoint(index)
			if data(self).errors.GetPoint then
				error("position query blocked")
			end
			return env.unpack(data(self).points[index or 1] or { "CENTER", data(self).parent, "CENTER", 0, 0 })
		end
		function frameMethods:GetVertexColor()
			return 1, 1, 1, 1
		end
		function frameMethods:IsShowOnlyName()
			return result(self, "IsShowOnlyName", false)
		end
		function frameMethods:SetScript(name, callback)
			data(self).scripts[name] = callback
		end
		function frameMethods:GetScript(name)
			return data(self).scripts[name]
		end
		function frameMethods:RegisterEvent(name)
			data(self).events[name] = true
		end
		function frameMethods:UnregisterEvent(name)
			data(self).events[name] = nil
		end
		function frameMethods:UnregisterAllEvents()
			data(self).events = {}
		end
		function frameMethods:HookScript(name, callback)
			data(self).scripts[name] = callback
		end
		function frameMethods:Show()
			mutate(self, "Show")
			data(self).shown = true
		end
		function frameMethods:Hide()
			mutate(self, "Hide")
			data(self).shown = false
		end
		function frameMethods:SetShown(value)
			if value then
				self:Show()
			else
				self:Hide()
			end
		end
		function frameMethods:ClearAllPoints()
			mutate(self, "ClearAllPoints")
			data(self).points = {}
			state:fireHook("ClearAllPoints", self)
		end
		function frameMethods:SetPoint(...)
			mutate(self, "SetPoint", ...)
			local points = data(self).points
			local incoming = { ... }
			local index = #points + 1
			for i, point in ipairs(points) do
				if point[1] == incoming[1] then
					index = i
					break
				end
			end
			points[index] = incoming
			state:fireHook("SetPoint", self, ...)
		end
		function frameMethods:SetHeight(value)
			mutate(self, "SetHeight", value)
			data(self).height = value
		end
		function frameMethods:SetWidth(value)
			mutate(self, "SetWidth", value)
			data(self).width = value
		end
		function frameMethods:SetSize(width, height)
			mutate(self, "SetSize", width, height)
			data(self).width, data(self).height = width, height
		end
		function frameMethods:SetFont(...)
			mutate(self, "SetFont", ...)
			data(self).font = { ... }
			return true
		end
		function frameMethods:SetFontObject(value)
			mutate(self, "SetFontObject", value)
			data(self).fontObject = type(value) == "string" and env[value] or value
		end
		function frameMethods:SetTextHeight(value)
			mutate(self, "SetTextHeight", value)
			data(self).textHeight = value
		end
		function frameMethods:SetJustifyH(value)
			mutate(self, "SetJustifyH", value)
			data(self).justify = value
		end
		function frameMethods:ApplyFrameOptions()
			error("addon invoked Blizzard ApplyFrameOptions")
		end
		function frameMethods:UpdateAnchors()
			error("addon invoked Blizzard UpdateAnchors")
		end
		for _, name in ipairs({
			"SetAtlas",
			"SetTexture",
			"SetHorizTile",
			"SetVertTile",
			"SetNormalTexture",
			"SetPushedTexture",
			"SetHighlightTexture",
			"SetBlendMode",
			"SetColorTexture",
			"SetVertexColor",
			"SetAlpha",
			"SetScale",
			"SetDrawLayer",
			"SetAllPoints",
			"SetText",
			"SetFrameLevel",
			"SetFrameStrata",
			"SetToplevel",
			"SetFlattensRenderLayers",
			"SetParent",
			"SetMaxLines",
			"SetMinMaxValues",
			"SetStatusBarColor",
			"SetStatusBarTexture",
			"SetTextColor",
			"SetValue",
			"SetWordWrap",
			"CloseMenu",
			"OverrideText",
			"Update",
			"SetClampedToScreen",
			"EnableMouse",
			"EnableMouseWheel",
			"SetMultiLine",
			"SetAutoFocus",
			"SetTextInsets",
			"HighlightText",
			"SetMovable",
			"SetResizable",
			"SetResizeBounds",
			"RegisterForDrag",
			"SetMaxLetters",
			"SetOrientation",
			"SetValueStep",
			"SetThumbTexture",
			"StartMoving",
			"StartSizing",
			"StopMovingOrSizing",
			"Raise",
		}) do
			local method = name
			frameMethods[method] = function(self, ...)
				mutate(self, method, ...)
			end
		end
		function frameMethods:SetText(value)
			mutate(self, "SetText", value)
			data(self).text = value
			local callback = data(self).scripts.OnTextChanged
			if callback then
				callback(self, false)
			end
		end
		function frameMethods:GetText()
			return data(self).text
		end
		function frameMethods:GetStringHeight()
			return result(self, "GetStringHeight", 240)
		end
		function frameMethods:GetVerticalScroll()
			return data(self).scroll or 0
		end
		function frameMethods:GetVerticalScrollRange()
			return 1000
		end
		function frameMethods:SetVerticalScroll(value)
			mutate(self, "SetVerticalScroll", value)
			data(self).scroll = value
		end
		function frameMethods:SetFocus()
			mutate(self, "SetFocus")
			data(self).focused = true
			local callback = data(self).scripts.OnEditFocusGained
			if callback then
				callback(self)
			end
		end
		function frameMethods:ClearFocus()
			mutate(self, "ClearFocus")
			data(self).focused = false
		end

		function state:frame(fields, foreign)
			local frame = {}
			local config = {
				fields = fields or {},
				foreign = foreign == true,
				scripts = {},
				events = {},
				results = {},
				errors = {},
				points = {},
			}
			self.frameData[frame] = config
			self.frames[#self.frames + 1] = frame
			setmetatable(frame, {
				__index = function(_, key)
					if config.missing and config.missing[key] then
						return nil
					end
					if self.inaccessible[frame] or self.inaccessibleTables[frame] then
						error("read of inaccessible foreign frame")
					end
					if config.forbidden and key ~= "IsForbidden" then
						error("read of forbidden foreign frame: " .. tostring(key))
					end
					if config.fields[key] ~= nil then
						return config.fields[key]
					end
					return frameMethods[key]
				end,
				__newindex = function(_, key, value)
					if config.foreign then
						self.foreignWrites = self.foreignWrites + 1
						error("addon wrote foreign frame field: " .. tostring(key))
					end
					config.fields[key] = value
				end,
			})
			return frame
		end
		function frameMethods:CreateTexture()
			mutate(self, "CreateTexture")
			local frame = state:frame({}, false)
			data(frame).parent = self
			return frame
		end
		function frameMethods:CreateFontString()
			local frame = state:frame({}, false)
			data(frame).parent = self
			return frame
		end
		env.CreateFrame = function(_, name, parent)
			local frame = state:frame({}, false)
			data(frame).parent = parent
			if name then
				env[name] = frame
			end
			return frame
		end
		env.UIParent = state:frame({}, true)
		env.SystemFont_NamePlate = state:frame({}, true)
		env.SystemFont_NamePlate_Outlined = state:frame({}, true)
		data(env.SystemFont_NamePlate).name = "SystemFont_NamePlate"
		data(env.SystemFont_NamePlate_Outlined).name = "SystemFont_NamePlate_Outlined"
		env.NamePlateDriverFrame = state:frame({
			UpdateNamePlateOptions = function()
				state.driverUpdates = state.driverUpdates + 1
			end,
		}, true)
		env.NamePlateBaseMixin = { ApplyFrameOptions = function() end }
		env.NamePlateUnitFrameMixin =
			{ OnUnitSet = function() end, OnUnitCleared = function() end, UpdateAnchors = function() end }
		env.NamePlateDriverMixin = { UpdateNamePlateOptions = function() end }
		env.DropdownButtonMixin = {}
		env.Settings = {
			RegisterCanvasLayoutCategory = function()
				return {
					GetID = function()
						return 42
					end,
				}
			end,
			RegisterAddOnCategory = function() end,
			OpenToCategory = function(id)
				state.openCategory = id
			end,
		}
		env.ColorPickerFrame = state:frame({
			SetupColorPickerAndShow = function(_, info)
				state.picker = info
			end,
			GetColorRGB = function()
				return env.unpack(state.pickerColor or { 0.2, 0.3, 0.4 })
			end,
		}, true)
		env.NamePlateSetupOptions = {
			healthBarHeight = 20,
			castBarHeight = 10,
			healthBarFontHeight = 12,
			castBarFontHeight = 10,
			castIconWidth = 16,
			castIconHeight = 16,
			castBarShieldWidth = 20,
			castBarShieldHeight = 20,
			classificationScale = 1,
			verticalScale = 1,
			unitNameAnchorStyle = 0,
			useClassicHealthBar = false,
			useClassicCastBar = false,
		}
		env.NamePlateConstants = {
			LARGE_HEALTH_BAR_HEIGHT = 20,
			SMALL_HEALTH_BAR_HEIGHT = 10,
			LARGE_CAST_BAR_HEIGHT = 16,
			SMALL_CAST_BAR_HEIGHT = 10,
			AURA_ITEM_HEIGHT = 25,
		}
		env.hooksecurefunc = function(owner, method, callback)
			state.hooks[#state.hooks + 1] = { owner = owner, method = method, callback = callback }
		end
		env.UIParentLoadAddOn = function()
			return true
		end
		env.C_NamePlate = {
			GetNamePlateForUnit = function(token)
				return state.plates[token]
			end,
			GetNamePlates = function()
				return state.visible
			end,
		}
		local function unitResult(name, token, fallback)
			local unit = state.units[token]
			if not unit then
				return fallback
			end
			if unit.errors and unit.errors[name] then
				error("unit API unavailable: " .. name)
			end
			local value = unit[name]
			if value ~= nil then
				return value
			end
			return fallback
		end
		env.UnitExists = function(token)
			return unitResult("exists", token, state.units[token] ~= nil)
		end
		env.UnitGUID = function(token)
			return unitResult("guid", token, nil)
		end
		env.UnitIsPlayer = function(token)
			return unitResult("isPlayer", token, false)
		end
		env.UnitIsFriend = function(_, token)
			return unitResult("isFriend", token, false)
		end
		env.UnitInParty = function(token)
			return unitResult("inParty", token, false)
		end
		env.UnitInRaid = function(token)
			return unitResult("inRaid", token, nil)
		end
		env.UnitIsUnit = function(left, right)
			local unit = state.units[left]
			if unit and unit.isUnit ~= nil then
				return unit.isUnit
			end
			if left == right then
				return true
			end
			return unit and state.units[right] and unit.guid ~= nil and unit.guid == state.units[right].guid or false
		end
		env.GetNumSubgroupMembers = function()
			return state.partyCount or 0
		end
		env.C_Timer = {
			After = function(delay, callback)
				state.timers[#state.timers + 1] = { delay = delay, callback = callback }
			end,
			NewTicker = function(delay, callback)
				local timer = { delay = delay, callback = callback, repeating = true }
				function timer:Cancel()
					self.cancelled = true
				end
				state.timers[#state.timers + 1] = timer
				return timer
			end,
		}

		function state:load(file, loaderNamespace, loaderName)
			local chunk, err
			if setfenv then
				chunk, err = loadfile(root .. "/" .. file)
				if chunk then
					setfenv(chunk, env)
				end
			else
				chunk, err = loadfile(root .. "/" .. file, "t", env)
			end
			assert(chunk, err)(loaderName or "PvPTogether", loaderNamespace or namespace)
		end
		function state:flushTimers()
			local queued = self.timers
			self.timers = {}
			for _, timer in ipairs(queued) do
				if not timer.cancelled then
					timer.callback()
				end
			end
			return #queued
		end
		function state:emit(event, ...)
			local snapshot = {}
			for _, frame in ipairs(self.frames) do
				snapshot[#snapshot + 1] = frame
			end
			for _, frame in ipairs(snapshot) do
				local config = data(frame)
				if config.events[event] and config.scripts.OnEvent then
					config.scripts.OnEvent(frame, event, ...)
				end
			end
		end
		function state:fireHook(method, ...)
			local owner = ...
			for _, hook in ipairs(self.hooks) do
				if hook.method == method and hook.owner == owner then
					hook.callback(...)
				end
			end
		end
		function state:secretValue()
			local value = setmetatable({}, {
				__tostring = function()
					error("secret was stringified")
				end,
				__add = function()
					error("secret arithmetic")
				end,
				__lt = function()
					error("secret comparison")
				end,
			})
			self.secret[value] = true
			return value
		end
		function state:plate(token, attributes)
			local base = self:frame({}, true)
			local unit = self:frame({}, true)
			data(base).fields.UnitFrame, data(base).unit = unit, token
			data(unit).parent, data(unit).fields.unit, data(unit).fields.showOnlyName = base, token, false
			local function child(parent, key)
				local frame = self:frame({}, true)
				data(frame).parent = parent
				data(parent).fields[key] = frame
				return frame
			end
			local casts = child(unit, "CastBarsContainer")
			local cast = child(casts, "castBar")
			for _, name in ipairs({
				"Icon",
				"BorderShield",
				"Spark",
				"Text",
				"CastTargetNameText",
				"ImportantCastIndicator",
			}) do
				child(cast, name)
			end
			local health = child(unit, "HealthBarsContainer")
			local bar = child(health, "healthBar")
			for _, name in ipairs({ "Text", "LeftText", "RightText", "bgTexture", "selectedBorder" }) do
				child(bar, name)
			end
			local auras = child(unit, "AurasFrame")
			child(auras, "DebuffListFrame")
			for _, name in ipairs({
				"name",
				"RaidTargetFrame",
				"ClassificationFrame",
				"PlayerLevelDiffFrame",
				"overAbsorbGlow",
				"overHealAbsorbGlow",
			}) do
				child(unit, name)
			end
			self.plates[token], self.visible[#self.visible + 1] = base, base
			self.units[token] = attributes or { guid = "Player-1-" .. token, isPlayer = true, isFriend = false }
			return base, unit, cast, bar
		end
		function state:clearMutations()
			self.mutations = {}
		end
		function state:countMutations(method, frame)
			local total = 0
			for _, item in ipairs(self.mutations) do
				if (not method or item.method == method) and (not frame or item.frame == frame) then
					total = total + 1
				end
			end
			return total
		end
		if options.configure then
			options.configure(env, state)
		end
		state:load("Libs/libchev/libchev.lua")
		state:load("Libs/libchev/Debug.lua")
		state:load("Libs/libchev/DebugWindow.lua")
		state:load("Libs/libchev/ReportWindow.lua")
		state:load("Libs/libchev/SelfTests.lua")
		state:load("Core.lua")
		state:load("InGameTests.lua")
		if not options.coreOnly then
			state:load("Nameplates.lua")
		end
		if options.options then
			state:load("Options.lua")
		end
		state.env, state.addon = env, env.PvPTogether
		state.addon:InitializeDatabase()
		return state.addon, state, env
	end
	return H
end
