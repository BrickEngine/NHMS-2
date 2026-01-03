local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local Global = require(ReplicatedStorage.Shared.Global)

local cam = Workspace.CurrentCamera

local plr = Players.LocalPlayer
local char = plr.Character

local mdl = Instance.new("Model", char)
local part = Instance.new("Part", mdl)
part.Anchored = true
part.CanCollide = false
part.CanQuery = false
part.CanTouch = false
part.CollisionGroup = Global.COLL_GROUPS.NOCOLL
part.Size = Vector3.new(1,1,3)

mdl:PivotTo(cam.CFrame)

if (not char) then
    error("no char")
end

local function updateFunc()
    mdl:PivotTo(cam.CFrame * CFrame.new(
        2.5,-1.5,-1
    ))
end

RunService:BindToRenderStep("GunUpdate", Enum.RenderPriority.Camera.Value, updateFunc)

plr.CharacterRemoving:Connect(function(character)
    updateFunc:Disconnect()
end)

