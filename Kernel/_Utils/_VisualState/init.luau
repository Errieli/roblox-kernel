local VisualState = {}

local function supportsTransparency(instance)
	return instance:IsA("BasePart")
		or instance:IsA("Decal")
		or instance:IsA("Texture")
end

local function supportsEnabled(instance)
	return instance:IsA("ParticleEmitter")
		or instance:IsA("Beam")
		or instance:IsA("Trail")
		or instance:IsA("Light")
		or instance:IsA("Highlight")
end

local function visit(root, callback)
	callback(root)
	for _, descendant in root:GetDescendants() do callback(descendant) end
end

function VisualState.Capture(root)
	local state = {}

	visit(root, function(instance)
		if supportsTransparency(instance) then
			state[instance] = {Transparency = instance.Transparency}
		elseif supportsEnabled(instance) then
			state[instance] = {Enabled = instance.Enabled}
		end
	end)

	return state
end

function VisualState.SetVisible(state, visible)
	for instance, properties in state do
		if not instance.Parent then continue end
		if properties.Transparency ~= nil then
			instance.Transparency = visible and properties.Transparency or 1
		else
			instance.Enabled = visible and properties.Enabled or false
		end
	end
end

function VisualState.TweenVisible(state, visible, tweenInfo, playTween)
	for instance, properties in state do
		if not instance.Parent then continue end
		if properties.Transparency ~= nil then
			playTween(instance, tweenInfo, {
				Transparency = visible and properties.Transparency or 1,
			})
		else
			instance.Enabled = visible and properties.Enabled or false
		end
	end
end

return table.freeze(VisualState)
