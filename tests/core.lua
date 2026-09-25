return function(H)
	H.test("welcome login announces once routes feedback and tolerates unavailable helpers", function()
		local handler
		local addon, state = H.new({
			coreOnly = true,
			configure = function(env)
				env.LinkUtil = {
					IsLinkHandlerRegistered = function()
						return false
					end,
					RegisterLinkHandler = function(kind, callback)
						H.equal(kind, "pvptogetherfeedback")
						handler = callback
					end,
				}
			end,
		})
		state:emit("PLAYER_LOGIN")
		state:emit("PLAYER_LOGIN")
		H.truthy(addon.hasLoggedIn)
		H.truthy(addon.isEnabled)
		H.equal(#state.messages, 1)
		H.truthy(state.messages[1][1]:find("v1.0.7 loaded!", 1, true))
		H.truthy(state.messages[1][1]:find("Type /pt for settings.", 1, true))
		handler("pvptogetherfeedback:curseforge")
		H.truthy(state.messages[2][1]:find("https://www.curseforge.com/wow/addons/pvptogether", 1, true))
		handler("pvptogetherfeedback:github")
		H.truthy(state.messages[3][1]:find("https://github.com/AlexAllocated/PvPTogether", 1, true))
		-- This library belongs to the offline environment, never a live addon.
		addon.LibChev.NewWelcomeController = nil
		state:emit("PLAYER_LOGIN")
		H.truthy(addon.isEnabled)
		H.equal(#state.messages, 3)
	end)

	H.test("legacy style preferences are preserved but no longer accepted as active settings", function()
		local addon, state = H.new({
			coreOnly = true,
			configure = function(env)
				env.PvPTogetherDBChar = {
					partyMemberStyle = 0,
					friendlyPlayerStyle = 2,
					enemyPlayerStyle = 3,
					styleSeeded = true,
					partyMemberStyleSeeded = true,
				}
				env.NameplatesOverrides.GetNameplateStyleOptions = function()
					error("retired provider invoked")
				end
			end,
		})
		for key, value in pairs({ partyMemberStyle = 0, friendlyPlayerStyle = 2, enemyPlayerStyle = 3 }) do
			H.equal(addon.db[key], value)
			H.falsy(addon:SetOption(key, 4))
			H.falsy(addon:SetOption(key, nil))
			H.equal(addon.db[key], value)
		end
		H.truthy(addon.db.styleSeeded)
		H.equal(#state.cvarWrites, 0)
	end)

	H.test("border settings replace style controls and open the native nameplate category", function()
		local addon, state, env = H.new({ options = true })
		addon.isEnabled = true
		env.Settings.NAMEPLATE_OPTIONS_CATEGORY_ID = 77
		addon:InitializeOptionsWindow()
		for _, kind in ipairs({ "partyMember", "friendlyPlayer", "enemyPlayer" }) do
			H.equal(addon.optionControls[kind .. "Style"], nil)
			H.equal(addon.optionControls[kind .. "Preview"], nil)
			H.truthy(addon.optionControls[kind .. "BorderEnabled"])
			H.truthy(addon.optionControls[kind .. "BorderColor"])
		end
		state.frameData[addon.optionControls.blizzardNameplateSettings].scripts.OnClick()
		H.equal(state.openCategory, 77)
		H.equal(#state.timers, 0)
		H.equal(#state.cvarWrites, 0)
		env.C_NamePlate = nil
		addon:RefreshOptionsWindow()
		H.falsy(state.frameData[addon.optionControls.enemyPlayerBorderEnabled].enabled)
	end)

	H.test("native settings shortcut handles combat unavailable secret and failing APIs", function()
		for _, mode in ipairs({ "combat", "missing", "secret", "error" }) do
			local addon, state, env = H.new({ options = true })
			env.Settings.NAMEPLATE_OPTIONS_CATEGORY_ID = 77
			if mode == "combat" then
				state.combat = true
			elseif mode == "missing" then
				env.Settings = nil
			elseif mode == "secret" then
				env.Settings.NAMEPLATE_OPTIONS_CATEGORY_ID = state:secretValue()
			else
				env.Settings.OpenToCategory = function()
					error("not available")
				end
			end
			H.falsy(addon:OpenBlizzardNameplateSettings())
			H.equal(state.openCategory, nil)
			H.equal(#state.cvarWrites, 0)
		end
	end)

	H.test("diagnostics explain native layout without reporting legacy overrides", function()
		local addon = H.new()
		addon.db.enemyPlayerStyle = 3
		local report = addon:BuildDiagnostics()
		H.truthy(report:find("layout=Blizzard global settings", 1, true))
		H.falsy(report:find("enemyPlayer.style", 1, true))
		H.falsy(report:find("layoutFailure", 1, true))
		H.falsy(report:find("retainedLayouts", 1, true))
	end)

	H.test("fixtures isolate addon globals and saved variables", function()
		local first, firstState, firstEnv = H.new({ coreOnly = true })
		local second, _, secondEnv = H.new({ coreOnly = true })
		first.db.enemyPlayerBorderEnabled = true
		H.equal(second.db.enemyPlayerBorderEnabled, false)
		H.truthy(firstEnv ~= secondEnv)
		H.truthy(firstEnv.PvPTogetherDBChar ~= secondEnv.PvPTogetherDBChar)
		H.equal(rawget(_G, "PvPTogether"), nil)
		H.equal(firstState.foreignWrites, 0)
	end)

	H.test("numbers reject nonfinite and foreign values", function()
		local addon = H.new({ coreOnly = true })
		H.equal(addon:SafeToNumber(math.huge), nil)
		H.equal(addon:SafeToNumber(-math.huge), nil)
		H.equal(addon:SafeToNumber(0 / 0), nil)
		H.equal(addon:SafeToNumber({}), nil)
		H.equal(addon:SafeToNumber(true), nil)
		H.equal(addon:SafeToNumber("0.25"), 0.25)
	end)

	H.test("secret and inaccessible primitives never enter normalization", function()
		local addon, state = H.new({ coreOnly = true })
		local secret = state:secretValue()
		H.equal(addon:SafeToNumber(secret), nil)
		H.equal(addon:SafeToBoolean(secret), nil)
		H.equal(addon:SafeToString(secret, "unavailable"), "unavailable")
		state.inaccessible["2"] = true
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
		addon.ScheduleNameplateRefresh = function()
			scheduled = scheduled + 1
		end
		addon.RefreshNameplates = function()
			direct = direct + 1
		end
		addon.isEnabled = true
		H.truthy(addon:SetOption("enemyPlayerBorderEnabled", true))
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

		H.truthy(addon:CanAccessTable({}))
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
