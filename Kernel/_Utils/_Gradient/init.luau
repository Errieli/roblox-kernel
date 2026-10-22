local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Gradient = {}

local DEFAULT_UPDATE_RATE = 20
local DEFAULT_DISTANCE = 140
local MAX_UPDATES_PER_STEP = 80

local animated = {}
local observing = {}
local watched = {}
local updateConnection = nil
local lowGraphicsProvider = nil
local updateCursor = 0
local activeCount = 0

function Gradient.Sequence(lightColor: Color3, strongColor: Color3): ColorSequence
	return ColorSequence.new({
		ColorSequenceKeypoint.new(0, lightColor),
		ColorSequenceKeypoint.new(1, strongColor),
	})
end

function Gradient.Get(parent: Instance, name: string?): UIGradient
	local gradientName = name or "Gradient"
	local gradient = parent:FindFirstChild(gradientName)
	if gradient and gradient:IsA("UIGradient") then return gradient end

	gradient = Instance.new("UIGradient")
	gradient.Name = gradientName
	gradient.Rotation = 0
	gradient.Parent = parent
	return gradient
end

function Gradient.SetAnimation(gradient: UIGradient, options)
	if typeof(options) ~= "table" then
		gradient:SetAttribute("GradientAnimated", false)
		return gradient
	end

	gradient:SetAttribute("GradientAnimated", options.Enabled ~= false)
	gradient:SetAttribute("GradientPreset", options.Preset or "Shimmer")
	gradient:SetAttribute("GradientSpeed", options.Speed or 0.25)
	gradient:SetAttribute("GradientDistance", options.Distance or DEFAULT_DISTANCE)
	gradient:SetAttribute("GradientUpdateRate", options.UpdateRate or DEFAULT_UPDATE_RATE)
	return gradient
end

function Gradient.Apply(parent: Instance, name: string?, lightColor: Color3, strongColor: Color3, rotation: number?, animation): UIGradient
	if typeof(rotation) == "table" and animation == nil then
		animation = rotation
		rotation = nil
	end

	local gradient = Gradient.Get(parent, name)
	gradient.Rotation = rotation or 0
	gradient.Color = Gradient.Sequence(lightColor, strongColor)
	Gradient.SetAnimation(gradient, animation)
	return gradient
end

function Gradient.Pair(base: Color3, peak: Color3, alpha: number, lightBlend: number?): (Color3, Color3)
	alpha = math.clamp(alpha or 0, 0, 1)
	local strong = base:Lerp(peak, alpha)
	local light = strong:Lerp(Color3.new(1, 1, 1), math.clamp(lightBlend or 0.25, 0, 1))
	return light, strong
end

