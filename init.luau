local RunService = game:GetService("RunService")
local ScriptContext = game:GetService("ScriptContext")
local Task = require(script._Task)
local Diagnostics = require(script._Diagnostics)

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
local threadSources = setmetatable({}, {__mode = "k"})
local phaseStalls = {}
local stallSeconds = 30
local configured = false
local bootstrapFailure
local errorConnection
local phaseStates = {}
local phaseFailures = {}
local activePhase = 0
local completedPhase = 0

for priority = 1, PHASE_COUNT do
	calls[priority] = {}
	waitingThreads[priority] = {}
	phaseFailures[priority] = {}
	phaseStates[priority] = {status = "Pending"}
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

local function trackRegistrationThread()
	local thread = coroutine.running()
	if thread and calls[PHASES.Preload] then
		local source = sourceName()
		waitingThreads[PHASES.Preload][thread] = true
		sourcePhases[source] = PHASES.Preload
		threadSources[thread] = threadSources[thread] or source
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
	dependencies = table.clone(dependencies)
	for _, dependency in ipairs(dependencies) do
		assert(typeof(dependency) == "string" and dependency ~= "", "Invalid Kernel dependency for " .. name)
	end

	trackRegistrationThread()
	rawset(hidden, name, value)
	exportInfo[name] = {purpose = metadata.purpose, dependencies = dependencies}

	return value
end

-- Optional bootstrap policy. PhaseStallSeconds = false disables the stall warning.
function hidden.Configure(options)
	assert(typeof(options) == "table", "Kernel.Configure expects an options table")
	assert(not configured, "Kernel.Configure accepts one declaration")
	assert(completedPhase < PHASE_COUNT, "Kernel.Configure must run before Ready completes")
	for key in pairs(options) do
		assert(key == "PhaseStallSeconds", "Unknown Kernel option: " .. tostring(key))
	end
	local seconds = options.PhaseStallSeconds
	if seconds ~= nil and seconds ~= false then
		assert(typeof(seconds) == "number" and seconds > 0 and seconds < math.huge, "PhaseStallSeconds must be a positive number or false")
	end
	configured = true
	if seconds ~= nil then stallSeconds = seconds end
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

-- Resumes a thread waiting in Yield. Engine resumption preserves require/Invoke
-- continuations (a raw resume can finish a ModuleScript while leaving its
-- requiring script suspended); its errors reach ScriptContext.Error below.
local function resumeWaiting(priority, thread, registry, source)
	sourcePhases[source] = priority
	registry[thread] = true
	threadSources[thread] = source
	Task.Defer(function()
		-- A failed bootstrap may have cancelled it before this turn.
		if coroutine.status(thread) == "suspended" then Task.Spawn(thread) end
	end)
end

