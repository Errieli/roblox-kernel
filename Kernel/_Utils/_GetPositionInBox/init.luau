-- Gets a random position within a box, ensuring the position is valid by raycasting.
return function(box: BasePart, params)
	local cF = box.CFrame
	local size = box.Size

	local x = math.random(-size.X/2, size.X/2)
	local z = math.random(-size.Z/2, size.Z/2)

	local origin = cF * CFrame.new(x, size.Y/2, z)

	for _ = 1, 8 do
		local cast: RaycastResult = workspace:Raycast(origin.Position, Vector3.yAxis * -10, params)
		if cast then return cast.Position end
		task.wait()
	end

	warn("Failed to find valid position after 8 attempts")
	return box.Position
end