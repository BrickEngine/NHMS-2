-- local ReplicatedStorage = game:GetService("ReplicatedStorage")
-- local RunService = game:GetService("RunService")

local WeaponCommon = {}

function WeaponCommon.joinWeaponToOwnerPrimPart(weaponMdl: Model, ownerMdl: Model)
    local joint = Instance.new("Motor6D", weaponMdl.PrimaryPart)
    joint.Name = "WeaponM6D"
    joint.Part0 = ownerMdl.PrimaryPart
    joint.Part1 = weaponMdl.PrimaryPart

    return joint
end

function WeaponCommon.equipWeaponModelGlobal(mdl: Model, offsetPos: CFrame)

end

return WeaponCommon