-- Yield pauses the calling thread until every earlier phase completes and enters
-- the named phase. It does not wait for other work in the same phase. Code that
-- must not block its script runs in its own thread: Kernel.Task.Spawn(function() ... end).
function hidden.Yield(phase, unexpected)
	local priority = resolvePhase(phase)
	assert(unexpected == nil, "Kernel.Yield takes only a phase; run the code after it returns")
	if bootstrapFailure then error(bootstrapFailure.message, 2) end
	local state = phaseStates[priority]

	local thread = coroutine.running()
	assert(thread, "Kernel.Yield cannot pause outside a coroutine")
	local phaseCalls = calls[priority]
	if phaseCalls then
		removeWaitingThread(thread, priority)
		phaseCalls[#phaseCalls + 1] = {thread = thread, source = sourceName()}
		local success, message = coroutine.yield()
		if success == false then error(message, 2) end
		return
	end

	-- A later Yield to the running phase joins it; one to a finished phase returns.
	if state.status == "Running" and priority == activePhase then
		local source = sourceName()
		waitingThreads[priority][thread] = true
		sourcePhases[source] = priority
		threadSources[thread] = source
	end
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

function hidden.Info()
	return Diagnostics.Snapshot({
		environment = runtimeEnvironment,
		phaseNames = PHASE_NAMES,
		phaseName = phaseName,
		activePhase = activePhase,
		completedPhase = completedPhase,
		phaseStates = phaseStates,
		waitingThreads = waitingThreads,
		threadSources = threadSources,
		exportInfo = exportInfo,
		phaseFailures = phaseFailures,
		phaseStalls = phaseStalls,
		stallSeconds = stallSeconds,
		bootstrapFailure = bootstrapFailure,
		missingDependencies = collectMissingDependencies(),
	}, os.clock())
end

function meta:__index(index)
	return rawget(hidden, index)
end

function meta:__newindex(index)
	error("Can not modify Kernel export: " .. tostring(index), 2)
end

-- Kernel{name = ..., value = ..., purpose = ..., dependencies = {...}} is the only registration form.
function meta:__call(definition)
	assert(typeof(definition) == "table", "Kernel{...} expects a definition table")
	return register(definition.name, definition.value, {
		purpose = definition.purpose,
		dependencies = definition.dependencies,
	})
end

local function registerBuiltin(name, value, purpose)
	rawset(hidden, name, value)
	exportInfo[name] = {purpose = purpose, dependencies = {}}
end

registerBuiltin("Task", Task, "Schedules visible asynchronous work and cancellation.")
registerBuiltin("Beat", require(script._Beat), "Connects callbacks to Roblox simulation and render signals.")
registerBuiltin("Class", require(script._Class), "Creates lightweight classes with constructor and destructor lifecycle.")
-- Utilities belong to the game (ReplicatedStorage.Utils);
-- Kernel.Utils.Name finds them without a require and names the missing one when absent.
registerBuiltin("Utils", require(script._LazyTree)("Utils", "Utility"), "Lazily resolves the game's utilities in ReplicatedStorage.Utils.")
registerBuiltin("Events", require(script._Events), "Coordinates transient, synchronous, and retained local events.")
registerBuiltin("Players", require(script._Players), "Observes the live player collection.")
registerBuiltin("Multiplier", require(script._Multiplier), "Combines named multiplier sources and change signals.")
registerBuiltin("Recycle", require(script._Recycle), "Collects runtime resources for deterministic cleanup.")
registerBuiltin("Configs", require(script._Configs), "Lazily resolves and caches configuration modules.")
registerBuiltin("Assets", require(script._Assets), "Lazily maps replicated game assets.")


-- Diagnostic only: a stalled phase keeps waiting; it warns once with its holders.
local function reportStall(priority, threads, since)
	if phaseStalls[priority] or not stallSeconds then return end
	local now = os.clock()
	if now - since < stallSeconds then return end
	local holders = Diagnostics.Holders(threads, threadSources)
	if #holders == 0 then return end
	local stall = {
		phase = phaseName(priority),
		since = since,
		warnedAt = now,
		threshold = stallSeconds,
		waited = now - since,
		holders = holders,
	}
	phaseStalls[priority] = stall
	warn(Diagnostics.StallWarning(stall))
end

local function waitForThreads(threads, priority, since)
	while threads and not bootstrapFailure do
		local thread = next(threads)
		if not thread then break end
		if coroutine.status(thread) == "dead" then
			threads[thread] = nil
		else
			reportStall(priority, threads, since)
			Task.Wait()
		end
	end
end

local function failPhase(priority, message)
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
		for _, entry in ipairs(calls[index] or {}) do pendingThreads[entry.thread] = true end
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
-- origin is the Script running the code, or the ModuleScript whose body failed,
-- so registered sources match it directly. Disconnects after Ready.
errorConnection = ScriptContext.Error:Connect(function(message, trace, origin)
	if bootstrapFailure or completedPhase == PHASE_COUNT or not origin then return end
	local source = origin:GetFullName()
	local priority = sourcePhases[source]
	if not priority then return end

	recordFailure(priority, source, message .. "\n" .. trace)
	failPhase(priority, message)
end)

local function runPhase(priority)
	if priority > PHASE_COUNT or bootstrapFailure then return end

	activePhase = priority
	local state = phaseStates[priority]
	local since = os.clock()
	waitForThreads(waitingThreads[priority], priority, since)
	if bootstrapFailure then return end

	local phaseCalls = calls[priority] or {}
	calls[priority] = nil
	local running = {}
	waitingThreads[priority] = running

	state.status = "Running"
	state.startedAt = os.clock()

	for _, entry in ipairs(phaseCalls) do
		resumeWaiting(priority, entry.thread, running, entry.source)
	end
	waitForThreads(running, priority, since)
	if bootstrapFailure then return end
	waitingThreads[priority] = nil
	local stall = phaseStalls[priority]
	if stall then
		stall.resolvedAt = os.clock()
		stall.waited = stall.resolvedAt - stall.since
		stall.holders = {}
	end

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
