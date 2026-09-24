return function(H)
	local function Messages(state)
		local lines = {}
		for _, message in ipairs(state.messages) do
			lines[#lines + 1] = message[1]
		end
		return table.concat(lines, "\n")
	end

	for _, order in ipairs({ "before", "after" }) do
		local loadOrder = order
		H.test("private LibChev stays isolated when another embed loads " .. loadOrder, function()
			local other = {}
			local function LoadOther(state)
				for _, file in ipairs({ "libchev.lua", "ReportWindow.lua", "SelfTests.lua" }) do
					state:load("Libs/libchev/" .. file, other, "OtherAddon")
				end
			end
			local addon, state, env = H.new({
				configure = function(_, fixture)
					if loadOrder == "before" then
						LoadOther(fixture)
					end
				end,
			})
			local library = addon.LibChev
			if loadOrder == "after" then
				LoadOther(state)
			end
			H.truthy(library ~= other.LibChev)
			H.truthy(library.RunTests ~= other.LibChev.RunTests)
			H.equal(addon.LibChev, library)
			H.equal(addon.Together, nil)
			H.equal(other.Together, nil)
			H.equal(env.LibChev, nil)
			H.equal(env.LibTogether, nil)
			H.equal(env.Together, nil)
		end)
	end

	-- Register the actual TOC-loaded cases, each in a fresh client fixture. These
	-- are the same pure bodies /pt test runs, not copies of their implementations.
	local registration = H.new({ coreOnly = true }):GetInGameTests()
	for index, case in ipairs(registration) do
		local caseIndex = index
		H.test("in-game body / " .. case.name, function()
			local addon = H.new({ coreOnly = true })
			addon:GetInGameTests()[caseIndex].run()
		end)
	end

	H.test("in-game runner preserves live addon stores and frame activity", function()
		local addon, state = H.new()
		local base = state:plate("nameplate1")
		addon.isEnabled, addon.db.enemyPlayerStyle = true, 2
		H.truthy(addon:ReapplyStyleForNameplateFrame(base))
		addon:RecordDiagnostic("existing-reason")
		local db, store, log = addon.db, addon.diagnosticCounterStore, addon.diagnosticLog
		local counters, layouts = addon:GetDiagnosticSnapshot(), addon.nameplateStateByFrame
		local mutationCount, frameCount, hookCount, timerCount =
			#state.mutations, #state.frames, #state.hooks, #state.timers
		local ok, passed, failed = addon:RunTests()
		H.truthy(ok)
		H.equal(passed, 12)
		H.equal(failed, 0)
		H.equal(addon.db, db)
		H.equal(addon.db.enemyPlayerStyle, 2)
		H.equal(addon.diagnosticCounterStore, store)
		H.equal(addon.diagnosticLog, log)
		H.equal(addon.nameplateStateByFrame, layouts)
		H.equal(#log.entries, 1)
		H.equal(#addon:GetDiagnosticSnapshot(), #counters)
		H.equal(addon:GetDiagnosticSnapshot()[1].count, 1)
		H.equal(#state.mutations, mutationCount)
		H.equal(#state.frames, frameCount)
		H.equal(#state.hooks, hookCount)
		H.equal(#state.timers, timerCount)
		H.equal(state.foreignWrites, 0)
		H.truthy(Messages(state):find("12 passed, 0 failed", 1, true))
	end)

	H.test("live test failure reporting withholds raw foreign errors", function()
		local addon, state = H.new()
		addon.GetInGameTests = function()
			return {
				{
					name = "private failure check",
					run = function()
						error("FOREIGN_PlayerName_Player-GUID_nameplate1")
					end,
				},
			}
		end
		local ok, passed, failed = addon:RunTests()
		H.falsy(ok)
		H.equal(passed, 0)
		H.equal(failed, 1)
		H.truthy(Messages(state):find("[FAIL] private failure check", 1, true))
		H.falsy(Messages(state):find("FOREIGN_", 1, true))
		H.equal(addon.diagnosticLog, nil)
	end)

	local function FailSuite(addon)
		addon.GetInGameTests = function()
			return {
				{
					name = "private failure check",
					run = function()
						error("FOREIGN_PlayerName_Player-GUID_nameplate1")
					end,
				},
			}
		end
	end

	H.test("slash test opens current results and reuses the diagnostic window", function()
		local addon, state, env = H.new()
		addon:RegisterSlashCommands()
		addon:PrintDiagnostics()
		local window = assert(addon.diagnosticsWindow)
		local db, frameCount, hookCount, timerCount = addon.db, #state.frames, #state.hooks, #state.timers
		env.SlashCmdList.PVPTOGETHER(" test ")
		local report = window.TextBox:GetText()
		H.truthy(window:IsShown())
		H.truthy(report:find("addon=PvPTogether", 1, true))
		H.truthy(report:find("library=libchev 1.0.0", 1, true))
		H.truthy(report:find("suite=PvPTogether in-game self-tests", 1, true))
		H.truthy(report:find("private values; nameplate simulations run offline", 1, true))
		H.truthy(report:find("12 passed, 0 failed (12 total)", 1, true))
		H.falsy(report:find("counter.", 1, true))
		H.truthy(#report <= 32768)
		env.SlashCmdList.PVPTOGETHER("test")
		H.equal(addon.diagnosticsWindow, window)
		H.equal(#state.frames, frameCount)
		H.equal(#state.hooks, hookCount)
		H.equal(#state.timers, timerCount)
		H.equal(addon.db, db)
		H.equal(addon.diagnosticLog, nil)
		H.equal(state.foreignWrites, 0)
		H.equal(#state.messages, 0)
	end)

	H.test("slash test opens a fresh window and replaces failures on the next run", function()
		local addon, state, env = H.new()
		addon:RegisterSlashCommands()
		local original = addon.GetInGameTests
		FailSuite(addon)
		env.SlashCmdList.PVPTOGETHER("test")
		local window = assert(addon.diagnosticsWindow)
		local report = window.TextBox:GetText()
		H.truthy(report:find("0 passed, 1 failed (1 total)", 1, true))
		H.truthy(report:find("[FAIL] private failure check", 1, true))
		H.truthy(report:find("error details omitted", 1, true))
		H.falsy(report:find("FOREIGN_", 1, true))
		H.falsy(Messages(state):find("FOREIGN_", 1, true))
		addon.GetInGameTests = original
		env.SlashCmdList.PVPTOGETHER("test")
		H.equal(addon.diagnosticsWindow, window)
		H.truthy(window.TextBox:GetText():find("12 passed, 0 failed", 1, true))
		H.falsy(window.TextBox:GetText():find("[FAIL]", 1, true))
	end)

	for _, scenario in ipairs({ "restricted", "native permission", "missing UI", "throwing UI" }) do
		local mode = scenario
		H.test("slash test reports safe failures in chat with " .. mode, function()
			local addon, state, env = H.new()
			addon:RegisterSlashCommands()
			FailSuite(addon)
			if mode == "restricted" then
				state.restricted[env.Enum.AddOnRestrictionType.PvPMatch] = env.Enum.AddOnRestrictionState.Active
			elseif mode == "native permission" then
				state.allowProtectedFunctions = false
			elseif mode == "missing UI" then
				env.CreateFrame = nil
			else
				env.CreateFrame = function()
					error("FOREIGN_UI_FAILURE")
				end
			end
			local frameCount = #state.frames
			env.SlashCmdList.PVPTOGETHER("test")
			local report = Messages(state)
			H.truthy(report:find("addon=PvPTogether", 1, true))
			H.truthy(report:find("0 passed, 1 failed (1 total)", 1, true))
			H.truthy(report:find("[FAIL] private failure check", 1, true))
			H.falsy(report:find("FOREIGN_", 1, true))
			H.equal(addon.diagnosticsWindow, nil)
			H.equal(#state.mutations, 0)
			if mode ~= "native permission" then
				H.equal(#state.frames, frameCount)
			end
			H.falsy(addon:BuildDiagnostics():find("FOREIGN_", 1, true))
		end)
	end

	H.test("static diagnostic sampling keeps bounded log and exact counters", function()
		local addon = H.new()
		for _ = 1, 205 do
			addon:RecordDiagnostic("layout-preflight")
		end
		H.equal(addon:GetDiagnosticSnapshot()[1].count, 205)
		H.equal(#addon.diagnosticLog.entries, 5)
		H.equal(addon.diagnosticLog.entries[4].text, "layout-preflight count=100")
		for i = 1, 23 do
			for _ = 1, 3 do
				addon:RecordDiagnostic("static_" .. i)
			end
		end
		H.equal(#addon.diagnosticLog.entries, 60)
		H.truthy(addon.diagnosticLog.dropped > 0)
		H.truthy(addon.diagnosticLog.chars <= 6000)
	end)

	H.test("secret and invalid diagnostic reasons never enter history", function()
		local addon, state = H.new()
		addon:RecordDiagnostic(state:secretValue())
		addon:RecordDiagnostic("foreign error: Player-Name at nameplate1")
		addon:RecordDiagnostic({})
		H.equal(#addon:GetDiagnosticSnapshot(), 0)
		H.equal(addon.diagnosticLog, nil)
	end)

	H.test("diagnostics use shared headers without live unit reads", function()
		local addon, state, env = H.new()
		local function Unexpected()
			error("diagnostics read live unit identity")
		end
		env.UnitGUID, env.UnitName, env.UnitIsPlayer, env.UnitIsFriend = Unexpected, Unexpected, Unexpected, Unexpected
		addon:RecordDiagnostic("layout-unavailable")
		local report = addon:BuildDiagnostics()
		H.truthy(report:find("addon=PvPTogether", 1, true))
		H.truthy(report:find("client.build=69933", 1, true))
		H.truthy(report:find("counter.layout-unavailable=1", 1, true))
		H.truthy(report:find("event.1=", 1, true))
		H.truthy(#report <= 32768)
		H.equal(#state.mutations, 0)
	end)

	H.test("report window opens copies refreshes and reuses addon-owned regions", function()
		local addon, state = H.new()
		addon:PrintDiagnostics()
		local window = assert(addon.diagnosticsWindow, "copy window did not open")
		H.truthy(window:IsShown())
		H.equal(window.TextBox:GetText(), addon:BuildDiagnostics())
		H.truthy(state.frameData[window.TextBox].focused)
		H.equal(#state.messages, 0)
		local frameCount = #state.frames
		addon:RecordDiagnostic("layout-write")
		addon:PrintDiagnostics()
		H.equal(#state.frames, frameCount)
		H.truthy(window.TextBox:GetText():find("counter.layout-write=1", 1, true))
		H.equal(state.foreignWrites, 0)
	end)

	H.test("restricted diagnostics fall back to chat without frame creation", function()
		local addon, state, env = H.new()
		state.restricted[env.Enum.AddOnRestrictionType.PvPMatch] = env.Enum.AddOnRestrictionState.Active
		local frameCount = #state.frames
		addon:PrintDiagnostics()
		H.equal(addon.diagnosticsWindow, nil)
		H.equal(#state.frames, frameCount)
		H.equal(#state.mutations, 0)
		H.truthy(Messages(state):find("addon=PvPTogether", 1, true))
	end)

	H.test("report creation failure falls back without logging foreign error payload", function()
		local addon, state = H.new({
			configure = function(env, fixture)
				local create = env.CreateFrame
				env.CreateFrame = function(...)
					if fixture.failFrames then
						error("FOREIGN_PlayerName_Player-GUID_nameplate1")
					end
					return create(...)
				end
			end,
		})
		state.failFrames = true
		addon:PrintDiagnostics()
		H.truthy(Messages(state):find("addon=PvPTogether", 1, true))
		H.falsy(Messages(state):find("FOREIGN_", 1, true))
		H.equal(addon:GetDiagnosticSnapshot()[1].reason, "report-window-unavailable")
		H.falsy(addon:BuildDiagnostics():find("FOREIGN_", 1, true))
	end)

	H.test("report window callbacks honor addon native permission policy", function()
		local addon, state = H.new()
		addon:PrintDiagnostics()
		local window = assert(addon.diagnosticsWindow)
		local wheel = state.frameData[window.Scroll].scripts.OnMouseWheel
		state:clearMutations()
		state.allowProtectedFunctions = false
		wheel(window.Scroll, -1)
		H.equal(#state.mutations, 0)
		state.allowProtectedFunctions = true
		wheel(window.Scroll, -1)
		H.equal(window.Scroll:GetVerticalScroll(), 36)
	end)

	H.test("already-open report callbacks stop when runtime restrictions change", function()
		local addon, state, env = H.new()
		addon:PrintDiagnostics()
		local window = assert(addon.diagnosticsWindow)
		local wheel = state.frameData[window.Scroll].scripts.OnMouseWheel
		state:clearMutations()
		state.allowProtectedFunctions = true
		state.restricted[env.Enum.AddOnRestrictionType.Map] = env.Enum.AddOnRestrictionState.Activating
		wheel(window.Scroll, -1)
		H.equal(#state.mutations, 0)
		state.restricted[env.Enum.AddOnRestrictionType.Map] = env.Enum.AddOnRestrictionState.Inactive
		wheel(window.Scroll, -1)
		H.equal(window.Scroll:GetVerticalScroll(), 36)
	end)

	H.test("failed restriction query sends diagnostics to chat without UI writes", function()
		local addon, state = H.new()
		state.queryErrors.restrictions = true
		local count = #state.frames
		addon:PrintDiagnostics()
		H.equal(#state.frames, count)
		H.equal(#state.mutations, 0)
		H.truthy(Messages(state):find("runtimeRestricted=true", 1, true))
	end)
end
