local RunService = game:GetService("RunService")
local ScriptContext = game:GetService("ScriptContext")
local Task = require(script._Task)

local PHASES = {
	Preload = 1,
	Shared = 2,
	Runtime = 3,
	Ready = 4,
}
local PHASE_NAMES = {"Preload", "Shared", "Runtime", "Ready"}
local PHASE_COUNT = #PHASE_NAMES

local hidden = {}
local meta = {}
local exportInfo = {}
local calls = {}
local waitingThreads = {}
local sourcePhases = {}
local threadPhases = setmetatable({}, {__mode = "k"})
local bootstrapFailure
local errorConnection
local failPhase
local phaseStates = {}
local phaseFailures = {}
local lateYields = {}
local activePhase = 0
local completedPhase = 0
local bootstrapStartedAt = os.clock()

for priority = 1, PHASE_COUNT do
	calls[priority] = {}
	waitingThreads[priority] = {}
	phaseFailures[priority] = {}
	phaseStates[priority] = {
		status = "Pending",
		startedAt = nil,
		completedAt = nil,
		callbackCount = 0,
	}
end

local function environment()
	if RunService:IsServer() then return "Server" end
	if RunService:IsClient() then return "Client" end
	return "Shared"
end

local runtimeEnvironment = environment()

local function phaseName(priority)
	return PHASE_NAMES[priority] or "Bootstrap"
end

local function resolvePhase(phase)
	if typeof(phase) == "string" then
		local priority = PHASES[phase]
		if priority then return priority end
		error("Unknown Kernel phase: " .. phase, 3)
	end
	if typeof(phase) ~= "number" or phase % 1 ~= 0 or phase < 1 or phase > PHASE_COUNT then
		error("Invalid Kernel phase: " .. tostring(phase), 3)
	end
	return phase
end

local function sourceName()
	local kernelSource = debug.info(1, "s")
	for level = 2, 14 do
		local success, source = pcall(debug.info, level, "s")
		if not success then break end
		if source and source ~= kernelSource and source ~= "[C]" then return source end
	end
	return "Unknown"
end

local function copyArray(values)
	local result = {}
	if typeof(values) ~= "table" then return result end
	for index, value in ipairs(values) do result[index] = value end
	return result
end

local function countMap(values)
	local count = 0
	if values then
		for _ in pairs(values) do count += 1 end
	end
	return count
end

local function trackRegistrationThread()
	local thread = coroutine.running()
	if thread and calls[PHASES.Preload] then
		waitingThreads[PHASES.Preload][thread] = true
		sourcePhases[sourceName()] = PHASES.Preload
	end
end

local function register(name, value, metadata)
	if bootstrapFailure then error(bootstrapFailure.message, 3) end
	assert(typeof(name) == "string" and name ~= "", "Kernel export name must be a non-empty string")
	assert(value ~= nil, "Kernel export value is required: " .. name)
	assert(rawget(hidden, name) == nil, "Duplicate Kernel export: " .. name)
	assert(typeof(metadata) == "table", "Kernel export metadata is required: " .. name)
	assert(typeof(metadata.purpose) == "string" and metadata.purpose ~= "", "Kernel export purpose is required: " .. name)

	local dependencies = metadata.dependencies
	if dependencies == nil then dependencies = {} end
	assert(typeof(dependencies) == "table", "Kernel dependencies must be a table: " .. name)
	dependencies = copyArray(dependencies)
	for _, dependency in ipairs(dependencies) do
		assert(typeof(dependency) == "string" and dependency ~= "", "Invalid Kernel dependency for " .. name)
	end

	trackRegistrationThread()
	rawset(hidden, name, value)
	exportInfo[name] = {
		name = name,
		purpose = metadata.purpose,
		dependencies = dependencies,
		environment = runtimeEnvironment,
		phase = phaseName(activePhase),
		source = sourceName(),
		definedAt = os.clock(),
	}

	return value
