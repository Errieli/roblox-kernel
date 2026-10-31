-- Read-only views of the bootstrap state for Kernel.Info and stall warnings.
-- Pure: the facade owns the state and passes it with the current clock.
local Diagnostics = {}

-- Live initializers still holding a phase, sorted by source.
function Diagnostics.Holders(threads, threadSources)
	local holders = {}
	for thread in pairs(threads or {}) do
		local status = coroutine.status(thread)
		if status ~= "dead" then
			holders[#holders + 1] = {
				source = threadSources[thread] or "Unknown",
				status = status,
				trace = debug.traceback(thread),
			}
		end
	end

	table.sort(holders, function(left, right) return left.source < right.source end)
	return holders
end

function Diagnostics.StallWarning(stall)
	local lines = {}
	for _, holder in ipairs(stall.holders) do
		lines[#lines + 1] = string.format("  %s (%s)\n%s", holder.source, holder.status, holder.trace)
	end

	return string.format(
		"Kernel phase %s has waited %.1fs for %d initializer(s):\n%s",
		stall.phase, stall.waited, #stall.holders, table.concat(lines, "\n")
	)
end

local function copyFailures(state)
	local result = {}
	for priority, entries in pairs(state.phaseFailures) do
		local phase = state.phaseName(priority)
		result[phase] = {}
		for index, entry in ipairs(entries) do result[phase][index] = table.clone(entry) end
	end

	return result
end

local function copyStalls(state, now)
	local result = {}
	for priority, stall in pairs(state.phaseStalls) do
		local entry = table.clone(stall)
		if not stall.resolvedAt and not state.bootstrapFailure then
			entry.holders = Diagnostics.Holders(state.waitingThreads[priority], state.threadSources)
			entry.waited = now - stall.since
		else
			entry.holders = {}
			for index, holder in ipairs(stall.holders) do entry.holders[index] = table.clone(holder) end
		end

		result[state.phaseName(priority)] = entry
	end

	return result
end

-- Copy of the bootstrap state; callers can keep or change it freely.
function Diagnostics.Snapshot(state, now)
	local exports = {}
	for name, details in pairs(state.exportInfo) do
		exports[name] = {purpose = details.purpose, dependencies = table.clone(details.dependencies)}
	end

	local phases = {}
	for priority, name in ipairs(state.phaseNames) do
		phases[name] = table.clone(state.phaseStates[priority])
	end

	return {
		environment = state.environment,
		phase = {
			active = state.phaseName(state.activePhase),
			completed = state.phaseName(state.completedPhase),
		},
		phases = phases,
		exports = exports,
		diagnostics = {
			missingDependencies = state.missingDependencies,
			failures = copyFailures(state),
			stalls = copyStalls(state, now),
			stallThreshold = state.stallSeconds,
			bootstrapFailure = state.bootstrapFailure and table.clone(state.bootstrapFailure) or nil,
		},
	}
end

return Diagnostics