function Gradient.FromPalette(palette: {Color3}, alpha: number, lightBlend: number?): (Color3, Color3)
	if typeof(palette) ~= "table" or #palette == 0 then
		return Gradient.Pair(Color3.new(1, 1, 1), Color3.new(1, 1, 1), 1, lightBlend)
	end

	alpha = math.clamp(alpha or 0, 0, 1)
	if #palette == 1 then
		local color = palette[1]
		return color:Lerp(Color3.new(1, 1, 1), math.clamp(lightBlend or 0.25, 0, 1)), color
	end

	local scaled = alpha * (#palette - 1)
	local colorIndex = math.clamp(math.floor(scaled) + 1, 1, #palette)
	local nextColorIndex = math.min(colorIndex + 1, #palette)
	local localAlpha = scaled % 1
	local strong = palette[colorIndex]:Lerp(palette[nextColorIndex], localAlpha)
	local light = strong:Lerp(Color3.new(1, 1, 1), math.clamp(lightBlend or 0.25, 0, 1))
	return light, strong
end

local function findBillboard(instance: Instance): BillboardGui?
	local current = instance.Parent
	while current do
		if current:IsA("BillboardGui") then return current end
		current = current.Parent
	end
	return nil
end

local function getBillboardPosition(billboard: BillboardGui): Vector3?
	local adornee = billboard.Adornee
	if adornee then
		if adornee:IsA("BasePart") then return adornee.Position end
		if adornee:IsA("Attachment") then return adornee.WorldPosition end
	end

	local parent = billboard.Parent
	if parent and parent:IsA("Model") then
		local root = parent:FindFirstChild("HumanoidRootPart") or parent.PrimaryPart
		if root and root:IsA("BasePart") then return root.Position end
	elseif parent and parent:IsA("BasePart") then
		return parent.Position
	end

	return nil
end

local function isVisible(gradient: UIGradient, distance: number): boolean
	local parent = gradient.Parent
	if not parent then return false end
	if parent:IsA("GuiObject") and not parent.Visible then return false end

	local billboard = findBillboard(gradient)
	if not billboard then return true end
	if not billboard.Enabled then return false end

	local camera = Workspace.CurrentCamera
	if not camera then return true end

	local position = getBillboardPosition(billboard)
	if not position then return true end
	return (camera.CFrame.Position - position).Magnitude <= distance
end

local function readOptions(gradient: UIGradient)
	return {
		Preset = gradient:GetAttribute("GradientPreset") or "Shimmer",
		Speed = gradient:GetAttribute("GradientSpeed") or 0.25,
		Distance = gradient:GetAttribute("GradientDistance") or DEFAULT_DISTANCE,
		UpdateRate = gradient:GetAttribute("GradientUpdateRate") or DEFAULT_UPDATE_RATE,
	}
end

local function applyPreset(gradient: UIGradient, state, now: number)
	local preset = state.Preset
	local speed = state.Speed
	local t = now * speed + state.Phase

	if preset == "Spin" then
		gradient.Rotation = (state.BaseRotation + t * 360) % 360
	else
		gradient.Offset = Vector2.new((t % 2) - 1, 0)
	end
end

local function stepAnimated()
	if lowGraphicsProvider then
		local ok, isLowGraphics = pcall(lowGraphicsProvider)
		if ok and isLowGraphics then return end
		if not ok then lowGraphicsProvider = nil end
	end
	if activeCount <= 0 then return end

	local now = os.clock()
	local updated = 0
	local visited = 0

	for gradient, state in animated do
		visited += 1
		if visited <= updateCursor then continue end
		if gradient.Parent == nil or gradient:GetAttribute("GradientAnimated") == false then
			animated[gradient] = nil
			activeCount -= 1
			continue
		end

		local interval = 1 / math.max(state.UpdateRate or DEFAULT_UPDATE_RATE, 1)
		if now - state.LastUpdate >= interval and isVisible(gradient, state.Distance or DEFAULT_DISTANCE) then
			state.LastUpdate = now
			applyPreset(gradient, state, now)
			updated += 1
			if updated >= MAX_UPDATES_PER_STEP then
				updateCursor = visited
				return
			end
		end
	end

	updateCursor = 0
end

local function ensureConnection()
	if not RunService:IsClient() then return end
	if updateConnection then return end
	updateConnection = RunService.Heartbeat:Connect(stepAnimated)
end

function Gradient.SetLowGraphicsProvider(provider)
	lowGraphicsProvider = provider
end

function Gradient.Animate(gradient: UIGradient, options)
	if not RunService:IsClient() then return gradient end
	if not gradient or not gradient:IsA("UIGradient") then return gradient end
	if gradient:GetAttribute("GradientAnimated") == false then return gradient end

	options = options or readOptions(gradient)
	if options.Enabled == false then
		Gradient.Stop(gradient)
		return gradient
	end

	if not animated[gradient] then
		activeCount += 1
	end

	animated[gradient] = {
		Preset = options.Preset or "Shimmer",
		Speed = options.Speed or 0.25,
		Distance = options.Distance or DEFAULT_DISTANCE,
		UpdateRate = options.UpdateRate or DEFAULT_UPDATE_RATE,
		BaseRotation = gradient.Rotation,
		Phase = math.random(),
		LastUpdate = 0,
	}

	ensureConnection()
	return gradient
end

function Gradient.Stop(gradient: UIGradient)
	local state = animated[gradient]
	if state then
		animated[gradient] = nil
		activeCount -= 1
	end
	if gradient then
		gradient.Offset = Vector2.zero
		if state and state.Preset == "Spin" then
			gradient.Rotation = state.BaseRotation
		end
	end
end

local function refreshAnimated(gradient: UIGradient)
	if gradient:GetAttribute("GradientAnimated") == true then
		Gradient.Animate(gradient)
	else
		Gradient.Stop(gradient)
	end
end

local function watchGradient(gradient: UIGradient)
	if watched[gradient] then
		refreshAnimated(gradient)
		return
	end

	watched[gradient] = {
		gradient:GetAttributeChangedSignal("GradientAnimated"):Connect(function()
			refreshAnimated(gradient)
		end),
		gradient:GetAttributeChangedSignal("GradientPreset"):Connect(function()
			refreshAnimated(gradient)
		end),
		gradient:GetAttributeChangedSignal("GradientSpeed"):Connect(function()
			refreshAnimated(gradient)
		end),
		gradient:GetAttributeChangedSignal("GradientDistance"):Connect(function()
			refreshAnimated(gradient)
		end),
		gradient:GetAttributeChangedSignal("GradientUpdateRate"):Connect(function()
			refreshAnimated(gradient)
		end),
	}

	refreshAnimated(gradient)
end

local function unwatchGradient(gradient: UIGradient)
	local connections = watched[gradient]
	if connections then
		for _, connection in connections do
			connection:Disconnect()
		end
		watched[gradient] = nil
	end
	Gradient.Stop(gradient)
end

function Gradient.Observe(root: Instance)
	if not RunService:IsClient() then return function() end end
	if observing[root] then return observing[root] end

	local connections = {}
	local function register(instance)
		if instance:IsA("UIGradient") then
			watchGradient(instance)
		end
	end

	for _, descendant in root:GetDescendants() do
		register(descendant)
	end

	connections[#connections + 1] = root.DescendantAdded:Connect(register)
	connections[#connections + 1] = root.DescendantRemoving:Connect(function(instance)
		if instance:IsA("UIGradient") then
			unwatchGradient(instance)
		end
	end)

	local disconnect = function()
		for _, connection in connections do
			connection:Disconnect()
		end
		for _, descendant in root:GetDescendants() do
			if descendant:IsA("UIGradient") then
				unwatchGradient(descendant)
			end
		end
		observing[root] = nil
	end

	observing[root] = disconnect
	ensureConnection()
	return disconnect
end

return Gradient