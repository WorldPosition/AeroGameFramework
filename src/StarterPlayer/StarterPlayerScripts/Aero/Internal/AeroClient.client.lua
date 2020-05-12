-- Aero Client
-- Stephen Leitnick
-- July 21, 2017
-- Modified by WorldPosition


local Aero = {
	Controllers = {};
	Modules = {};
	Shared = {};
	Services = {};
	Player = game:GetService("Players").LocalPlayer;
}

local NO_CACHE = {}

-- Registered properties table container.
local RegistereredProperties = {};

local mt = {}

mt.__index = function(self, index)
	if self._properties[index] then
		return self._properties[index];
	else
		return Aero[index];
	end
end

mt.__newindex = function(self, k, v)
	local property = self._properties[k];
	if property ~= nil then -- set the new _property and fire the event.
		if v == nil then
			v = false;
		end
		rawset(self._properties, k, v);
		if self._propertyevents[k] then
			self._propertyevents[k]:Fire(v, property); -- fire the new property (v) and the old one (property)
		end
	else
		rawset(self, k, v);
	end
end


local controllersFolder = script.Parent.Parent:WaitForChild("Controllers")
local modulesFolder = script.Parent.Parent:WaitForChild("Modules")
local sharedFolder = game:GetService("ReplicatedStorage"):WaitForChild("Aero"):WaitForChild("Shared")

local modulesAwaitingStart = {}

local SpawnNow = require(sharedFolder:WaitForChild("Thread"):Clone()).SpawnNow
local Promise = require(sharedFolder:WaitForChild("Promise"):Clone())


local function PreventEventRegister()
	error("Cannot register event after Init method")
end

-- Custom Function: Print text and describe what script it came from.
function Aero:Log(Text)
	local scrpt = getfenv(2).script;
	print("[" .. scrpt.Name .. "]: " .. Text);
end

-- Custom Function: Get the event for a registered property.
function Aero:GetPropertyChangedEvent(PropertyName)
	if self._propertyevents[PropertyName] then
		return self._propertyevents[PropertyName];
	end
end

-- Custom function: Create a new property with an event for when it is changed.
function Aero:RegisterProperty(PropertyName, DefaultValue)
	if DefaultValue == nil then DefaultValue = false end;
	self._propertyevents[PropertyName] = self.Shared.Event.new();
	rawset(self._properties, PropertyName, DefaultValue);
	return self._propertyevents[PropertyName];
end

function Aero:RegisterEvent(eventName)
	local event = self.Shared.Event.new()
	self._events[eventName] = event
	return event
end


function Aero:FireEvent(eventName, ...)
	self._events[eventName]:Fire(...)
end


function Aero:ConnectEvent(eventName, func)
	return self._events[eventName]:Connect(func)
end


function Aero:WaitForEvent(eventName)
	return self._events[eventName]:Wait()
end


