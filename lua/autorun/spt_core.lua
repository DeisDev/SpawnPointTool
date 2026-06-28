if SERVER then
    AddCSLuaFile()
    AddCSLuaFile("spawnpointtool/sh_config.lua")
    AddCSLuaFile("spawnpointtool/sh_util.lua")
    AddCSLuaFile("spawnpointtool/cl_markers.lua")
    AddCSLuaFile("spawnpointtool/cl_menu.lua")
end

include("spawnpointtool/sh_config.lua")
include("spawnpointtool/sh_util.lua")
