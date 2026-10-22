const Kernel = require(game:GetService("ReplicatedFirst").Kernel)
const Beat = Kernel.Beat
const cache = {}

const function getBezier(startPosition: Vector3, control: Vector3, endPosition: Vector3, alpha: number): Vector3
	const inverse = 1 - alpha

	return inverse * inverse * startPosition + 2 * inverse * alpha * control + alpha * alpha * endPosition
end

Beat.Heartbeat(function(deltaTime)
	for part, data in cache do
		if not part.Parent then
			cache[part] = nil
			continue
		end

		data.Elapsed += deltaTime

		const alpha = math.clamp(data.Elapsed / data.Duration, 0, 1)
		part.Position = getBezier(data.StartPosition, data.Control, data.EndPosition, alpha)

		if data.RandomRotation then
			part.Orientation += Vector3.one * 360 * deltaTime
		end

		if alpha >= 1 then
			cache[part] = nil
		end
	end
end)

return function(part: BasePart, startPosition: Vector3, controlOffset: Vector3, endPosition: Vector3, duration: number, shouldYield: boolean?, randomRotation: boolean?)
	if typeof(part) ~= "Instance" or not part:IsA("BasePart") then return end

	const control = (startPosition + endPosition) / 2
	const data = {
		Elapsed = 0;
		Duration = math.max(duration, 1 / 240);
		StartPosition = startPosition;
		Control = control + controlOffset;
		EndPosition = endPosition;
		RandomRotation = randomRotation == true;
	}

	cache[part] = data

	if shouldYield then
		task.wait(data.Duration)

		if cache[part] == data then
			cache[part] = nil
		end
		return
	end

	return function()
		if cache[part] == data then
			cache[part] = nil
		end
	end
end