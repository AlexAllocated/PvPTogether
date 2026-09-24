-- OFFLINE ONLY. This file is deliberately absent from every addon TOC.
-- Run: lua scripts/test.lua [repository-root] [reverse]
-- Every case loads production code into a fresh private Lua environment. No
-- runtime test patches a real Blizzard global, frame, mixin, or saved variable.
local root = arg[1] or "."
local harness = assert(loadfile(root .. "/tests/harness.lua"))()(root)
for _, suite in ipairs({ "core", "nameplates" }) do
	assert(loadfile(root .. "/tests/" .. suite .. ".lua"))()(harness)
end

if arg[2] == "reverse" then
	for index = 1, math.floor(#harness.cases / 2) do
		local opposite = #harness.cases - index + 1
		harness.cases[index], harness.cases[opposite] = harness.cases[opposite], harness.cases[index]
	end
end

local passed, failed = 0, 0
for _, case in ipairs(harness.cases) do
	local ok, err = pcall(case.run)
	if ok then
		passed = passed + 1
	else
		failed = failed + 1
		io.write("FAIL ", case.name, ": ", tostring(err), "\n")
	end
end
io.write(string.format("Offline regressions: %d passed, %d failed (%d total).\n", passed, failed, #harness.cases))
io.write("These fixtures cannot establish live-client taint safety or visual correctness.\n")
os.exit(failed == 0 and 0 or 1)
