local Physics = {}

local function apply(root, callback)
	if root:IsA("BasePart") then callback(root) end

	for _, descendant in root:GetDescendants() do
		if descendant:IsA("BasePart") then callback(descendant) end
	end
end

function Physics.SetCollisionGroup(root, collisionGroup, observeDescendants)
	assert(typeof(collisionGroup) == "string", "Collision group must be a string")
	apply(root, function(part)
		part.CollisionGroup = collisionGroup
	end)
	if observeDescendants then
		return root.DescendantAdded:Connect(function(part)
			if part:IsA("BasePart") then part.CollisionGroup = collisionGroup end
		end)
	end
end

function Physics.Anchor(root, anchored)
	if anchored == nil then anchored = true end
	apply(root, function(part)
		part.Anchored = anchored
	end)
end

function Physics.DisableQuery(root)
	apply(root, function(part)
		part.CanQuery = false
	end)
end

function Physics.DisableCollide(root)
	apply(root, function(part)
		part.CanCollide = false
		part.CanTouch = false
	end)
end

function Physics.DisableAllPhysics(root, collisionGroup)
	apply(root, function(part)
		part.EnableFluidForces = false
		part.AudioCanCollide = false
		part.CanCollide = false
		part.CanTouch = false
		part.CanQuery = false
		part.Massless = true
		if collisionGroup then part.CollisionGroup = collisionGroup end
	end)
end

function Physics.DisableHumanoidStates(humanoid)
	for _, state in Enum.HumanoidStateType:GetEnumItems() do
		if state == Enum.HumanoidStateType.None then continue end
		humanoid:SetStateEnabled(state, false)
	end
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Running, true)
	humanoid:SetStateEnabled(Enum.HumanoidStateType.Dead, true)
end

return table.freeze(Physics)
