local Players = game:GetService("Players")
local Task = require(script.Parent._Task)
local Signal = require(script.Parent._Signal)
local Recycle = require(script.Parent._Recycle)

-- Online is replaced, never mutated: a kept reference stays a valid snapshot.
local online = table.freeze(Players:GetPlayers()) :: {Player}
local added, removed = Signal.new(), Signal.new()

local api = {}

function api.Added(callback: (Player) -> ())
	for _, player in online do
		Task.Run(callback, player)
	end

	return (added:Connect(callback))
end

function api.Removed(callback: (Player) -> ())
	return (removed:Connect(callback))
end

local function cleanNow(resource)
	local recycle = Recycle.new()
	recycle:Connect(resource)
	recycle:Destroy()
end

-- onAdded(player, recycle) may also return a cleanup resource; it joins the
-- player's Recycle, or is cleaned at once when the player already left.
function api.Observe(onAdded: (Player, any) -> any?, onRemoved: ((Player) -> ())?)
	assert(type(onAdded) == "function" and (onRemoved == nil or type(onRemoved) == "function"), "Invalid player observers")
	local recycles = {} :: {[Player]: any}
	local active = true

	local function attach(player)
		if not active or recycles[player] then return end
		local recycle = Recycle.new()
		recycles[player] = recycle
		Task.Run(function()
			local resource = onAdded(player, recycle)
			if resource == nil then return end
			if recycles[player] == recycle then recycle:Connect(resource) else cleanNow(resource) end
		end)
	end

	local function detach(player)
		local recycle = recycles[player]
		if not recycle then return end
		recycles[player] = nil
		if onRemoved then Task.Run(onRemoved, player) end
		recycle:Destroy()
	end

	local stopAdded = added:Connect(attach)
	local stopRemoved = removed:Connect(detach)
	for _, player in online do attach(player) end

	return function()
		if not active then return end
		active = false
		stopAdded(); stopRemoved()
		local list = recycles
		recycles = {}
		for _, recycle in list do recycle:Destroy() end
	end
end

Players.PlayerAdded:Connect(function(player)
	if table.find(online, player) then return end
	local list = table.clone(online)
	table.insert(list, player)
	online = table.freeze(list)
	added:Fire(player)
end)

Players.PlayerRemoving:Connect(function(player)
	local index = table.find(online, player)
	if index then
		local list = table.clone(online)
		table.remove(list, index)
		online = table.freeze(list)
	end

	removed:Fire(player)
end)

return setmetatable({}, {
	__index = function(_, key)
		if key == "Online" then return online end
		return api[key]
	end,
	__newindex = function(_, key)
		error("Kernel.Players is read-only: " .. tostring(key), 2)
	end,
	__metatable = "locked",
})
