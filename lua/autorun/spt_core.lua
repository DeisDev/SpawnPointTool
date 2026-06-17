if SERVER then
    AddCSLuaFile()
end

SpawnPointTool = SpawnPointTool or {}

-- Bump this value for each Workshop release.
SpawnPointTool.VERSION = "1.0.3"
SpawnPointTool.VERSION_LABEL = "v." .. SpawnPointTool.VERSION
SpawnPointTool.AUTHOR = "cat sniffer"
