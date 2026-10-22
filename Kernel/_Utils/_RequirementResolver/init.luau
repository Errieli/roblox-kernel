const Kernel = require(game.ReplicatedFirst.Kernel)
const Table = Kernel.Utils.Table

export type Requirement = {
	Type: string;
	Path: string?;
	Required: number?;
	Expected: any?;
	Key: any?;
	Operator: string?;
	Requirements: {any}?;
}

export type Overrides = {
	Required: number?;
	Expected: any?;
	Key: any?;
}

export type Result = {
	Type: string;
	Valid: boolean;
	Resolved: boolean;
	Completed: boolean;
	Progress: number;
	Current: any?;
	Target: any?;
	Path: string?;
	Key: any?;
	Operator: string?;
	Error: string?;
	Children: {any}?;
}

const Resolver = {}

const OPERATORS = {
	["=="] = true;
	["~="] = true;
	[">"] = true;
	[">="] = true;
	["<"] = true;
	["<="] = true;
}

const function clampProgress(value): number
	return math.clamp(tonumber(value) or 0, 0, 1)
end

const function invalid(typeName, reason): Result
	return {
		Type = typeName or "Unknown";
		Valid = false;
		Resolved = false;
		Completed = false;
		Progress = 0;
		Error = reason;
	}
end

const function result(typeName, resolved, completed, current, target, progress, extra): Result
	const state = {
		Type = typeName;
		Valid = true;
		Resolved = resolved;
		Completed = resolved and completed;
		Current = current;
		Target = target;
		Progress = resolved and clampProgress(progress) or 0;
	}

	if extra then
		for key, value in extra do
			state[key] = value
		end
	end

	return state
end

const function readPath(data, path)
	if typeof(path) ~= "string" or path == "" then return nil, false end

	const parent, _, value = Table.GetPath(data, path)
	if not parent or value == nil then return nil, false end

	return value, true
end

const function getOperator(requirement, defaultOperator)
	const operator = requirement.Operator or defaultOperator
	if not OPERATORS[operator] then return end

	return operator
end

const function compare(current, target, operator)
	if operator == "==" then return current == target end
	if operator == "~=" then return current ~= target end

	const currentType = typeof(current)
	const targetType = typeof(target)
	if currentType ~= targetType then
		return nil, `Cannot compare {currentType} with {targetType}`
	end
	if currentType ~= "number" and currentType ~= "string" then
		return nil, `Operator {operator} does not support {currentType}`
	end

	if operator == ">" then return current > target end
	if operator == ">=" then return current >= target end
	if operator == "<" then return current < target end
	if operator == "<=" then return current <= target end

	return nil, "Operator is invalid"
end

const function resolveCount(requirement, data, overrides)
	const path = requirement.Path
	const required = if overrides and overrides.Required ~= nil then overrides.Required else requirement.Required
	if typeof(path) ~= "string" or path == "" then
		return invalid("Count", "Count requires Path")
	end
	if typeof(required) ~= "number" or required < 0 then
		return invalid("Count", "Count requires a non-negative Required value")
	end

	const operator = getOperator(requirement, ">=")
	if not operator then return invalid("Count", "Count operator is invalid") end

	const current, resolved = readPath(data, path)
	if not resolved then
		return result("Count", false, false, nil, required, 0, {
			Path = path;
			Operator = operator;
		})
	end
	if typeof(current) ~= "number" then
		return invalid("Count", "Count Path must resolve to a number")
	end

	const completed, comparisonError = compare(current, required, operator)
	if comparisonError then return invalid("Count", comparisonError) end

	local progress = completed and 1 or 0
	if not completed and (operator == ">=" or operator == ">") and required > 0 then
		progress = current / required
	end

	return result("Count", true, completed, current, required, progress, {
		Path = path;
		Operator = operator;
	})
end

