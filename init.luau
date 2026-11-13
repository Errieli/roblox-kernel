local RunService = game:GetService("RunService")
local Task = require(script._Task)
local Diagnostics = require(script._Diagnostics)
local Exports = require(script._Exports)
local Phases = require(script._Phases)
local LazyTree = require(script._LazyTree)

local exports = Exports.Values
local meta = {__index = exports}
local runtimeEnvironment = if RunService:IsServer() then "Server" elseif RunService:IsClient() then "Client" else "Shared"

-- Where the game's Utils, Configs, Rules and Assets folders live: the ReplicatedStorage root first,
-- then these ReplicatedStorage children in order. Kernel.Configure({ProjectFolders = {...}}) replaces
-- the list before the first lookup; {} keeps only the root.
local projectSearch = {Folders = {"Modules"}, Resolved = false}

local function validFolders(folders)
	if typeof(folders) ~= "table" then return false end
	local count = 0
	for _ in folders do count += 1 end
	for index = 1, count do
		local name = folders[index]
		if typeof(name) ~= "string" or name == "" then return false end
	end
	return true
end

exports.Yield = Phases.Yield

-- One declaration of bootstrap options. ProjectFolders is handled here; the rest belongs to Phases.
-- A rejected declaration changes nothing.
function exports.Configure(options)
	assert(typeof(options) == "table", "Kernel.Configure expects an options table")
	local folders = options.ProjectFolders
	local rest = options
	if folders ~= nil then
		assert(validFolders(folders), "ProjectFolders must be an array of ReplicatedStorage folder names")
		assert(not projectSearch.Resolved, "ProjectFolders must be declared before the first Utils, Configs, Rules or Assets lookup")
		rest = table.clone(options)
		rest.ProjectFolders = nil
	end

	Phases.Configure(rest)
	if folders ~= nil then projectSearch.Folders = table.freeze(table.clone(folders)) end
end

function exports.Info()
	local state = Phases.State()
	state.environment = runtimeEnvironment
	state.exportInfo = Exports.Info
	state.missingDependencies = Exports.Missing()
	return Diagnostics.Snapshot(state, os.clock())
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
Exports.AddBuiltin("Utils", LazyTree("Utils", "Utility", nil, projectSearch), "Lazily resolves the game's utilities in ReplicatedStorage.Utils.")
Exports.AddBuiltin("Events", require(script._Events), "Coordinates transient, synchronous, and retained local events.")
Exports.AddBuiltin("Players", require(script._Players), "Observes the live player collection.")
Exports.AddBuiltin("Multiplier", require(script._Multiplier), "Combines named multiplier sources and change signals.")
Exports.AddBuiltin("Recycle", require(script._Recycle), "Collects runtime resources for deterministic cleanup.")
Exports.AddBuiltin("Configs", LazyTree("Configs", "Config", nil, projectSearch), "Lazily resolves and caches configuration modules.")
-- Rules are the game's pure shared logic (ReplicatedStorage.Rules): computed from Configs, with no state of their own.
Exports.AddBuiltin("Rules", LazyTree("Rules", "Rule", nil, projectSearch), "Lazily resolves the game's pure shared rules in ReplicatedStorage.Rules.")
Exports.AddBuiltin("Assets", LazyTree("Assets", "Asset", function(child) return child end, projectSearch), "Lazily maps replicated game assets.")

Phases.Start(Exports.Unresolved)

return table.freeze(setmetatable({}, meta))
