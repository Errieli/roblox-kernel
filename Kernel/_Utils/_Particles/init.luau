-- Small common particle primitives. Extended effects are a separate optional library.
local Particles = {}
local function visit(root, callback)
	local function apply(item)
		if item:IsA("ParticleEmitter") or item:IsA("Beam") or item:IsA("Trail") then callback(item) end
	end
	apply(root)
	for _, item in root:GetDescendants() do apply(item) end
end
function Particles.Emit(root, count)
	visit(root, function(item)
		if not item:IsA("ParticleEmitter") then return end
		local amount = count or item:GetAttribute("EmitCount") or 1
		assert(type(amount) == "number" and amount >= 0 and amount < math.huge, "Invalid emission count")
		item:Emit(math.floor(amount))
	end)
end
function Particles.SetEnabled(root, enabled)
	visit(root, function(item) item.Enabled = enabled end)
end
return table.freeze(Particles)
