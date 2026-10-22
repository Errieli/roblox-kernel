--!native

type FunctionT = () -> ()

type DebounceT = {
	Function: FunctionT,
	Cooldown: number,
	Debounce: number,
}

type List = {
	Basic: {[FunctionT]: true},
	Debounce: {[DebounceT]: true}
}

local RunService = game:GetService("RunService")
local Task = require(script.Parent._Task)

local isClient = RunService:IsClient() 

local callbacks = {} :: {[string]: {[string]: {[any]: true}}}

local function createAndReturn(table, index)
	table[index] = {} return table[index]
end

local function addFunction(eventName: string, ...) : (() -> ())
	local callbacksList: List = callbacks[eventName]
	if not callbacksList then
		error("Mode not found: "..eventName, 4)
	end

	local list: {[any]: true}--List
	local info: FunctionT | DebounceT

	if typeof(...) == "number" then
		local _debounce, _function = ...

		info = {
			Debounce = _debounce,
			Function = _function,
			Cooldown = 0
		}

		list = callbacksList.Debounce
	elseif typeof(...) == "function" then
		info = ...
		list = callbacksList.Basic-- :: {[FunctionT]: true}
	else
		error("Wrong Params", 4)
	end

	list[info] = true

	return function()
		list[info] = nil
	end	
end

local function makeConnection(eventName)
	local list = createAndReturn(callbacks, eventName) :: List
	local basicList = createAndReturn(list, "Basic") :: {[FunctionT]: true}
	local debounceList = createAndReturn(list, "Debounce") :: {[DebounceT]: true}

	RunService[eventName]:Connect(function(...)
		for fun in basicList do
			Task.Spawn(fun, ...)
		end

		for info in debounceList do
			info.Cooldown += select(2, ...) or ...
			if info.Cooldown < info.Debounce then continue end

			Task.Spawn(info.Function, info.Cooldown)

			info.Cooldown -= info.Debounce
		end
	end)
	
	--Handles timed connections -> function(Debounce_Time, Callback)
	return function(...)
		return addFunction(eventName, ...)
	end
end

local Beat = {}

Beat.Heartbeat = makeConnection("Heartbeat")
Beat.PostSimulation = makeConnection("PostSimulation")
Beat.PreAnimation = makeConnection("PreAnimation")
Beat.PreSimulation = makeConnection("PreSimulation")
Beat.Stepped = makeConnection("Stepped")

if isClient then
	Beat.PreRender = makeConnection("PreRender")
	Beat.RenderStepped = makeConnection("RenderStepped")
end

return Beat