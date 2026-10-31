-- Startup phases: who waits on each one, when it advances and how it fails.
local RunService = game:GetService("RunService")
local ScriptContext = game:GetService("ScriptContext")
local Task = require(script.Parent._Task)
local Diagnostics = require(script.Parent._Diagnostics)

local PHASES = {
	Preload = 1,
	Shared = 2,
	Runtime = 3,
	Ready = 4,
}
local PHASE_NAMES = {"Preload", "Shared", "Runtime", "Ready"}
local PHASE_COUNT = #PHASE_NAMES

local kernelName = script.Parent:GetFullName()
local ownSources = {[debug.info(1, "s")] = true, [kernelName] = true}

local Phases = {}

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

-- The script that called into the Kernel: the first frame outside this module and the facade.
local function sourceName()
	for level = 2, 14 do
		local success, source = pcall(debug.info, level, "s")
		if not success then break end
		if source and not ownSources[source] and source ~= "[C]" then return source end
	end

	return "Unknown"
end

function Phases.TrackRegistration()
	local thread = coroutine.running()
	if thread and calls[PHASES.Preload] then
		local source = sourceName()
		waitingThreads[PHASES.Preload][thread] = true
		sourcePhases[source] = PHASES.Preload
		threadSources[thread] = threadSources[thread] or source
	end
end

-- Optional bootstrap policy. PhaseStallSeconds = false disables the stall warning.
function Phases.Configure(options)
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
function Phases.Yield(phase, unexpected)
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

function Phases.Failure()
	return bootstrapFailure and bootstrapFailure.message
end

-- Live state for Diagnostics.Snapshot, which copies what it keeps.
function Phases.State()
	return {
		phaseNames = PHASE_NAMES,
		phaseName = phaseName,
		activePhase = activePhase,
		completedPhase = completedPhase,
		phaseStates = phaseStates,
		waitingThreads = waitingThreads,
		threadSources = threadSources,
		phaseFailures = phaseFailures,
		phaseStalls = phaseStalls,
		stallSeconds = stallSeconds,
		bootstrapFailure = bootstrapFailure,
	}
end

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

local function runPhase(priority, checkReady)
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
		local message = checkReady()
		if message then
			recordFailure(priority, kernelName, message)
			failPhase(priority, message)
			return
		end
	end

	completedPhase = priority
	state.status = "Completed"
	state.completedAt = os.clock()

	if priority < PHASE_COUNT then
		Task.Defer(runPhase, priority + 1, checkReady)
	elseif errorConnection then
		errorConnection:Disconnect()
		errorConnection = nil
		table.clear(sourcePhases)
	end
end

-- checkReady runs before Ready completes and returns a failure message, or nil to pass.
function Phases.Start(checkReady)
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

	-- Pure facade exports are available immediately. Project phases retain their
	-- existing guarantee that the initial replicated game tree is available.
	Task.Defer(function()
		if RunService:IsClient() and not game:IsLoaded() then game.Loaded:Wait() end
		runPhase(PHASES.Preload, checkReady)
	end)
end

return Phases
