local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Global = require(ReplicatedStorage.Shared.Global)
local CollisionGroup = require(ReplicatedStorage.Shared.Enums.CollisionGroup)

-- local DEBUG_COLL_COLOR3 = Color3.fromRGB(0, 0, 255)

local PLAYERMDL_MASS_ENABLED = false
local MAIN_ROOT_PRIO = 100

local PRINT_PLRMDL_UNUSED_WARNING = false

------------------------------------------------------------------------------------------------------------------------
-- character phys model parameters

local PARAMS = table.freeze({
    ROOT_ATT_NAME = "Root",
    ROOTPART_SIZE = Vector3.new(1, 1, 1),
    MAINCOLL_SIZE = Vector3.new(3, 3, 3),
    LEGCOLL_SIZE = Vector3.new(2, 3, 3),

    ROOTPART_SHAPE = Enum.PartType.Block,
    MAINCOLL_SHAPE = Enum.PartType.Cylinder,
    LEGCOLL_SHAPE = Enum.PartType.Cylinder,

    ROOTPART_NAME = "RootPart",
    MAINCOLL_NAME = "MainColl",
    LEGCOLL_NAME = "LegColl",

    ROOTPART_CF = CFrame.identity,
    MAINCOLL_CF = CFrame.new(
        0, 1.5, 0,
        0, -1, 0,
        1, 0, 0,
        0, 0, 1
    ),
    LEGCOLL_CF = CFrame.new(
        0, -1, 0,
        0, -1, 0,
        1, 0, 0,
        0, 0, 1
    ),
    PLAYERMODEL_OFFSET_CF = CFrame.new(
        0, -0.3, 0, --0, 1, 0
        1, 0, 0,
        0, 1, 0,
        0, 0, 1
    ),
    PHYS_PROPERTIES = PhysicalProperties.new(
        1, 0, 0, 100, 100
    )
})

------------------------------------------------------------------------------------------------------------------------

local function setCollGroup(mdl: Model)
    for _, v: Instance in pairs(mdl:GetDescendants()) do
        if (v:IsA("BasePart")) then
            v.CollisionGroup = CollisionGroup.PLAYER
        end
    end
end

local function setMdlTransparency(mdl: Model, val: number)
    for _, v: Instance in pairs(mdl:GetChildren()) do
        if (v:IsA("BasePart")) then
            v.Transparency = val
        elseif (v:IsA("Model")) then
            setMdlTransparency(v, val)
        end
    end
end

local function createPart(name: string, size: Vector3, cFrame: CFrame, shape: Enum.PartType): BasePart
    local part = Instance.new("Part")
    part.Name = name; part.Size = size; part.CFrame = cFrame
    part.Shape = shape; part.Transparency = 1; part.Anchored = false
    part.CustomPhysicalProperties = PARAMS.PHYS_PROPERTIES
    return part
end

local function createParentedAttachment(name: string, parent: BasePart): Attachment
    local attachment = Instance.new("Attachment")
    attachment.Parent = parent
    return attachment
end

local function createParentedWeld(p0: BasePart, p1: BasePart): WeldConstraint
    local weldConstraint = Instance.new("WeldConstraint")
    weldConstraint.Part0 = p0; weldConstraint.Part1 = p1
    weldConstraint.Parent = p0
    return weldConstraint
end

local function createCharacter(playermodel: Model?): Model
    if (not RunService:IsServer()) then
        error("createCharacter should only be called on the server")
    end

    local character = Instance.new("Model")
    local rootPart = createPart(PARAMS.ROOTPART_NAME, PARAMS.ROOTPART_SIZE, PARAMS.ROOTPART_CF, PARAMS.ROOTPART_SHAPE)
    local mainColl = createPart(PARAMS.MAINCOLL_NAME, PARAMS.MAINCOLL_SIZE, PARAMS.MAINCOLL_CF, PARAMS.MAINCOLL_SHAPE)
    local legColl = createPart(PARAMS.LEGCOLL_NAME, PARAMS.LEGCOLL_SIZE, PARAMS.LEGCOLL_CF, PARAMS.LEGCOLL_SHAPE)

    rootPart.Parent, mainColl.Parent, legColl.Parent = character, character, character
    rootPart.CanCollide, rootPart.CanQuery, rootPart.CanTouch = false, false, false
    createParentedWeld(rootPart, mainColl)
    createParentedWeld(rootPart, legColl)
    legColl.CanCollide = false
    
    rootPart.Massless = true
    rootPart.RootPriority = MAIN_ROOT_PRIO
    character.PrimaryPart = rootPart
    createParentedAttachment("Root", rootPart)

    -- playermodel with assigned PrimaryPart is required
    if (not playermodel) then
        error("No Playermodel found", 2)
    end
    if (not playermodel.PrimaryPart) then
        error("Playermodel has no set PrimaryPart", 2)
    end

    local plrMdlClone = playermodel:Clone()
    local plrMdlPrimPart = plrMdlClone.PrimaryPart

    for _, inst: Instance in pairs(plrMdlClone:GetDescendants()) do
        if (inst:IsA("BasePart")) then
            inst.Parent = character
            inst.CanCollide = false
            inst:AddTag(Global.PLAYER_CHARACTER_TAG_NAME)

            if (not PLAYERMDL_MASS_ENABLED) then
                inst.Massless = true
            end
        elseif (inst:IsA("Model") or inst:IsA("Folder")) then
            (inst :: Instance).Parent = character
        end
    end
    plrMdlPrimPart.CFrame = rootPart.CFrame * PARAMS.PLAYERMODEL_OFFSET_CF
    createParentedWeld(rootPart, plrMdlPrimPart)

    -- discard playermodel with remaining unused components
    if (#(plrMdlClone:GetDescendants()) > 0 and PRINT_PLRMDL_UNUSED_WARNING) then
        warn("Playermodel included unused components, which were discarded:")
        warn(plrMdlClone:GetDescendants())
    end
    plrMdlClone:Destroy()

    -- create Animator and AnimationController
    local animController = Instance.new("AnimationController", character)
    Instance.new("Animator", animController)

    -- player characters should never be streamed out for other clients
    if (Workspace.StreamingEnabled) then
        character.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
    end

    return character
end

------------------------------------------------------------------------------------------------------------------------
-- Module
------------------------------------------------------------------------------------------------------------------------

local CharacterDef = {}
CharacterDef.__index = CharacterDef

function CharacterDef.new()
    local self = setmetatable({}, CharacterDef)

    self.PARAMS = PARAMS

    return self
end

-- Can only be called on the server
function CharacterDef.createCharacter(playerModel: Model): Model
    if (not RunService:IsServer()) then
        error("character should be created from server")
    end

    local character = createCharacter(playerModel)
    setCollGroup(character)

    return character
end

return CharacterDef.new()