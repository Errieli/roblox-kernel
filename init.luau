local RunService = game:GetService("RunService")
local Task = require(script._Task)
local Diagnostics = require(script._Diagnostics)
local Exports = require(script._Exports)
local Phases = require(script._Phases)
local LazyTree = require(script._LazyTree)

local exports = Exports.Values
local meta = {}

local function environment()
	if RunService:IsServer() then return "Server" end
	if RunService:IsClient() then return "Client" end
	return "Shared"
end

local runtimeEnvironment = environment()

exports.Yield = Phases.Yield
exports.Configure = Phases.Configure

function exports.Info()
	local state = Phases.State()
	state.environment = runtimeEnvironment
	state.exportInfo = Exports.Info
	state.missingDependencies = Exports.Missing()
	return Diagnostics.Snapshot(state, os.clock())
end

function meta:__index(index)
	return rawget(exports, index)
end

function meta:__newindex(index)
	error("Can not modify Kernel export: " .. tostring(index), 2)
end

-- Kernel{name = ..., value = ..., purpose = ..., dependencies = {...}} is the only registration form.
function meta:__call(definition)
	assert(typeof(definition) == "table", "Kernel{...} expects a definition table")
	local failure = Phases.Failure()
	if failure then error(failure, 2) end
	Exports.Add(definition)
	Phases.TrackRegistration()
	return definition.value
end

Exports.AddBuiltin("Task", Task, "Schedules visible asynchronous work and cancellation.")
Exports.AddBuiltin("Beat", require(script._Beat), "Connects callbacks to Roblox simulation and render signals.")
Exports.AddBuiltin("Class", require(script._Class), "Creates lightweight classes with constructor and destructor lifecycle.")
-- Utilities belong to the game (ReplicatedStorage.Utils);
-- Kernel.Utils.Name finds them without a require and names the missing one when absent.
Exports.AddBuiltin("Utils", LazyTree("Utils", "Utility"), "Lazily resolves the game's utilities in ReplicatedStorage.Utils.")
Exports.AddBuiltin("Events", require(script._Events), "Coordinates transient, synchronous, and retained local events.")
Exports.AddBuiltin("Players", require(script._Players), "Observes the live player collection.")
Exports.AddBuiltin("Multiplier", require(script._Multiplier), "Combines named multiplier sources and change signals.")
Exports.AddBuiltin("Recycle", require(script._Recycle), "Collects runtime resources for deterministic cleanup.")
Exports.AddBuiltin("Configs", LazyTree("Configs", "Config"), "Lazily resolves and caches configuration modules.")
Exports.AddBuiltin("Assets", LazyTree("Assets", "Asset", function(child) return child end), "Lazily maps replicated game assets.")

Phases.Start(Exports.Unresolved)

return table.freeze(setmetatable({}, meta))
