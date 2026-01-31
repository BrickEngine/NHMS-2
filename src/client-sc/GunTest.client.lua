local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local ClientRoot = require(ReplicatedStorage.Shared.ClientRoot)
local PlayerStateId = require(ReplicatedStorage.Shared.Enums.PlayerStateId)

local VEC3_UP = Vector3.new(0, 1, 0)
local PI_2 = math.pi * 2

local cam = Workspace.CurrentCamera

local plr = Players.LocalPlayer
local char = plr.Character

local viewPortGui = Instance.new("ScreenGui", plr:WaitForChild("PlayerGui"))
viewPortGui.Name = "ViewportGui"
local viewPortFrame = Instance.new("ViewportFrame", viewPortGui)
viewPortFrame.CurrentCamera = Workspace.CurrentCamera
viewPortFrame.Size = UDim2.new(1, 0, 1, 0)
--viewPortFrame.Transparency = 1
viewPortFrame.BackgroundTransparency = 1

-- local mdl = Instance.new("Model", viewPortFrame)
-- local part = Instance.new("Part", mdl)
-- mdl.PrimaryPart = part
-- part.Anchored = true
-- part.CanCollide = false
-- part.CanQuery = false
-- part.CanTouch = false
-- part.CollisionGroup = CollisionGroup.NOCOLL
-- part.Size = Vector3.new(1,1,3)

local mdl = ReplicatedStorage.Models["Test Gun"]
mdl.Parent = viewPortFrame
local gunPart = mdl.PrimaryPart

if (not char) then
    error("no char")
end

assert(char.PrimaryPart)

local circT = 0
local function updateFunc(dt: number)
    local primaryPart: BasePart = char.PrimaryPart
    local horiVel = primaryPart.AssemblyLinearVelocity
    horiVel = Vector3.new(horiVel.X, 0, horiVel. Z)
    local velFac = math.clamp(horiVel.Magnitude, 0, 25)

    local velTimeFac = math.clamp(velFac * 0.1, 0, 6)
    if (
        horiVel.Magnitude < 0.05 or ClientRoot.getPlayerState() == PlayerStateId.ON_WALL
        or not ClientRoot.getIsGrounded()
    ) then
        circT = 0
    end
    
    local pvOffset = VEC3_UP * math.sin(circT * 7) * 0.06 * velTimeFac

    --2.5,-1.5,-1
    mdl:PivotTo(
        cam.CFrame * CFrame.new(1.08, -0.9, -1) * CFrame.Angles(0, math.rad(180), 0)
    )
    mdl:PivotTo(gunPart.CFrame * CFrame.new(pvOffset))

    circT += dt
    if (circT >= PI_2) then
        circT = 0
    end
end

local updateConnection = RunService:BindToRenderStep("GunUpdate", Enum.RenderPriority.Camera.Value, updateFunc)

plr.CharacterRemoving:Connect(function(character)
    if (updateConnection) then
        updateConnection:Disconnect()
    end
end)