end

function hidden.Define(definition)
	assert(typeof(definition) == "table", "Kernel.Define expects a definition table")
	return register(definition.name, definition.value, {
		purpose = definition.purpose,
		dependencies = definition.dependencies,
	})
end

local function recordLateYield(priority, kind)
	lateYields[#lateYields + 1] = {
		phase = phaseName(priority),
		kind = kind,
		source = sourceName(),
		occurredAt = os.clock(),
		completedPhase = phaseName(completedPhase),
	}
	if #lateYields > 64 then table.remove(lateYields, 1) end
end

local function recordFailure(priority, source, message)
	local list = phaseFailures[priority]
	list[#list + 1] = {
		source = source,
		message = tostring(message),
		occurredAt = os.clock(),
	}
end

local function removeWaitingThread(thread, throughPriority)
	for priority = 1, throughPriority do
		local threads = waitingThreads[priority]
		if threads then threads[thread] = nil end
	end
end

local function scheduleCallable(priority, callable, registry, source)
	local callableType = typeof(callable)
	sourcePhases[source] = priority
	local worker = Task.Defer(function()
		local success, message
		if callableType == "thread" then
			-- Engine resumption preserves require/Invoke continuations. Raw resume
			-- can finish a ModuleScript while leaving its requiring script suspended.
			Task.Spawn(callable)
			success = true -- Thread errors are observed by ScriptContext.Error below.
		else
			success, message = xpcall(callable, debug.traceback)
		end
		if not success and not bootstrapFailure then
			local failedPriority = threadPhases[coroutine.running()] or priority
			recordFailure(failedPriority, source, message)
			failPhase(failedPriority, tostring(message))
		end
	end)
	registry[worker] = true
	threadPhases[worker] = priority
	if callableType == "thread" then
		registry[callable] = true
		threadPhases[callable] = priority
	end
	return worker
end

