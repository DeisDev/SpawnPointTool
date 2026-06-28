SpawnPointTool = SpawnPointTool or {}

local SPT = SpawnPointTool

SPT.VERSION = "1.1.0"
SPT.VERSION_LABEL = "v" .. SPT.VERSION
SPT.AUTHOR = "cat sniffer"
SPT.AUTHOR_STEAM_ID64 = "76561199216202475"

SPT.Links = {
    Workshop = "https://steamcommunity.com/sharedfiles/filedetails/?id=3738661916",
    SteamProfile = "https://steamcommunity.com/profiles/76561199216202475",
    GitHub = "https://github.com/DeisDev/SpawnPointTool",
    Issues = "https://github.com/DeisDev/SpawnPointTool/issues/new/choose"
}

SPT.HULL_MINS = Vector(-16, -16, 0)
SPT.HULL_MAXS = Vector(16, 16, 72)

SPT.Net = {
    SyncMarkers = "spt_sync_markers",
    RequestMarkers = "spt_request_markers",
    ClearCurrentRequest = "spt_clear_current_request",
    ClearAllRequest = "spt_clear_all_request",
    AdminSetting = "spt_admin_setting",
    PersistChanged = "spt_persist_changed"
}

SPT.MarkerVisibility = {
    OwnOnly = 0,
    Admins = 1,
    Everyone = 2
}

SPT.AdminSetting = {
    Enabled = 1,
    MarkerVisibility = 2,
    MaxSpawns = 3,
    DeleteRadius = 4,
    SpawnOffset = 5,
    DangerCheck = 6,
    DangerRadius = 7,
    RespawnHullCheck = 8,
    ResetDefaults = 9
}

SPT.ServerDefaults = {
    Enabled = 1,
    ShowAllMarkers = 0,
    MarkerVisibility = SPT.MarkerVisibility.OwnOnly,
    MaxSpawns = 32,
    DeleteRadius = 64,
    SpawnOffset = 8,
    DangerCheck = 1,
    DangerRadius = 256,
    RespawnHullCheck = 0
}

SPT.ClientDefaults = {
    Enabled = 1,
    Persist = 0,
    HullCheck = 1,
    AlwaysShow = 0
}