function Aero:WrapModule(tbl)
	assert(type(tbl) == "table", "Expected table for argument")
	tbl._events = {}
	tbl._properties = {}; -- contains all registered properties.
	tbl._propertyevents = {}; -- contains all property changed events.
	setmetatable(tbl, mt)
	if (type(tbl.Init) == "function" and not tbl.__aeroPreventInit) then
		tbl:Init()
	end
	if (type(tbl.Start) == "function" and not tbl.__aeroPreventStart) then
		if (modulesAwaitingStart) then
			modulesAwaitingStart[#modulesAwaitingStart + 1] = tbl
		else
			SpawnNow(tbl.Start, tbl)
		end
	end
end


local function LoadService(serviceFolder, servicesTbl)
	local service = {}
	servicesTbl[serviceFolder.Name] = service
	for _,v in pairs(serviceFolder:GetChildren()) do
		if (v:IsA("RemoteEvent")) then
			local event = Aero.Shared.Event.new()
			local fireEvent = event.Fire
			function event:Fire(...)
				v:FireServer(...)
			end
			v.OnClientEvent:Connect(function(...)
				fireEvent(event, ...)
			end)
			service[v.Name] = event
		elseif (v:IsA("RemoteFunction")) then
			local cacheTTL = v:FindFirstChild("Cache")
			if (cacheTTL) then
				cacheTTL = cacheTTL.Value
				local methodName = v.Name
				local cache = NO_CACHE
				local lastCacheTime = 0
				local fetchingPromise
				service[methodName] = function(self, ...)
					local now = tick()
					if (fetchingPromise) then
						local _,c = fetchingPromise:Await()
						return table.unpack(c)
					elseif (cache == NO_CACHE or (cacheTTL > 0 and (now - lastCacheTime) > cacheTTL)) then
						lastCacheTime = now
						local args = table.pack(...)
						fetchingPromise = Promise.Async(function(resolve, reject)
							resolve(table.pack(v:InvokeServer(table.unpack(args))))
						end)
						local success, _cache = fetchingPromise:Await()
						if (success) then
							cache = _cache
						end
						fetchingPromise = nil
						return table.unpack(_cache)
					end
					return table.unpack(cache)
				end
			else
				service[v.Name] = function(self, ...)
					return v:InvokeServer(...)
				end
			end
		end
	end
	return service
end


local function LoadServices()
	local remoteServices = game:GetService("ReplicatedStorage"):WaitForChild("Aero"):WaitForChild("AeroRemoteServices")
	local function LoadAllServices(folder, servicesTbl)
		for _,serviceFolder in pairs(folder:GetChildren()) do
			if (serviceFolder:IsA("Folder")) then
				local service = LoadService(serviceFolder, servicesTbl)
				if (next(service) == nil) then
					LoadAllServices(serviceFolder, service)
				end
			end
		end
	end
	LoadAllServices(remoteServices, Aero.Services)
end


-- Setup table to load modules on demand:
local function LazyLoadSetup(tbl, folder)
	setmetatable(tbl, {
		__index = function(t, i)
			local child = folder[i]
			if (child:IsA("ModuleScript")) then
				local obj = require(child)
				rawset(t, i, obj)
				if (type(obj) == "table") then
					Aero:WrapModule(obj)
				end
				return obj
			elseif (child:IsA("Folder")) then
				local nestedTbl = {}
				rawset(t, i, nestedTbl)
				LazyLoadSetup(nestedTbl, child)
				return nestedTbl
			end
		end;
	})
end


local function LoadController(module, controllersTbl)
	local controller = require(module)
	controllersTbl[module.Name] = controller
	controller._events = {}
	controller._properties = {}; -- contains all registered properties.
	controller._propertyevents = {}; -- contains all property changed events.
	setmetatable(controller, mt)
end


local function InitController(controller)
	if (type(controller.Init) == "function") then
		controller:Init()
	end
	controller.RegisterEvent = PreventEventRegister
end


local function StartController(controller)
	-- Start controllers on separate threads:
	if (type(controller.Start) == "function") then
		SpawnNow(controller.Start, controller)
	end
end


local function Init()
	
	-- Load controllers:
	local function LoadAllControllers(parent, controllersTbl)
		for _,child in pairs(parent:GetChildren()) do
			if (child:IsA("ModuleScript")) then
				LoadController(child, controllersTbl)
			elseif (child:IsA("Folder")) then
				local tbl = {}
				controllersTbl[child.Name] = tbl
				LoadAllControllers(child, tbl)
			end
		end
	end
	
	-- Initialize controllers:
	local function InitAllControllers(controllers)
		-- Collect all controllers:
		local controllerTables = {}
		local function CollectControllers(_controllers)
			for _,controller in pairs(_controllers) do
				if (getmetatable(controller) == mt) then
					controllerTables[#controllerTables + 1] = controller
				else
					CollectControllers(controller)
				end
			end
		end
		CollectControllers(controllers)
		-- Sort controllers by optional __aeroOrder field:
		table.sort(controllerTables, function(a, b)
			local aOrder = (type(a.__aeroOrder) == "number" and a.__aeroOrder or math.huge)
			local bOrder = (type(b.__aeroOrder) == "number" and b.__aeroOrder or math.huge)
			return (aOrder < bOrder)
		end)
		-- Initialize controllers:
		for _,controller in ipairs(controllerTables) do
			InitController(controller)
		end
	end
	
	-- Start controllers:
	local function StartAllControllers(controllers)
		for _,controller in pairs(controllers) do
			if (getmetatable(controller) == mt) then
				StartController(controller)
			else
				StartAllControllers(controller)
			end
		end
	end

	-- Start modules that were already loaded:
	local function StartLoadedModules()
		for _,tbl in pairs(modulesAwaitingStart) do
			SpawnNow(tbl.Start, tbl)
		end
		modulesAwaitingStart = nil
	end

	------------------------------------------------------
	
	-- Lazy load modules:
	LazyLoadSetup(Aero.Modules, modulesFolder)
	LazyLoadSetup(Aero.Shared, sharedFolder)
	
	-- Load server-side services:
	LoadServices()

	-- Load, init, and start controllers:
	LoadAllControllers(controllersFolder, Aero.Controllers)
	InitAllControllers(Aero.Controllers)
	StartAllControllers(Aero.Controllers)
	StartLoadedModules()

	-- Expose client framework globally:
	_G.Aero = Aero
	
end


Init()
