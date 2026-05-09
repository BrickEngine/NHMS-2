local WeaponCommon = {}

function WeaponCommon.joinWeaponToOwnerPrimPart(weaponMdl: Model, ownerMdl: Model)
    local joint = Instance.new("Motor6D", ownerMdl.PrimaryPart)
    joint.Name = "WeaponM6D"
    joint.Part0 = ownerMdl.PrimaryPart
    joint.part1 = weaponMdl.PrimaryPart
    
    return joint
end

function WeaponCommon.equipWeaponModelGlobal(mdl: Model, offsetPos: CFrame)

end

return WeaponCommon