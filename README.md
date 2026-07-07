# Spawn Point Tool

A Garry's Mod Toolgun addon for creating personal respawn points. Admins can also place global respawn points that apply to everyone. Multiple points on a map are chosen at random.

## Install

Subscribe on the Steam Workshop:

https://steamcommunity.com/sharedfiles/filedetails/?id=3738661916

Restart Garry's Mod or let the Workshop download finish, then find it in the Toolgun menu under `Spawn Point Tool`.

For local development, this addon folder can also be placed at `garrysmod/addons/SpawnPointTool`.

Expected layout:

- `lua/autorun/client/spt_client.lua`
- `lua/autorun/spt_core.lua`
- `lua/autorun/server/spt_server.lua`
- `lua/spawnpointtool/*.lua`
- `lua/weapons/gmod_tool/stools/spawnpoint.lua`
- `materials/SpawnPointTool/spawndecal.vmt`
- `materials/SpawnPointTool/spawndecal.vtf`

## Controls

- Left-click a non-sky surface to add a respawn point.
- Right-click near one of your spawn markers to remove it.
- Reload clears your respawn points on the current map.
- Respawn points preserve the direction you were facing when placed.
- The blue preview shows where the next marker will be placed.
- Admin global placement uses a gold preview and gold markers.
- A red preview means the player hull check thinks the spot is blocked.
- Other players' markers appear with a blue tint when shared markers are enabled.
- Nearby markers show floating labels with owner name and spawn index. Global markers show `Global`.
- The optional danger check prefers respawn points without nearby NPCs or NextBots.
- The HUD shows your current respawn point count while the tool is held.
- Admins can hold the global hotkey, Left Alt by default, or enable sticky global placement.

## Tool Options

- `Persist across sessions` saves your current map respawn points immediately and keeps future changes saved under `spawnpointtool/<map>/<steamid>.json`.
- `Check player hull before placement` rejects cramped respawn points.
- `Use my respawn points` lets players temporarily return to normal map spawns without deleting their points.
- `Always show synced markers` keeps synced markers visible without holding the tool.
- `Toggle global placement` lets admins use the same tool controls for global points.
- `Global hold key` changes the admin global placement hotkey.
- Admins can configure custom respawns, marker visibility, max respawn points, remove radius, spawn surface offset, danger checking, and respawn-time hull checks.
- Admins can reset server settings to their defaults from the tool menu.
- `Delete this map's respawn points...` removes your saved points on the current map.
- `Delete all saved respawn points...` removes your saved points across every map.

## ConVars

- `spawnpoint_enabled 1`: use your personal respawn points.
- `spawnpoint_global_sticky 0`: keep admin global placement enabled.
- `spawnpoint_global_hotkey 81`: admin global placement hold key.
- `spawnpoint_global_mode 0`: active admin global placement state.
- `spt_enabled 1`: enable custom respawns server-wide.
- `spt_marker_visibility 0`: users holding the tool can see only their own markers.
- `spt_marker_visibility 1`: admins can see all spawn markers.
- `spt_marker_visibility 2`: everyone can see all spawn markers.
- `spt_max_spawns 32`: maximum respawn points per player or global set.
- `spt_delete_radius 64`: distance used when right-click removing an aimed respawn point.
- `spt_spawn_offset 8`: distance players are moved away from the saved surface when respawning.
- `spt_danger_check 1`: prefer respawn points without nearby NPCs or NextBots.
- `spt_danger_radius 256`: radius used when checking whether a respawn point is dangerous.
- `spt_respawn_hull_check 0`: check whether saved points are blocked before respawning.

## Admin Commands

- `spt_list_counts`: list loaded global and player respawn point counts.
- `spt_clear_player <name|steamid>`: clear a player's current-map respawn points.

The placed marker uses an opaque alpha-tested material. The live placement preview is drawn separately as a translucent overlay.

Marker sharing is off by default for privacy and server performance. Clients request marker data when the Spawn Point Tool is selected or Always Show is enabled.

Personal points save under `spawnpointtool/<map>/<steamid>.json`. Global points save under `spawnpointtool/<map>/global.json`. The save format is `{ "spawns": [...] }`; older single-spawn save files are ignored.

## Links

- Steam Workshop: https://steamcommunity.com/sharedfiles/filedetails/?id=3738661916
- GitHub: https://github.com/DeisDev/SpawnPointTool