const function resolveValue(requirement, data, overrides)
	const path = requirement.Path
	const expected = if overrides and overrides.Expected ~= nil then overrides.Expected else requirement.Expected
	if typeof(path) ~= "string" or path == "" then
		return invalid("Value", "Value requires Path")
	end
	if expected == nil then
		return invalid("Value", "Value requires Expected")
	end

	const operator = getOperator(requirement, "==")
	if not operator then return invalid("Value", "Value operator is invalid") end

	const current, resolved = readPath(data, path)
	if not resolved then
		return result("Value", false, false, nil, expected, 0, {
			Path = path;
			Operator = operator;
		})
	end

	const completed, comparisonError = compare(current, expected, operator)
	if comparisonError then return invalid("Value", comparisonError) end

	return result("Value", true, completed, current, expected, completed and 1 or 0, {
		Path = path;
		Operator = operator;
	})
end

const function resolveOwn(requirement, data, overrides)
	const path = requirement.Path
	const key = if overrides and overrides.Key ~= nil then overrides.Key else requirement.Key
	if typeof(path) ~= "string" or path == "" then
		return invalid("Own", "Own requires Path")
	end
	if key == nil then
		return invalid("Own", "Own requires Key")
	end

	const container, resolved = readPath(data, path)
	if not resolved then
		return result("Own", false, false, nil, key, 0, {
			Path = path;
			Key = key;
		})
	end
	if typeof(container) ~= "table" then
		return invalid("Own", "Own Path must resolve to a table")
	end

	const current = container[key]
	local completed = current ~= nil and current ~= false
	if typeof(current) == "number" then
		completed = current > 0
	end

	return result("Own", true, completed, current, key, completed and 1 or 0, {
		Path = path;
		Key = key;
	})
end

const function resolveComposite(typeName, requirement, data)
	const requirements = requirement.Requirements
	if typeof(requirements) ~= "table" or #requirements == 0 then
		return invalid(typeName, typeName .. " requires a non-empty Requirements array")
	end

	const children = {}
	local valid = true
	local allResolved = true
	local allCompleted = true
	local anyCompleted = false
	local totalProgress = 0
	local highestProgress = 0

	for index = 1, #requirements do
		const child = Resolver.Resolve(requirements[index], data)
		children[index] = child
		valid = valid and child.Valid
		allResolved = allResolved and child.Resolved
		allCompleted = allCompleted and child.Completed
		anyCompleted = anyCompleted or child.Completed
		totalProgress += child.Progress
		highestProgress = math.max(highestProgress, child.Progress)
	end

	const completed = valid and (if typeName == "All" then allResolved and allCompleted else anyCompleted)
	const resolved = valid and (if typeName == "All" then allResolved else anyCompleted or allResolved)
	const progress = if typeName == "All" then totalProgress / #children else highestProgress

	return {
		Type = typeName;
		Valid = valid;
		Resolved = resolved;
		Completed = completed;
		Progress = valid and clampProgress(progress) or 0;
		Children = children;
		Error = if valid then nil else "Composite contains invalid requirements";
	}
end

function Resolver.Resolve(requirement: Requirement, data, overrides: Overrides?): Result
	if typeof(requirement) ~= "table" then
		return invalid(nil, "Requirement must be a table")
	end
	if typeof(data) ~= "table" then
		return invalid(requirement.Type, "Requirement data must be a table")
	end

	const typeName = requirement.Type
	if typeName == "All" or typeName == "Any" then
		return resolveComposite(typeName, requirement, data)
	end
	if typeName == "Count" then return resolveCount(requirement, data, overrides) end
	if typeName == "Value" then return resolveValue(requirement, data, overrides) end
	if typeName == "Own" then return resolveOwn(requirement, data, overrides) end

	return invalid(typeName, "Requirement type is not supported")
end

function Resolver.IsComplete(requirement: Requirement, data, overrides: Overrides?): boolean
	const state = Resolver.Resolve(requirement, data, overrides)
	return state.Valid and state.Resolved and state.Completed
end

function Resolver.GetProgress(requirement: Requirement, data, overrides: Overrides?): number
	const state = Resolver.Resolve(requirement, data, overrides)
	return state.Valid and state.Progress or 0
end

return table.freeze(Resolver)
