![Logo](/imgs/logo_github_readme.png)

# AeroGameFramework
A powerful game framework for the Roblox platform.

AeroGameFramework is a Roblox game framework that makes development easy and fun. The framework is designed to simplify the communication between modules and seamlessly bridge the gap between the server and client. Never again will you have to touch RemoteFunctions or RemoteEvents.

# Documentation
Visit the [documentation site](https://sleitnick.github.io/AeroGameFramework).

# Custom Functions by WorldPosition

Here is an example showing :GetPropertyChangedEvent(PropertyName) and :RegisterProperty(Name)
```lua
local TestController = {}


function TestController:Start()
	self:GetPropertyChangedEvent("Enabled"):Connect(function(New, Old)
		print("New Property: ", New, "Old Property: ", Old);
	end)
	self.Enabled = true;
	self:Log("Hello World!");
end


function TestController:Init()
	self:RegisterProperty("Enabled");
end


return TestController
```

I've also added a :Log(text) function which will print the text, while also displaying the name of the script that called it.
```lua
self:Log("Hello World!");
```

# Example

Here is an example of a client-side controller invoking a server-side service to respawn the player. Notice that no remote objects have to be explicitly referenced:

```lua
-- Client:
local MyController = {}

function MyController:Start()
	local didRespawn = self.Services.MyService:Respawn()
	if (didRespawn) then
		...
	end
end

return MyController
```

```lua
-- Server:
local MyService = {Client = {}}

function MyService.Client:Respawn(player)

	local humanoid = player.Character and player.Character:FindFirstChild("Humanoid")

	-- Only allow respawning if the player is dead:
	if ((not humanoid) or humanoid.Health == 0) then
		player:LoadCharacter()
		return true
	end

	return false

end

return MyService
```

These are complete code examples. They could be put into the framework and work as-is.
