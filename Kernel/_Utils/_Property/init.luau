-- // Services

local Property = {}

-- Set the property of the instance if found.
function Property.Set(instance: Instance, name: string, value: any?): ()
	if not instance then return end
	if not instance:IsA("Instance") then return end

	(instance :: any?)[name] = value
end

-- Get the property of the instance if found.
function Property.Get(instance: Instance, name: string, value: any?): any?
	if not instance then return end
	if not instance:IsA("Instance") then return end

	return (instance :: any?)[name] or instance:GetAttributeChangedSignal(name):Wait()
end
return Property