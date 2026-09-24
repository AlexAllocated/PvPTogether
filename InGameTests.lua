-- Safe in-game checks only. Offline nameplate simulations remain in tests/.
local PvPTogether = _G.PvPTogether
local LibChev = PvPTogether.LibChev

function PvPTogether:GetInGameTests()
	local cases = LibChev.SelfTests()
	cases[#cases + 1] = {
		name = "PvPTogether: color normalization copies private values",
		run = function()
			local fixture = setmetatable({}, { __index = PvPTogether })
			local input = { r = 2, g = -1, b = 0.5 }
			local color = fixture:NormalizeColorRGB(input, { r = 0, g = 0, b = 0 })
			LibChev.AssertEqual(color.r, 1)
			LibChev.AssertEqual(color.g, 0)
			LibChev.AssertEqual(color.b, 0.5)
			LibChev.AssertEqual(input.r, 2)
			assert(color ~= input)
		end,
	}
	cases[#cases + 1] = {
		name = "PvPTogether: diagnostic counters stay on detached fixtures",
		run = function()
			local fixture = setmetatable(
				{ diagnosticCounterStore = LibChev.NewCounters(), diagnosticLog = LibChev.NewLog() },
				{ __index = PvPTogether }
			)
			fixture:RecordDiagnostic("fixture-reason")
			local snapshot = fixture:GetDiagnosticSnapshot()
			LibChev.AssertEqual(#snapshot, 1)
			LibChev.AssertEqual(snapshot[1].count, 1)
		end,
	}
	return cases
end

-- Presentation is explicit: programmatic callers stay headless by default.
function PvPTogether:RunTests(showReport)
	local result = LibChev.RunTests(self:GetInGameTests())
	local purpose = "In-game checks use private values; nameplate simulations run offline."
	local report = showReport == true and self:NewDiagnosticReport() or nil
	if report then
		report:Add("suite", "PvPTogether in-game self-tests")
		report:Add("purpose", purpose)
		report:Add("summary", LibChev.TestSummary(result))
	end
	for index, failure in ipairs(result.failures) do
		-- Names come from our static registrations. Never include failure.error.
		local line = "[FAIL] " .. failure.name .. " (error details omitted; run offline tests for debugging)"
		if report then
			report:Add("failure." .. index, line)
		else
			self:Print(line)
		end
	end
	if report then
		self:ShowDiagnosticReport(report:Text())
	else
		self:Print(LibChev.TestSummary(result))
		self:Print(purpose)
	end
	return result.failed == 0, result.passed, result.failed
end
