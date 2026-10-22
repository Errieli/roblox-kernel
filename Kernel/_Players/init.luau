local Players = game:GetService("Players")
local Task = require(script.Parent._Task)

local module = {
	Online = {} :: {Player}, 
}

local callbacks = {Added = {}, Removed = {}}

function module.Added(callback: (Player) -> ())
	for index, player in module.Online do
		Task.Spawn(callback, player)
	end

	table.insert(callbacks.Added, callback)

	return function()
		local index = table.find(callbacks.Added, callback)
		if index then
			table.remove(callbacks.Added, index)
		end
	end
end

function module.Removed(callback: (Player) -> ())
	table.insert(callbacks.Removed, callback)

	return function()
		local index = table.find(callbacks.Removed, callback)
		if index then
			table.remove(callbacks.Removed, index)
		end
	end
end

module.Online = Players:GetPlayers()

Players.PlayerAdded:Connect(function(player)
	table.insert(module.Online, player)

	for index, callback in callbacks.Added do
		Task.Spawn(callback, player)
	end
end)

Players.PlayerRemoving:Connect(function(player)
	local index = table.find(module.Online, player) 
	if index then
		table.remove(module.Online, index)
	end

	for index, callback in callbacks.Removed do
		Task.Spawn(callback, player)
	end
end)

return module