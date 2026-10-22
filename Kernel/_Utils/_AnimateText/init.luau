type TextObject = TextLabel | TextButton
type TextOrTexts = TextObject | {TextObject}

const Kernel = require(game:GetService("ReplicatedFirst").Kernel)
const Task = Kernel.Task
const FormatText = Kernel.Utils.FormatText
const STEPS = 4
const DURATION = 0.6
const versions = setmetatable({}, {__mode = "k"})

const function updateLabel(label: TextObject, ...)
	label.Text = FormatText(...)
end

const function updateLabels(textOrTexts: TextOrTexts, ...)
	if typeof(textOrTexts) == "table" then
		for _, label in textOrTexts do
			updateLabel(label, ...)
		end
		return
	end

	updateLabel(textOrTexts, ...)
end

return function(textOrTexts: TextOrTexts, newNumber: number, oldNumber: number?, decimalPlaces: number?)
	const key = if typeof(textOrTexts) == "table" then textOrTexts[1] else textOrTexts
	if not key then return end

	const version = (versions[key] or 0) + 1
	versions[key] = version

	if oldNumber == nil then
		updateLabels(textOrTexts, newNumber, decimalPlaces)
		return
	end

	const difference = newNumber - oldNumber
	const fraction = difference / STEPS

	Task.Spawn(function()
		for index = 1, STEPS do
			if versions[key] ~= version then return end

			updateLabels(textOrTexts, oldNumber + fraction * index, decimalPlaces)

			if index < STEPS then
				task.wait(DURATION / STEPS)
			end
		end
	end)
end