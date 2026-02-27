-- Main animation module. Instantiates all character dependent animation tracks

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AnimStateId = require(ReplicatedStorage.Shared.Enums.AnimationStateId)

local Animation = {}
Animation.__index = Animation

Animation.states = {
	-- idle (0)
	[AnimStateId.DEATH] = {id = "rbxassetid://86228921476914", prio = 0},
	[AnimStateId.IDLE] = {id = "rbxassetid://112935245839336", prio = 0},
	--[AnimStateId.IDLE] = {id = "http://www.roblox.com/asset/?id=180435571", prio = 0},
	-- movement (1)
	[AnimStateId.WALK] = {id = "rbxassetid://131022707317400", prio = 1},
    --[AnimStateId.WALK] = {id = "http://www.roblox.com/asset/?id=180426354", prio = 1},

	--TODO
	--SWIM = "",
	--FALL = "",
	-- actions (2-5)
}

export type AnimationStateType = {
    id: string,
	prio: number
}

function Animation.new(simulation)
    local self = setmetatable({}, Animation)

	self.character = simulation.character :: Model
	self.animationController = self.character:FindFirstChildOfClass("AnimationController")
	self.animator = self.animationController:FindFirstChildOfClass("Animator")

	self.currentState = "None"
	self.animTracks = {} :: {[string]: AnimationTrack}

	for animName: string, animData: AnimationStateType in pairs(self.states) do
		local animInst = Instance.new("Animation", self.animator)
		animInst.AnimationId = animData.id
		animInst.Name = animName

		self.animTracks[animName] = self.animator:LoadAnimation(animInst) :: AnimationTrack
		self.animTracks[animName].Priority = animData.prio
		self.animTracks[animName].Stopped:Connect(function()
			--print(animName .. " WAS STOPPED")
		end)
		self.animTracks[animName].Ended:Connect(function()
			--print(animName .. " HAS ENDEDEDED")
		end)
	end

	return self
end

function Animation:setState(newState: string, f_t: number?)
	if (not newState) then
		error("missing newState parameter")
	end
	if (newState == self.currentState) then
		return
	end
	local fade = f_t or 0.100000001

	if (self.animTracks[self.currentState]) then
		self.animTracks[self.currentState]:Stop()
	end
	self.currentState = newState
	self.animTracks[self.currentState]:Play(fade)
end

function Animation:adjustSpeed(speed: number)
	if (speed == self.animTracks[self.currentState].Speed) then
		return
	end
	self.animTracks[self.currentState]:AdjustSpeed(speed)
end

function Animation:destroy()
	for i, animTrack: AnimationTrack in pairs(self.animTracks) do
		animTrack:Destroy()
		self.animTracks[i] = nil
	end

	setmetatable(self, nil)
end

return Animation