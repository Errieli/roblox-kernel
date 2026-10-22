const DEFAULT_DISTANCE = 30
const DEFAULT_ATTEMPTS = 10
const Ground = {}

function Ground.Cast(origin: Vector3, params: RaycastParams?, distance: number?, radius: number?)
	const direction = Vector3.yAxis * -(distance or DEFAULT_DISTANCE)
	const result = if radius then workspace:Spherecast(origin, radius, direction, params) else workspace:Raycast(origin, direction, params)

	return result and result.Position, result
end

function Ground.Resolve(origin: Vector3, offsetY: number, params: RaycastParams?, distance: number?, fallbackPosition: Vector3?)
	const position, result = Ground.Cast(origin, params, distance)

	return if position then position + Vector3.yAxis * offsetY else fallbackPosition or origin + Vector3.yAxis * (offsetY - (distance or DEFAULT_DISTANCE)), result
end

function Ground.RandomInBox(box: BasePart, params: RaycastParams?, distance: number?, attempts: number?)
	const size = box.Size
	const castDistance = distance or math.max(DEFAULT_DISTANCE, size.Y + 20)

	for _ = 1, attempts or DEFAULT_ATTEMPTS do
		const x = math.random() * size.X - size.X / 2
		const z = math.random() * size.Z - size.Z / 2
		const origin = (box.CFrame * CFrame.new(x, size.Y / 2, z)).Position
		const position = Ground.Cast(origin, params, castDistance)

		if position then return position end
	end

	warn(`Failed to find ground below {box:GetFullName()}`)
	return (box.CFrame * CFrame.new(0, -size.Y / 2, 0)).Position
end

function Ground.RandomInCircle(area: BasePart, params: RaycastParams?, distance: number?, attempts: number?, radius: number?)
	const areaRadius = math.min(area.Size.X, area.Size.Z) / 2
	const castDistance = distance or math.max(DEFAULT_DISTANCE, area.Size.Y + 20)

	for _ = 1, attempts or DEFAULT_ATTEMPTS do
		const angle = math.random() * math.pi * 2
		const pointRadius = math.sqrt(math.random()) * areaRadius
		const x = math.cos(angle) * pointRadius
		const z = math.sin(angle) * pointRadius
		const origin = (area.CFrame * CFrame.new(x, area.Size.Y / 2, z)).Position
		const position = Ground.Cast(origin, params, castDistance, radius)

		if position then return position end
	end

	warn(`Failed to find ground below {area:GetFullName()}`)
	return (area.CFrame * CFrame.new(0, -area.Size.Y / 2, 0)).Position
end

function Ground.GetModelOffset(model: Model, scale: number?)
	const pivot = model:GetPivot()
	const boundsCFrame, boundsSize = model:GetBoundingBox()
	const bottomY = boundsCFrame.Position.Y - boundsSize.Y / 2

	return (pivot.Position.Y - bottomY) * (scale or 1)
end

return Ground