--!native

type Token = {
	Callback: (...any) -> (),
	Debounce: number?,
	Cooldown: number,
	Connected: boolean,
}

local RunService = game:GetService("RunService")
local Task = require(script.Parent._Task)

local isClient = RunService:IsClient()

-- Each RunService signal is connected only while it has callbacks. Tokens are
-- independent; during a frame, disconnected tokens are skipped and removed
-- afterwards, and tokens added mid-frame start on the next one.
local function makeConnection(eventName: string)
	local tokens = {} :: {Token}
	local connection: RBXScriptConnection? = nil
	local dispatching, dirty = false, false
	-- Stepped passes (time, deltaTime); every other signal passes deltaTime first.
	local deltaIndex = if eventName == "Stepped" then 2 else 1

	local function compact()
		dirty = false
		local write = 0
		for read = 1, #tokens do
			local token = tokens[read]
			if token.Connected then
				write += 1
				tokens[write] = token
			end
		end

		for index = #tokens, write + 1, -1 do tokens[index] = nil end
		if write == 0 and connection then
			connection:Disconnect()
			connection = nil
		end
	end

	local function step(...)
		dispatching = true
		local deltaTime = select(deltaIndex, ...)
		for index = 1, #tokens do
			local token = tokens[index]
			if not token.Connected then continue end
			local debounce = token.Debounce
			if not debounce then
				Task.Run(token.Callback, ...)
				continue
			end

			token.Cooldown += deltaTime
			if token.Cooldown < debounce then continue end

			Task.Run(token.Callback, token.Cooldown)

			token.Cooldown -= debounce
		end

		dispatching = false
		if dirty then compact() end
	end

	--Handles timed connections -> function(Debounce_Time, Callback)
	return function(first, second): () -> ()
		local token: Token
		if type(first) == "number" and type(second) == "function" then
			token = {Callback = second, Debounce = first, Cooldown = 0, Connected = true}
		elseif type(first) == "function" then
			token = {Callback = first, Cooldown = 0, Connected = true}
		else
			error("Wrong Params", 2)
		end

		-- During a frame the loop bound is fixed, so an appended token waits a frame.
		table.insert(tokens, token)
		if not connection then
			connection = RunService[eventName]:Connect(step)
		end

		return function()
			if not token.Connected then return end
			token.Connected = false
			dirty = true
			if not dispatching then compact() end
		end
	end
end

local Beat = {}

Beat.Heartbeat = makeConnection("Heartbeat")
Beat.PostSimulation = makeConnection("PostSimulation")
Beat.PreAnimation = makeConnection("PreAnimation")
Beat.PreSimulation = makeConnection("PreSimulation")
Beat.Stepped = makeConnection("Stepped")

if isClient then
	Beat.PreRender = makeConnection("PreRender")
	Beat.RenderStepped = makeConnection("RenderStepped")
end

return Beat