-- Yield enters a phase after all earlier phases complete. It does not wait for
-- other work in the same phase. Callback initializers stay tracked across waits.
function hidden.Yield(phase, callable)
	local priority = resolvePhase(phase)
	if bootstrapFailure then error(bootstrapFailure.message, 2) end
	local state = phaseStates[priority]

	if callable ~= nil then
		local callableType = typeof(callable)
		assert(callableType == "function" or callableType == "thread", "Kernel.Yield callable must be a function or thread")
		local phaseCalls = calls[priority]
		if phaseCalls then
			phaseCalls[#phaseCalls + 1] = {callable = callable, source = sourceName()}
		elseif state.status == "Running" then
			scheduleCallable(priority, callable, waitingThreads[priority], sourceName())
		else
			recordLateYield(priority, "Callback")
			Task.Defer(callable)
		end
		return
	end

	local thread = coroutine.running()
	assert(thread, "Kernel.Yield cannot pause outside a coroutine")
	local phaseCalls = calls[priority]
	if phaseCalls then
		removeWaitingThread(thread, priority)
		phaseCalls[#phaseCalls + 1] = {callable = thread, source = sourceName(), waiting = true}
		local success, message = coroutine.yield()
		if success == false then error(message, 2) end
		return
	end

	if state.status == "Running" then
		if priority == activePhase then
			waitingThreads[priority][thread] = true
			threadPhases[thread] = priority
			sourcePhases[sourceName()] = priority
		end
		return
	end

	recordLateYield(priority, "Blocking")
end

local function collectMissingDependencies()
	local result = {}
	for name, details in pairs(exportInfo) do
		local missing = {}
		for _, dependency in ipairs(details.dependencies) do
			if rawget(hidden, dependency) == nil then missing[#missing + 1] = dependency end
		end
		if #missing > 0 then result[name] = missing end
	end
	return result
end

local function copyFailures()
	local result = {}
	for priority, entries in pairs(phaseFailures) do
		local phase = phaseName(priority)
		result[phase] = {}
		for index, entry in ipairs(entries) do result[phase][index] = table.clone(entry) end
	end
	return result
end

function hidden.Info()
	local exports = {}
	for name, details in pairs(exportInfo) do
		exports[name] = {
			name = details.name,
			purpose = details.purpose,
			dependencies = copyArray(details.dependencies),
			environment = details.environment,
			phase = details.phase,
			source = details.source,
			definedAt = details.definedAt,
		}
	end

	local phases = {}
	for priority, name in ipairs(PHASE_NAMES) do
		local state = phaseStates[priority]
		phases[name] = {
			status = state.status,
			callbacks = calls[priority] and #calls[priority] or 0,
			threads = countMap(waitingThreads[priority]),
			callbackCount = state.callbackCount,
			startedAt = state.startedAt,
			completedAt = state.completedAt,
			failure = state.failure,
		}
	end

	local late = {}
	for index, entry in ipairs(lateYields) do late[index] = table.clone(entry) end

	return {
		environment = runtimeEnvironment,
		phase = {
			active = phaseName(activePhase),
			completed = phaseName(completedPhase),
			index = activePhase,
		},
		phases = phases,
		exports = exports,
		diagnostics = {
			missingDependencies = collectMissingDependencies(),
			lateYields = late,
			failures = copyFailures(),
			bootstrapFailure = bootstrapFailure and table.clone(bootstrapFailure) or nil,
		},
		bootstrap = {startedAt = bootstrapStartedAt},
	}
end

function meta:__index(index)
	return rawget(hidden, index)
end

function meta:__newindex(index)
	error("Can not modify Kernel export: " .. tostring(index), 2)
end

function meta:__call(name, value, metadata)
	if value == nil then value = {} end
	if metadata == nil then
		metadata = {purpose = "Legacy Kernel export without declared purpose."}
		warn("Kernel export registered without metadata: " .. tostring(name))
	end
	return register(name, value, metadata)
end

local function registerBuiltin(name, value, purpose, source)
	rawset(hidden, name, value)
	exportInfo[name] = {
		name = name,
		purpose = purpose,
		dependencies = {},
		environment = runtimeEnvironment,
		phase = "Bootstrap",
		source = source,
		definedAt = os.clock(),
	}
end

registerBuiltin("Task", Task, "Schedules visible asynchronous work and cancellation.", script._Task:GetFullName())
registerBuiltin("Beat", require(script._Beat), "Connects callbacks to Roblox simulation and render signals.", script._Beat:GetFullName())
registerBuiltin("Class", require(script._Class), "Creates lightweight classes with constructor and destructor lifecycle.", script._Class:GetFullName())
registerBuiltin("Utils", require(script._Utils), "Lazily resolves shared utility modules.", script._Utils:GetFullName())
registerBuiltin("Events", require(script._Events), "Coordinates transient, synchronous, and retained local events.", script._Events:GetFullName())
registerBuiltin("Players", require(script._Players), "Observes the live player collection.", script._Players:GetFullName())
registerBuiltin("Multiplier", require(script._Multiplier), "Combines named multiplier sources and change signals.", script._Multiplier:GetFullName())
registerBuiltin("Recycle", require(script._Recycle), "Collects runtime resources for deterministic cleanup.", script._Recycle:GetFullName())
registerBuiltin("Configs", require(script._Configs), "Lazily resolves and caches configuration modules.", script._Configs:GetFullName())
registerBuiltin("Assets", require(script._Assets), "Lazily maps replicated game assets.", script._Assets:GetFullName())


local function waitForThreads(threads)
	while threads and not bootstrapFailure do
		local thread = next(threads)
		if not thread then break end
		if coroutine.status(thread) == "dead" then
			threads[thread] = nil
		else
			Task.Wait()
		end
	end
end

failPhase = function(priority, message)
	if bootstrapFailure then return end
	message = string.format("Kernel phase %s failed: %s", phaseName(priority), message)
	bootstrapFailure = {phase = phaseName(priority), message = message, occurredAt = os.clock()}
	if errorConnection then
		errorConnection:Disconnect()
		errorConnection = nil
	end

	local pendingThreads = {}
	for index = priority, PHASE_COUNT do
		local state = phaseStates[index]
		state.status = "Failed"
		state.failure = message
		state.completedAt = os.clock()
		for _, entry in ipairs(calls[index] or {}) do
			if entry.waiting then
				pendingThreads[entry.callable] = true
			elseif typeof(entry.callable) == "thread" then
				Task.Cancel(entry.callable)
			end
		end
		calls[index] = nil
	end

	local current = coroutine.running()
	for index = 1, PHASE_COUNT do
		local threads = waitingThreads[index]
		for thread in pairs(threads or {}) do
			if thread ~= current and not pendingThreads[thread] then Task.Cancel(thread) end
		end
		waitingThreads[index] = nil
	end
	for thread in pairs(pendingThreads) do
		if coroutine.status(thread) == "suspended" then Task.Defer(thread, false, message) end
	end
	warn(message)
end

-- Engine waits may resume script coroutines outside the first coroutine.resume.
-- Observe only registered initialization sources, then disconnect after Ready.
errorConnection = ScriptContext.Error:Connect(function(message, trace, origin)
	if bootstrapFailure or completedPhase == PHASE_COUNT then return end
	local originName = origin and origin:GetFullName()
	local priority = originName and sourcePhases[originName]
	local matchedSource = originName
	if not priority and (not origin or not origin:IsA("BaseScript")) then
		local nearest
		for source, phase in pairs(sourcePhases) do
			local position = source ~= "Unknown" and string.find(trace, source, 1, true)
			if position and (not nearest or position < nearest) then
				nearest = position
				priority = phase
				matchedSource = source
			end
		end
	end
	if not priority then return end

	recordFailure(priority, matchedSource, message .. "\n" .. trace)
	failPhase(priority, message)
end)

local function runPhase(priority)
	if priority > PHASE_COUNT or bootstrapFailure then return end

	activePhase = priority
	local state = phaseStates[priority]
	waitForThreads(waitingThreads[priority])
	if bootstrapFailure then return end

	local phaseCalls = calls[priority] or {}
	calls[priority] = nil
	local running = {}
	waitingThreads[priority] = running

	state.status = "Running"
	state.startedAt = os.clock()
	state.callbackCount = #phaseCalls

	for _, entry in ipairs(phaseCalls) do
		scheduleCallable(priority, entry.callable, running, entry.source)
	end
	waitForThreads(running)
	if bootstrapFailure then return end
	waitingThreads[priority] = nil

	if priority == PHASE_COUNT then
		local missing = collectMissingDependencies()
		if next(missing) then
			local unresolved = {}
			for name, dependencies in pairs(missing) do
				unresolved[#unresolved + 1] = name .. " -> " .. table.concat(dependencies, ", ")
			end
			table.sort(unresolved)
			local message = "Unresolved dependencies: " .. table.concat(unresolved, "; ")
			recordFailure(priority, script:GetFullName(), message)
			failPhase(priority, message)
			return
		end
	end

	completedPhase = priority
	state.status = "Completed"
	state.completedAt = os.clock()

	if priority < PHASE_COUNT then
		Task.Defer(runPhase, priority + 1)
	elseif errorConnection then
		errorConnection:Disconnect()
		errorConnection = nil
		table.clear(sourcePhases)
	end
end

-- Pure facade exports are available immediately. Project phases retain their
-- existing guarantee that the initial replicated game tree is available.
Task.Defer(function()
	if RunService:IsClient() and not game:IsLoaded() then game.Loaded:Wait() end
	runPhase(PHASES.Preload)
end)

return table.freeze(setmetatable({}, meta))
