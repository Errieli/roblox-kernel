local Bezier = {}

function Bezier.Quadratic(point0, point1, point2, alpha)
	local inverse = 1 - alpha
	return (inverse ^ 2 * point0)
		+ (2 * inverse * alpha * point1)
		+ (alpha ^ 2 * point2)
end

function Bezier.QuadraticTangent(point0, point1, point2, alpha)
	return (2 * (1 - alpha) * (point1 - point0))
		+ (2 * alpha * (point2 - point1))
end

function Bezier.Cubic(point0, point1, point2, point3, alpha)
	local inverse = 1 - alpha
	return (inverse ^ 3 * point0)
		+ (3 * inverse ^ 2 * alpha * point1)
		+ (3 * inverse * alpha ^ 2 * point2)
		+ (alpha ^ 3 * point3)
end

function Bezier.CubicTangent(point0, point1, point2, point3, alpha)
	local inverse = 1 - alpha
	return (3 * inverse ^ 2 * (point1 - point0))
		+ (6 * inverse * alpha * (point2 - point1))
		+ (3 * alpha ^ 2 * (point3 - point2))
end

return table.freeze(Bezier)