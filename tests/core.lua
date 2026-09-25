return function(H)
	local function ForeverStyles()
		return {
			{ value = 1, label = "Default" },
			{ value = 0, label = "Large" },
			{ value = 2, label = "Block" },
			{ value = 4, label = "Cast Focus" },
		}
	end

	H.test("all override dropdowns use Forever native choices labels and order", function()
		local addon, state = H.new({
			options = true,
			configure = function(env, fixture)
				env.NameplatesOverrides.GetNameplateStyleOptions = ForeverStyles
				fixture.cvars.nameplateStyle = "1"
				env.PvPTogetherDBChar = { enemyPlayerStyle = 3, styleSeeded = true, partyMemberStyleSeeded = true }
			end,
		})
		addon.isEnabled = true
		addon:InitializeOptionsWindow()
		for _, kind in ipairs({ "partyMember", "friendlyPlayer", "enemyPlayer" }) do
			local menu = {}
			local root = {
				CreateRadio = function(_, label, selected, set, value)
					menu[#menu + 1] = { label = label, value = value, selected = selected, set = set }
				end,
			}
			state.frameData[addon.optionControls[kind .. "Style"]].menu(nil, root)
			H.equal(#menu, 5)
			H.equal(menu[1].label, "Inherit From Global Setting")
			for index, native in ipairs(ForeverStyles()) do
				H.equal(menu[index + 1].value, native.value)
				H.equal(menu[index + 1].label, native.label)
			end
		end
		H.falsy(addon:IsNameplateStyle(3))
		H.falsy(addon:IsNameplateStyle(5))
		H.equal(addon.db.enemyPlayerStyle, nil)
		H.equal(addon:GetConfiguredStyleForUnitKind("enemyPlayer"), 1)
		H.falsy(addon:SetOption("enemyPlayerStyle", 3))
		H.equal(#state.cvarWrites, 0)
		H.equal(state.foreignWrites, 0)
	end)

	H.test("Retail options retain all six supported choices and copy provider labels", function()
		local addon, _, env = H.new({ coreOnly = true })
		H.equal(#addon.nameplateStyleOrder, 6)
		H.truthy(addon:IsNameplateStyle(3))
		H.truthy(addon:IsNameplateStyle(5))
		local options = {
			{ value = 3, label = "Localized health style" },
			{ value = 3, label = "Duplicate" },
			{ value = 6, label = "Native only" },
			{ value = 99, label = "Future renderer" },
			{ value = 2, label = "Localized block style" },
		}
		env.NameplatesOverrides.GetNameplateStyleOptions = function()
			return options
		end
		H.truthy(addon:RefreshNameplateStyleOptions())
		H.equal(#addon.nameplateStyleOrder, 2)
		H.equal(addon.nameplateStyleOrder[1], 3)
		H.equal(addon.nameplateStyleOrder[2], 2)
		H.equal(#options, 5)
		options[1].label, options[1].value = "Changed", 0
		H.equal(addon:GetNameplateStyleLabel(3), "Localized health style")
		H.equal(addon.nameplateStyleOrder[1], 3)
	end)

	H.test("late native settings provider preserves saved choices and activates them after loading", function()
		local addon, state, env = H.new({
			coreOnly = true,
			configure = function(client)
				client.NameplatesOverrides = nil
				client.PvPTogetherDBChar = { enemyPlayerStyle = 4, styleSeeded = true, partyMemberStyleSeeded = true }
			end,
		})
		H.equal(#addon.nameplateStyleOrder, 0)
		H.equal(addon.db.enemyPlayerStyle, 4)
		H.equal(addon:GetConfiguredStyleForUnitKind("enemyPlayer"), 0)
		env.NameplatesOverrides = { GetNameplateStyleOptions = ForeverStyles }
		state:emit("ADDON_LOADED", "Blizzard_SettingsDefinitions_Frame")
		H.equal(#addon.nameplateStyleOrder, 4)
		H.equal(addon:GetConfiguredStyleForUnitKind("enemyPlayer"), 4)
	end)

	H.test("older Retail uses the callback registered on the native global dropdown", function()
		local addon, state = H.new({
			coreOnly = true,
			configure = function(env, fixture)
				local provider = env.NameplatesOverrides.GetNameplateStyleOptions
				env.NameplatesOverrides.GetNameplateStyleOptions = nil
				local setting, category = {}, {}
				local initializers =
					{ { data = { setting = {} } }, { data = { setting = setting, options = provider } } }
				env.Settings.NAMEPLATE_OPTIONS_CATEGORY_ID = 42
				env.Settings.GetSetting = function(variable)
					H.equal(variable, "nameplateStyle")
					return setting
				end
				env.Settings.GetCategory = function(id)
					H.equal(id, 42)
					return category
				end
				env.SettingsPanel = fixture:frame({
					GetLayout = function(_, selected)
						H.equal(selected, category)
						return { initializers = initializers }
					end,
				}, true)
			end,
		})
		H.equal(#addon.nameplateStyleOrder, 6)
		H.equal(addon.nameplateStyleOrder[4], 3)
		H.equal(addon:GetNameplateStyleLabel(3), "Health Focus")
		H.equal(state.foreignWrites, 0)
		H.equal(#state.cvarWrites, 0)
	end)

	H.test("registered dropdown fallback never inspects forbidden settings frames", function()
		local addon, state = H.new({
			coreOnly = true,
			configure = function(env, fixture)
				env.NameplatesOverrides = nil
				env.SettingsPanel = fixture:frame({}, true)
				fixture.frameData[env.SettingsPanel].forbidden = true
				fixture.frameData[env.SettingsPanel].fields.GetLayout = function()
					error("forbidden read")
				end
			end,
		})
		H.equal(#addon.nameplateStyleOrder, 0)
		H.falsy(addon.nameplateStyleOptionsAvailable)
		H.equal(state.foreignWrites, 0)
	end)

	H.test("unreadable native style options fail closed without retaining stale choices", function()
		for _, mode in ipairs({
			"error",
			"secret-table",
			"inaccessible-table",
			"secret-value",
			"secret-label",
			"row",
			"metatable",
		}) do
			local addon, state, env = H.new({ coreOnly = true })
			local options = ForeverStyles()
			local calls = 0
			if mode == "secret-table" then
				state.secret[options] = true
			elseif mode == "inaccessible-table" then
				state.inaccessibleTables[options] = true
			elseif mode == "secret-value" then
				options[2].value = state:secretValue()
			elseif mode == "secret-label" then
				options[2].label = state:secretValue()
			elseif mode == "row" then
				options[2] = false
			elseif mode == "metatable" then
				options[2] = setmetatable({}, {
					__index = function()
						calls = calls + 1
						error("foreign field")
					end,
				})
			end
			env.NameplatesOverrides.GetNameplateStyleOptions = function()
				if mode == "error" then
					error("provider unavailable")
				end
				return options
			end
			H.falsy(addon:RefreshNameplateStyleOptions())
			H.equal(#addon.nameplateStyleOrder, 0)
			H.falsy(addon:IsNameplateStyle(3))
			H.equal(calls, 0)
		end
	end)

	H.test("opening an override menu refreshes native choices and rejects removed selections", function()
		local addon, state, env = H.new({ options = true })
		addon.isEnabled = true
		addon:InitializeOptionsWindow()
		addon.db.enemyPlayerStyle = 3
		env.NameplatesOverrides.GetNameplateStyleOptions = ForeverStyles
		local values = {}
		state.frameData[addon.optionControls.enemyPlayerStyle].menu(nil, {
			CreateRadio = function(_, _, _, _, value)
				values[#values + 1] = value
			end,
		})
		H.equal(#values, 5)
		H.equal(addon:GetConfiguredStyleForUnitKind("enemyPlayer"), addon:GetCurrentGlobalNameplateStyle())
		H.falsy(addon:SetOption("enemyPlayerStyle", 3))
	end)

	H.test("fixtures isolate addon globals and saved variables", function()
		local first, firstState, firstEnv = H.new({ coreOnly = true })
		local second, _, secondEnv = H.new({ coreOnly = true })
		first.db.enemyPlayerStyle = 5
		H.equal(second.db.enemyPlayerStyle, 0)
		H.truthy(firstEnv ~= secondEnv)
		H.truthy(firstEnv.PvPTogetherDBChar ~= secondEnv.PvPTogetherDBChar)
		H.equal(rawget(_G, "PvPTogether"), nil)
		H.equal(firstState.foreignWrites, 0)
	end)

	H.test("style normalization converts numeric strings and fallback to integers", function()
		local addon = H.new({ coreOnly = true })
		H.equal(addon:NormalizeNameplateStyle("2", 0), 2)
		H.equal(addon:NormalizeNameplateStyle("invalid", "3"), 3)
		H.equal(addon:NormalizeNameplateStyle(nil, "invalid"), 0)
		H.equal(addon:NormalizeNameplateStyle(2.49, 0), 2)
		H.equal(addon:NormalizeNameplateStyle(2.5, 0), 3)
	end)

	H.test("numbers reject nonfinite and foreign values", function()
		local addon = H.new({ coreOnly = true })
		H.equal(addon:SafeToNumber(math.huge), nil)
		H.equal(addon:SafeToNumber(-math.huge), nil)
		H.equal(addon:SafeToNumber(0 / 0), nil)
		H.equal(addon:SafeToNumber({}), nil)
		H.equal(addon:SafeToNumber(true), nil)
		H.equal(addon:SafeToNumber("0.25"), 0.25)
		H.equal(addon:NormalizeNameplateStyle(math.huge, 4), 4)
	end)

	H.test("secret and inaccessible primitives never enter normalization", function()
		local addon, state = H.new({ coreOnly = true })
		local secret = state:secretValue()
		H.equal(addon:SafeToNumber(secret), nil)
		H.equal(addon:SafeToBoolean(secret), nil)
		H.equal(addon:SafeToString(secret, "unavailable"), "unavailable")
		state.inaccessible["2"] = true
		H.equal(addon:NormalizeNameplateStyle("2", 4), 4)
	end)

	H.test("failed secret query fails closed", function()
		local addon, state = H.new({ coreOnly = true })
		state.queryErrors.issecretvalue = true
		H.truthy(addon:IsSecretValue(2))
		H.falsy(addon:CanAccessValue(2))
		H.equal(addon:SafeToNumber(2), nil)
	end)

	H.test("failed value access query fails closed", function()
		local addon, state = H.new({ coreOnly = true })
		state.queryErrors.canaccessvalue = true
		H.falsy(addon:CanAccessValue("safe-looking"))
		H.equal(addon:SafeToString("safe-looking", "fallback"), "")
	end)

	H.test("table access gate precedes field reads", function()
		local addon, state = H.new({ coreOnly = true })
		local reads = 0
		local foreign = setmetatable({}, {
			__index = function()
				reads = reads + 1
				error("should never read")
			end,
		})
		state.inaccessibleTables[foreign] = true
		local value, readable = addon:SafeGetField(foreign, "value")
		H.equal(value, nil)
		H.falsy(readable)
		H.equal(reads, 0)
		state.inaccessibleTables[foreign] = nil
		state.queryErrors.canaccesstable = true
		H.falsy(addon:CanAccessTable(foreign))
		H.equal(reads, 0)
	end)

	H.test("field access distinguishes absent from unreadable", function()
		local addon, state = H.new({ coreOnly = true })
		local value, readable = addon:SafeGetField({}, "absent")
		H.equal(value, nil)
		H.truthy(readable)
		value, readable = addon:SafeGetField({ value = state:secretValue() }, "value")
		H.equal(value, nil)
		H.falsy(readable)
		value, readable = addon:SafeGetField(
			setmetatable({}, {
				__index = function()
					error("denied")
				end,
			}),
			"value"
		)
		H.equal(value, nil)
		H.falsy(readable)
	end)

	H.test("diagnostic conversion never invokes foreign tostring", function()
		local addon = H.new({ coreOnly = true })
		local calls = 0
		local foreign = setmetatable({}, {
			__tostring = function()
				calls = calls + 1
				error("foreign tostring")
			end,
		})
		H.equal(addon:SafeToString(foreign, "unknown"), "unknown")
		H.equal(calls, 0)
		H.equal(addon:SafeToString(false), "false")
	end)

	H.test("boolean normalization refuses truthy non-booleans", function()
		local addon = H.new({ coreOnly = true })
		H.equal(addon:SafeToBoolean(true), true)
		H.equal(addon:SafeToBoolean(false), false)
		H.equal(addon:SafeToBoolean(1), nil)
		H.equal(addon:SafeToBoolean("false"), nil)
		H.falsy(addon:SetOption("enabled", "false"))
		H.equal(addon.db.enabled, true)
	end)

	H.test("combat access errors conservatively restrict mutation", function()
		local addon, state = H.new({ coreOnly = true })
		H.falsy(addon:IsInCombatLockdown())
		state.queryErrors.InCombatLockdown = true
		H.truthy(addon:IsInCombatLockdown())
	end)

	H.test("secret combat result conservatively restricts mutation", function()
		local addon, state = H.new({ coreOnly = true })
		state.combat = state:secretValue()
		H.truthy(addon:IsInCombatLockdown())
	end)

	H.test("unreadable or malformed combat API is not treated as legacy absence", function()
		local addon, state, env = H.new({ coreOnly = true })
		state.secret[env.InCombatLockdown] = true
		H.truthy(addon:IsInCombatLockdown())
		state.secret[env.InCombatLockdown] = nil
		env.InCombatLockdown = false
		H.truthy(addon:IsInCombatLockdown())
		env.InCombatLockdown = nil
		H.falsy(addon:IsInCombatLockdown())
	end)

	H.test("CVar failures use safe global style fallback", function()
		local addon, state = H.new({ coreOnly = true })
		state.queryErrors.cvar = true
		H.equal(addon:GetCurrentGlobalNameplateStyle(), 0)
		state.queryErrors.cvar = nil
		state.cvars.nameplateStyle = state:secretValue()
		H.equal(addon:GetCurrentGlobalNameplateStyle(), 0)
	end)

	H.test("color normalization clamps values and repairs invalid components", function()
		local addon, state = H.new({ coreOnly = true })
		local color = addon:NormalizeColorRGB({ r = -4, g = 3, b = "0.2" }, { r = 0, g = 0, b = 0 })
		H.equal(color.r, 0)
		H.equal(color.g, 1)
		H.equal(color.b, 0.2)
		color = addon:NormalizeColorRGB(
			{ r = math.huge, g = 0 / 0, b = state:secretValue() },
			{ r = 0.1, g = 0.2, b = 0.3 }
		)
		H.equal(color.r, 0.1)
		H.equal(color.g, 0.2)
		H.equal(color.b, 0.3)
	end)

	H.test("inaccessible color table uses copied defaults without reads", function()
		local addon, state = H.new({ coreOnly = true })
		local fallback = { r = 0.1, g = 0.2, b = 0.3 }
		local foreign = setmetatable({}, {
			__index = function()
				error("inaccessible color indexed")
			end,
		})
		state.inaccessibleTables[foreign] = true
		local color = addon:NormalizeColorRGB(foreign, fallback)
		H.equal(color.r, 0.1)
		H.equal(color.g, 0.2)
		H.equal(color.b, 0.3)
		H.truthy(color ~= fallback)
	end)

	H.test("options own their copied color values", function()
		local addon = H.new({ coreOnly = true })
		local supplied = { r = 0.2, g = 0.3, b = 0.4 }
		H.truthy(addon:SetOption("enemyPlayerBorderColor", supplied))
		supplied.r = 1
		H.equal(addon.db.enemyPlayerBorderColor.r, 0.2)
		H.falsy(addon:SetOption("enemyPlayerBorderColor", { r = 0.2001, g = 0.3, b = 0.4 }))
	end)

	H.test("unknown options cannot extend saved settings", function()
		local addon = H.new({ coreOnly = true })
		H.falsy(addon:SetOption("foreignFlag", true))
		H.equal(addon.db.foreignFlag, nil)
	end)

	H.test("settings refresh is coalesced instead of a synchronous mutation", function()
		local addon = H.new({ coreOnly = true })
		local scheduled, direct = 0, 0
		addon.ScheduleReapplyAllNameplateStyles = function()
			scheduled = scheduled + 1
		end
		addon.ReapplyAllNameplateStyles = function()
			direct = direct + 1
		end
		addon.isEnabled = true
		H.truthy(addon:SetOption("enemyPlayerStyle", 2))
		H.equal(scheduled, 1)
		H.equal(direct, 0)
	end)

	H.test("missing secret APIs retain legacy-client primitive behavior", function()
		local addon = H.new({
			coreOnly = true,
			configure = function(env)
				env.issecretvalue, env.canaccessvalue, env.canaccesstable = nil, nil, nil
			end,
		})
		H.equal(addon:NormalizeNameplateStyle("4", "1"), 4)
		H.truthy(addon:CanAccessTable({}))
	end)

	H.test("Forever native Classic style survives inheritance without becoming an override", function()
		local addon, state = H.new({
			coreOnly = true,
			configure = function(env, state)
				env.Enum.NamePlateStyle.Classic = 6
				state.cvars.nameplateStyle = "6"
			end,
		})
		H.equal(addon:GetCurrentGlobalNameplateStyle(), 6)
		H.equal(addon:NormalizeNameplateStyle(nil, 6), 6)
		H.falsy(addon:IsNameplateStyle(6))
		for _, kind in ipairs({ "partyMember", "friendlyPlayer", "enemyPlayer" }) do
			H.equal(addon:GetOption(kind .. "Style"), nil)
		end
		H.truthy(addon.db.styleSeeded)
		H.truthy(addon.db.partyMemberStyleSeeded)
		state.cvars.nameplateStyle = "3"
		addon:InitializeDatabase()
		H.equal(addon.db.enemyPlayerStyle, nil)
		H.equal(addon:GetConfiguredStyleForUnitKind("enemyPlayer"), 3)
	end)

	H.test("diagnostics have bounded keys and bounded counter values", function()
		local addon, state = H.new({ coreOnly = true })
		for index = 1, 40 do
			addon:RecordDiagnostic("reason_" .. index)
		end
		addon:RecordDiagnostic("contains player name or arbitrary data")
		addon:RecordDiagnostic(string.rep("a", 49))
		addon:RecordDiagnostic(state:secretValue())
		H.equal(#addon:GetDiagnosticSnapshot(), 24)
		for _ = 1, 100010 do
			addon:RecordDiagnostic("reason_1")
		end
		local counters = addon:GetDiagnosticSnapshot()
		H.equal(counters[1].reason, "reason_1")
		H.equal(counters[1].count, 99999)
	end)

	H.test("diagnostic snapshots are detached from internal counters", function()
		local addon = H.new({ coreOnly = true })
		addon:RecordDiagnostic("unavailable")
		local snapshot = addon:GetDiagnosticSnapshot()
		snapshot[1].count, snapshot[1].reason = 123, "changed"
		local second = addon:GetDiagnosticSnapshot()
		H.equal(second[1].reason, "unavailable")
		H.equal(second[1].count, 1)
	end)

	H.test("stopped preview timer cannot restart work after re-enable", function()
		local addon, state = H.new({ coreOnly = true, options = true })
		addon.optionsFrame = state:frame({}, false)
		addon.isEnabled = true
		local refreshes = 0
		addon.RandomizeOptionsPreviewClasses = function()
			refreshes = refreshes + 1
		end
		addon.RefreshOptionsPreviewsOnly = function() end
		addon:StartOptionsPreviewTicker()
		local oldCallback = assert(state.timers[1], "preview timer was not created").callback
		addon:StopOptionsPreviewTicker()
		addon:StartOptionsPreviewTicker()
		oldCallback()
		H.equal(refreshes, 0)
		state.timers[#state.timers].callback()
		H.equal(refreshes, 1)
	end)

	H.test("disable invalidates color picker callbacks and stops preview", function()
		local addon, state = H.new({ coreOnly = true, options = true })
		addon.optionsFrame = state:frame({}, false)
		addon.isEnabled = true
		addon:StartOptionsPreviewTicker()
		local timer = assert(state.timers[1])
		local generation = addon.optionsCallbackGeneration or 0
		addon:Disable()
		H.truthy(timer.cancelled)
		H.truthy(addon.optionsCallbackGeneration > generation)
		H.equal(addon.optionsPreviewTicker, nil)
	end)

	H.test("modern settings panel initializes and gates unavailable style capability", function()
		local addon, state, env = H.new({ options = true })
		addon.isEnabled = true
		addon:InitializeOptionsWindow()
		H.truthy(addon.optionsFrame)
		local controls = addon.optionControls
		H.truthy(state.frameData[controls.enemyPlayerStyle].menu)
		H.truthy(state.frameData[controls.enemyPlayerStyle].enabled)
		env.NamePlateSetupOptions.useClassicHealthBar = true
		addon:RefreshOptionsWindow()
		H.falsy(state.frameData[controls.enemyPlayerStyle].enabled)
		H.truthy(state.frameData[controls.enemyPlayerBorderEnabled].enabled)
		H.equal(state.foreignWrites, 0)
	end)

	H.test("stale color picker callbacks cannot change settings after disable and re-enable", function()
		local addon, state = H.new({ options = true })
		addon.hasLoggedIn = true
		addon:Enable()
		addon:InitializeOptionsWindow()
		local swatch = addon.optionControls.enemyPlayerBorderColor
		state.frameData[swatch].scripts.OnClick()
		local picker = assert(state.picker)
		picker.swatchFunc()
		H.equal(addon.db.enemyPlayerBorderColor.r, 0.2)
		addon:Disable()
		addon:Enable()
		state.pickerColor = { 0.8, 0.7, 0.6 }
		picker.swatchFunc()
		picker.cancelFunc()
		H.equal(addon.db.enemyPlayerBorderColor.r, 0.2)
		H.equal(addon.db.enemyPlayerBorderColor.g, 0.3)
	end)

	H.test("reset button invalidates an already open color picker", function()
		local addon, state = H.new({ options = true })
		addon.isEnabled = true
		addon:InitializeOptionsWindow()
		local controls = addon.optionControls
		state.frameData[controls.enemyPlayerBorderColor].scripts.OnClick()
		local picker = assert(state.picker)
		picker.swatchFunc()
		state.frameData[controls.resetEnemyPlayerBorderColor].scripts.OnClick()
		picker.swatchFunc()
		picker.cancelFunc()
		H.equal(addon.db.enemyPlayerBorderColor.r, 1)
		H.equal(addon.db.enemyPlayerBorderColor.g, 0)
		H.equal(addon.db.enemyPlayerBorderColor.b, 0)
	end)

	H.test("secret picker color is rejected without modifying saved settings", function()
		local addon, state = H.new({ options = true })
		addon.isEnabled = true
		addon:InitializeOptionsWindow()
		state.frameData[addon.optionControls.enemyPlayerBorderColor].scripts.OnClick()
		state.pickerColor = { state:secretValue(), 0.2, 0.3 }
		state.picker.swatchFunc()
		H.equal(addon.db.enemyPlayerBorderColor.r, 1)
		H.equal(addon.db.enemyPlayerBorderColor.g, 0)
		H.equal(addon.db.enemyPlayerBorderColor.b, 0)
	end)

	H.test("border toggle invalidates a picker across off and on", function()
		local addon, state = H.new({ options = true })
		addon.isEnabled = true
		addon:SetOption("enemyPlayerBorderEnabled", true)
		addon:InitializeOptionsWindow()
		state.frameData[addon.optionControls.enemyPlayerBorderColor].scripts.OnClick()
		local picker = assert(state.picker)
		addon:SetOption("enemyPlayerBorderEnabled", false)
		addon:SetOption("enemyPlayerBorderEnabled", true)
		picker.swatchFunc()
		picker.cancelFunc()
		H.equal(addon.db.enemyPlayerBorderColor.r, 1)
		H.equal(addon.db.enemyPlayerBorderColor.g, 0)
	end)

	H.test("temporarily unavailable Settings API can initialize on later retry", function()
		local addon, _, env = H.new({ options = true })
		local settings = env.Settings
		env.Settings = nil
		addon:InitializeOptionsWindow()
		H.equal(addon.optionsFrame, nil)
		env.Settings = settings
		addon:InitializeOptionsWindow()
		H.truthy(addon.optionsFrame)
		H.truthy(addon.optionsCategory)
	end)
end
