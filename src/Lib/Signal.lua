local usableThread: thread?

local function pass(fn: (...unknown) -> (), ...): ()
	local acquiredThread = usableThread
	usableThread = nil
	fn(...)
	usableThread = acquiredThread
end

local function yield(): ()
	while true do
		pass(coroutine.yield())
	end
end

type Disconnect = () -> () -> Disconnect

export type Module<T...> = {
	__tostring: (self: Signal<T...>) -> "CustomSignal",
	new: () -> Signal<T...>,
	Fire: (self: Signal<T...>, T...) -> (),
	Connect: (self: Signal<T...>, (T...) -> ()) -> Disconnect,
	ConnectLimited: (self: Signal<T...>, (T...) -> (), Amount: number) -> Disconnect,
	ConnectUntil: (self: Signal<T...>, (T...) -> (), Seconds: number) -> () -> (),
	ConnectStrict: (self: Signal<T...>, (T...) -> ()) -> Disconnect,
	Once: (self: Signal<T...>, (T...) -> ()) -> Disconnect,
	Wait: (self: Signal<T...>) -> T...,
	DisconnectAll: (self: Signal<T...>) -> (),
}

export type Signal<T...> = typeof(setmetatable({} :: { [(T...) -> ()]: boolean }, {} :: Module<T...>))

local Signal = {}
Signal.__index = Signal

function Signal:__tostring(): "CustomSignal"
	return "CustomSignal"
end

function Signal.new<T...>(): Signal<T...>
	return setmetatable({}, Signal)
end

function Signal:Fire(...)
	for callback in self do
		if not usableThread then
			usableThread = coroutine.create(yield)
			coroutine.resume(usableThread)
		end

		task.spawn(usableThread :: thread, callback, ...)
	end
end

function Signal:Connect(callback)
	assert(typeof(callback) == "function", `Callback is not a function!`)
	assert(self[callback] ~= nil, "Callback already connected to Signal!")

	self[callback] = true

	return function()
		self[callback] = nil

		return function()
			self:Connect(callback)
		end
	end
end

function Signal:ConnectLimited<T...>(callback: (T...) -> (), Amount: number): Disconnect
	local Fired = 0
	local Connection

	Connection = self:Connect(function(...)
		Fired += 1

		if Fired == Amount then
			Connection()
		end

		callback(...)
	end)

	return Connection
end

function Signal:ConnectUntil<T...>(callback: (T...) -> (), Seconds: number): () -> ()
	local Connection

	Connection = self:Connect(callback)

	local Delayer = task.delay(Seconds, function()
		Connection()
	end)

	return function()
		if coroutine.status(Delayer) ~= "dead" then
			task.cancel(Delayer)
			Connection()
		end
	end
end

function Signal:ConnectStrict<T...>(callback: (T...) -> ()): Disconnect
	local Connection

	Connection = self:Connect(function(...)
		if callback(...) == false then
			Connection()
		end
	end)

	return Connection
end

function Signal:Once(callback)
	assert(typeof(callback) == "function", `Callback is not a function!`)

	local connection

	connection = self:Connect(function(...)
		connection()
		callback(...)
	end)

	return connection
end

function Signal:Wait()
	local running = coroutine.running()

	self:Once(function(...)
		task.spawn(running, ...)
	end)

	return coroutine.yield()
end

function Signal:DisconnectAll()
	table.clear(self)
end

return table.freeze(Signal)
