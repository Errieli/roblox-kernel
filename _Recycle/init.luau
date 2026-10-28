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
	local parent = self._parent
	if parent and not parent._cleaning then
		for index, item in parent._items do
			if item.Object == self then table.remove(parent._items, index) break end
		end
	end
end

-- Destroys this Recycle when the instance is destroyed; the Destroying
-- connection itself is released if the Recycle is destroyed first.
function Recycle:AttachToInstance(instance)
	assert(typeof(instance) == "Instance", "AttachToInstance requires an Instance")
	self:Connect(instance.Destroying:Connect(function()
		self:Destroy()
	end))
	return self
end

-- A nested Recycle is cleaned before the resources its parent held earlier,
-- and leaves the parent when destroyed on its own.
function Recycle:Extend()
	assert(not self._destroyed and not self._cleaning, "Cannot extend a destroyed Recycle")
	local child = Recycle.new()
	child._parent = self
	self._items[#self._items + 1] = {Cleaner = Recycle.Destroy, Object = child}
	return child
end

return setmetatable(Recycle, {
	__call = function()
		return Recycle.new()
	end,
})
