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
				for _, file in ipairs({
					"libchev.lua",
					"Debug.lua",
					"DebugWindow.lua",
					"ReportWindow.lua",
					"SelfTests.lua",
				}) do
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
			H.truthy(library.DebugController ~= other.LibChev.DebugController)
			local ownController = addon:GetDebugController()
			local otherController = other.LibChev.NewDebugController({})
			ownController:Append("private-local", "STATE")
			H.equal(#otherController:GetEntries(), 0)
			otherController:Append("private-other", "TEST")
			H.falsy(ownController:GetText():find("private-other", 1, true))
			H.falsy(otherController:GetText():find("private-local", 1, true))
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
		H.truthy(addon:RefreshNameplateFrame(base))
		addon:RecordDiagnostic("existing-reason")
		local db, store, log = addon.db, addon.diagnosticCounterStore, addon.diagnosticLog
		local counters, layouts = addon:GetDiagnosticSnapshot(), addon.nameplateStateByFrame
		local mutationCount, frameCount, hookCount, timerCount =
			#state.mutations, #state.frames, #state.hooks, #state.timers
		local ok, passed, failed = addon:RunTests()
		H.truthy(ok)
		H.equal(passed, 15)
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
		H.truthy(Messages(state):find("15 passed, 0 failed", 1, true))
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
		H.truthy(report:find("library=libchev 1.2.0", 1, true))
		H.truthy(report:find("suite=PvPTogether in-game tests", 1, true))
		H.truthy(
			report:find("Addon-owned isolated checks; live-client behavior requires separate validation.", 1, true)
		)
		H.truthy(report:find("15 passed, 0 failed (15 total)", 1, true))
		local _, summaries = report:gsub("Test summary:", "")
		H.equal(summaries, 1)
		H.falsy(report:find("counter.", 1, true))
		H.truthy(#report <= 32768)
		env.SlashCmdList.PVPTOGETHER("test")
		H.equal(addon.diagnosticsWindow, window)
		H.equal(#state.frames, frameCount)
		H.equal(#state.hooks, hookCount)
		H.equal(#state.timers, timerCount)
		H.equal(addon.db, db)
		H.truthy(addon.diagnosticLog)
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
		H.falsy(report:find("FOREIGN_", 1, true))
		H.falsy(Messages(state):find("FOREIGN_", 1, true))
		addon.GetInGameTests = original
		env.SlashCmdList.PVPTOGETHER("test")
		H.equal(addon.diagnosticsWindow, window)
		H.truthy(window.TextBox:GetText():find("15 passed, 0 failed", 1, true))
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
			H.falsy(addon:BuildDiagnosticExport():find("FOREIGN_", 1, true))
		end)
	end

	H.test("shared debug commands filter clear and reuse one console", function()
		local addon, state, env = H.new()
		addon:RegisterSlashCommands()
		addon:RecordDiagnostic("layout-preflight")
		env.SlashCmdList.PVPTOGETHER("debug")
		local window, controller = assert(addon.diagnosticsWindow), addon:GetDebugController()
		H.truthy(window.TextBox:GetText():find("layout-preflight count=1", 1, true))
		H.equal(controller:GetCategory(), "ALL")
		env.SlashCmdList.PVPTOGETHER("test")
		H.equal(controller:GetCategory(), "ALL")
		H.truthy(window.TextBox:GetText():find("15 passed, 0 failed", 1, true))
		H.truthy(window.TextBox:GetText():find("layout-preflight", 1, true))
		env.SlashCmdList.PVPTOGETHER("dump STATE")
		H.equal(controller:GetCategory(), "STATE")
		H.falsy(window.TextBox:GetText():find("15 passed", 1, true))
		controller:SetSearch('"not present"')
		H.equal(window.TextBox:GetText(), "")
		env.SlashCmdList.PVPTOGETHER("runtests")
		H.equal(controller:GetCategory(), "TEST")
		H.equal(controller:GetSearch(), "")
		H.truthy(window.TextBox:GetText():find("15 passed, 0 failed", 1, true))
		env.SlashCmdList.PVPTOGETHER("dump clear")
		H.equal(controller:GetCategory(), "ALL")
		H.equal(window.TextBox:GetText(), "")
		H.equal(addon:GetDiagnosticSnapshot()[1].count, 1)
		H.equal(addon.diagnosticsWindow, window)
		H.equal(state.foreignWrites, 0)
	end)

	H.test("shared console buttons use addon reports and the detached suite", function()
		local addon, state, env = H.new()
		addon:RegisterSlashCommands()
		env.SlashCmdList.PVPTOGETHER("debug")
		local window = assert(addon.diagnosticsWindow)
		local function Click(button)
			state.frameData[button].scripts.OnClick(button)
		end
		Click(window.Buttons.tests)
		H.truthy(window.TextBox:GetText():find("15 passed, 0 failed", 1, true))
		Click(window.Buttons.diagnostics)
		H.equal(window.TextBox:GetText(), addon:BuildDiagnosticExport())
		Click(window.Buttons.log)
		H.truthy(window.TextBox:GetText():find("15 passed, 0 failed", 1, true))
		state:clearMutations()
		state.restricted[env.Enum.AddOnRestrictionType.PvPMatch] = env.Enum.AddOnRestrictionState.Active
		local sequence = addon.diagnosticLog.sequence
		Click(window.Buttons.tests)
		H.equal(addon.diagnosticLog.sequence, sequence)
		H.equal(#state.mutations, 0)
		H.equal(state.foreignWrites, 0)
	end)

	H.test("shared reload button honors the addon restriction policy", function()
		local addon, state, env = H.new({
			configure = function(environment, fixture)
				fixture.reloadCount = 0
				environment.ReloadUI = function()
					fixture.reloadCount = fixture.reloadCount + 1
				end
			end,
		})
		addon:RegisterSlashCommands()
		env.SlashCmdList.PVPTOGETHER("debug")
		local button = assert(addon.diagnosticsWindow).Buttons.reload
		H.truthy(button:IsShown())
		local click = state.frameData[button].scripts.OnClick
		click(button)
		H.equal(state.reloadCount, 1)
		state.allowProtectedFunctions = false
		click(button)
		H.equal(state.reloadCount, 1)
	end)

	H.test("detached self-tests never reuse an inherited live debug controller", function()
		local addon = H.new()
		addon:RecordDiagnostic("live-reason")
		local controller, log = addon:GetDebugController(), addon.diagnosticLog
		local count = #log.entries
		local ok, passed, failed = addon:RunTests()
		H.truthy(ok)
		H.equal(passed, 15)
		H.equal(failed, 0)
		H.equal(addon:GetDebugController(), controller)
		H.equal(addon.diagnosticLog, log)
		H.equal(#log.entries, count)
		H.equal(addon:GetDiagnosticSnapshot()[1].reason, "live-reason")
	end)

	H.test("shared log formatter includes the accessible clock and sequence", function()
		local addon, state = H.new()
		state.now = 12.5
		addon:RecordDiagnostic("clock-first")
		state.now = 13.75
		addon:RecordDiagnostic("clock-second")
		local text = addon:GetDebugController():GetText()
		H.truthy(text:find("[STATE] [12.500 #1] clock-first count=1", 1, true))
		H.truthy(text:find("[STATE] [13.750 #2] clock-second count=1", 1, true))
		H.truthy(addon:BuildDiagnosticExport():find("[STATE] [13.750 #2]", 1, true))
	end)

	H.test("diagnostic clock rejects unavailable secret and nonfinite values", function()
		local addon, state, env = H.new()
		for _, value in ipairs({ state:secretValue(), math.huge, -math.huge, "12", {} }) do
			env.GetTime = function()
				return value
			end
			H.equal(addon:GetDiagnosticTime(), nil)
		end
		env.GetTime = function()
			error("FOREIGN_clock_failure")
		end
		addon:RecordDiagnostic("clock-unavailable")
		H.equal(addon.diagnosticLog.entries[1].elapsed, nil)
		H.falsy(addon:BuildDiagnosticExport():find("FOREIGN_", 1, true))
		env.GetTime = nil
		H.equal(addon:GetDiagnosticTime(), nil)
	end)

	H.test("pure in-game bodies never read the native clock", function()
		local addon, _, env = H.new()
		local calls = 0
		env.GetTime = function()
			calls = calls + 1
			error("in-game self-test read native clock")
		end
		local ok, passed, failed = addon:RunTests()
		H.truthy(ok)
		H.equal(passed, 15)
		H.equal(failed, 0)
		H.equal(calls, 0)
	end)

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
		local report = addon:BuildDiagnosticExport()
		H.truthy(report:find("addon=PvPTogether", 1, true))
		H.truthy(report:find("client.build=69933", 1, true))
		H.truthy(report:find("counter.layout-unavailable=1", 1, true))
		H.truthy(report:find("Recent events:", 1, true))
		H.truthy(report:find("[STATE] [0.000 #1] layout-unavailable count=1", 1, true))
		H.truthy(#report <= 32768)
		H.equal(#state.mutations, 0)
	end)

	H.test("report window opens copies refreshes and reuses addon-owned regions", function()
		local addon, state = H.new()
		addon:PrintDiagnostics()
		local window = assert(addon.diagnosticsWindow, "copy window did not open")
		H.truthy(window:IsShown())
		H.equal(window.TextBox:GetText(), addon:BuildDiagnosticExport())
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
		H.equal(#addon:GetDiagnosticSnapshot(), 0)
		H.falsy(addon:BuildDiagnosticExport():find("FOREIGN_", 1, true))
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
