local Task = require(script.Parent._Task)

local cleanupByType = {
	["function"] = function(callback)
		callback()
	end,
	thread = function(target)
		Task.Cancel(target)
	end,
	RBXScriptConnection = function(connection)
		connection:Disconnect()
	end,
	Instance = function(instance)
		instance:Destroy()
	end,
}

local Recycle = {}
Recycle.__index = Recycle

local function add(self, object)
	local cleaner = cleanupByType[typeof(object)]
	if type(object) == "table" then
		if type(object.Disconnect) == "function" then cleaner = function(value) value:Disconnect() end
		elseif type(object.Destroy) == "function" then cleaner = function(value) value:Destroy() end end
	end
	if not cleaner then
		warn(string.format("Invalid Recycle object type: %s\n%s", typeof(object), debug.traceback()))
		return false
	end
	self._items[#self._items + 1] = {Cleaner = cleaner, Object = object}
	return true
end

function Recycle.new()
	return setmetatable({_items = {}, _destroyed = false}, Recycle)
end

function Recycle:Connect(objects)
	assert(not self._destroyed and not self._cleaning, "Cannot connect resources to a destroyed Recycle")
	if typeof(objects) == "table" and type(objects.Disconnect) ~= "function" and type(objects.Destroy) ~= "function" then
		for _, object in pairs(objects) do add(self, object) end
	else
		add(self, objects)
	end
	return objects
end

function Recycle:Disconnect()
	if self._cleaning then return end
	self._cleaning = true
	for index = #self._items, 1, -1 do
		local item = self._items[index]
		self._items[index] = nil
		local success, message = pcall(item.Cleaner, item.Object)
		if not success then warn("Recycle cleanup failed: " .. tostring(message)) end
	end
	self._cleaning = false
end

function Recycle:Destroy()
	if self._destroyed then return end
	self._destroyed = true
	self:Disconnect()
end

return setmetatable(Recycle, {
	__call = function()
		return Recycle.new()
	end,
})
