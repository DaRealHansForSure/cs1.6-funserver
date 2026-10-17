// Fun GunGame - every kill moves you to the next weapon, the knife comes last.
//
// Only active while the server runs the "gungame" mode. Respawning, free for
// all and the infinite round come from ReGameDLL cvars in modes/gungame.cfg,
// this plugin only handles levels and weapons.
//
// Rules:
//   - A kill with your current weapon moves you up one level.
//   - A knife kill steals a level: you move up, the victim moves down.
//   - The first kill with the knife on the last level wins the map.

#include <amxmodx>
#include <cstrike>
#include <fun>
#include <hamsandwich>
#include <fun_common>

#pragma semicolon 1

#define PLUGIN_NAME "Fun GunGame"
#define PLUGIN_VERSION "1.0"
#define PLUGIN_AUTHOR "LAN"

#define TASK_EQUIP_PLAYER 5100
#define TASK_GRENADE_REFILL 5200
#define TASK_END_MAP 5300
#define TASK_ZBOT_HOOKS 5400

const Float:EQUIP_DELAY_SECONDS = 0.2;
const Float:GRENADE_REFILL_INTERVAL_SECONDS = 1.5;
const Float:END_MAP_DELAY_SECONDS = 8.0;
const FULL_ARMOR = 100;

new const LEVEL_WEAPONS[][] = {
    "weapon_glock18",
    "weapon_usp",
    "weapon_p228",
    "weapon_deagle",
    "weapon_fiveseven",
    "weapon_elite",
    "weapon_m3",
    "weapon_xm1014",
    "weapon_tmp",
    "weapon_mac10",
    "weapon_mp5navy",
    "weapon_ump45",
    "weapon_p90",
    "weapon_galil",
    "weapon_famas",
    "weapon_ak47",
    "weapon_m4a1",
    "weapon_sg552",
    "weapon_aug",
    "weapon_scout",
    "weapon_awp",
    "weapon_m249",
    "weapon_hegrenade",
    "weapon_knife"
};

new const LEVEL_TITLES[][] = {
    "Glock",
    "USP",
    "P228",
    "Desert Eagle",
    "Five-SeveN",
    "Dual Berettas",
    "M3 Shotgun",
    "XM1014",
    "TMP",
    "MAC-10",
    "MP5",
    "UMP45",
    "P90",
    "Galil",
    "FAMAS",
    "AK-47",
    "M4A1",
    "SG552",
    "AUG",
    "Scout",
    "AWP",
    "M249",
    "HE Grenade",
    "Knife"
};

new gPlayerLevel[MAX_PLAYERS + 1];
new gKillsOnLevel[MAX_PLAYERS + 1];
new bool:gIsGameWon;
new bool:gIsGunGameMode;
new bool:gAreZbotHooksRegistered;
new gKillsPerLevelCvar;
new gHudSync;

public plugin_init()
{
    register_plugin(PLUGIN_NAME, PLUGIN_VERSION, PLUGIN_AUTHOR);

    if (!is_fun_mode(FUN_MODE_GUNGAME)) {
        return;
    }
    gIsGunGameMode = true;

    gKillsPerLevelCvar = create_cvar("fun_gg_kills_per_level", "1", _, "Kills needed per level", true, 1.0, true, 10.0);

    register_event("DeathMsg", "onDeathMessage", "a");
    RegisterHam(Ham_Spawn, "player", "onPlayerSpawned", 1);
    RegisterHam(Ham_Touch, "weaponbox", "onWeaponTouched");
    RegisterHam(Ham_Touch, "armoury_entity", "onWeaponTouched");
    register_clcmd("drop", "blockCommand");

    gHudSync = CreateHudSyncObj();
    set_task(GRENADE_REFILL_INTERVAL_SECONDS, "refillGrenades", TASK_GRENADE_REFILL, _, _, "b");
}

public client_putinserver(playerId)
{
    gPlayerLevel[playerId] = 0;
    gKillsOnLevel[playerId] = 0;

    if (gIsGunGameMode && !gAreZbotHooksRegistered && is_zbot(playerId)) {
        set_task(FUN_ZBOT_HOOK_DELAY, "registerZbotHooks", TASK_ZBOT_HOOKS + playerId);
    }
}

public client_disconnected(playerId)
{
    remove_task(TASK_EQUIP_PLAYER + playerId);
    remove_task(TASK_ZBOT_HOOKS + playerId);
}

/**
 * zBot bots have their own vtable (see fun_common.inc), so the spawn hook
 * is registered once more on the first bot. All bots share that vtable,
 * a second registration would equip every bot twice.
 */
public registerZbotHooks(taskId)
{
    new botId = taskId - TASK_ZBOT_HOOKS;
    if (gAreZbotHooksRegistered || !is_user_connected(botId)) {
        return;
    }
    gAreZbotHooksRegistered = true;

    RegisterHamFromEntity(Ham_Spawn, botId, "onPlayerSpawned", 1);
}

public blockCommand(playerId)
{
    return PLUGIN_HANDLED;
}

public onWeaponTouched(weaponEntity, toucherId)
{
    // Picking up dropped guns would skip the level system.
    if (is_user_alive(toucherId)) {
        return HAM_SUPERCEDE;
    }
    return HAM_IGNORED;
}

public onPlayerSpawned(playerId)
{
    if (!is_user_alive(playerId)) {
        return;
    }

    // The game hands out its own spawn weapons right after this hook, so the
    // level weapon is given a moment later to replace them.
    remove_task(TASK_EQUIP_PLAYER + playerId);
    set_task(EQUIP_DELAY_SECONDS, "equipForLevel", TASK_EQUIP_PLAYER + playerId);
}

public equipForLevel(taskId)
{
    new playerId = taskId - TASK_EQUIP_PLAYER;
    if (!is_user_alive(playerId)) {
        return;
    }

    new level = gPlayerLevel[playerId];

    strip_user_weapons(playerId);
    give_item(playerId, "weapon_knife");

    if (!equal(LEVEL_WEAPONS[level], "weapon_knife")) {
        give_item(playerId, LEVEL_WEAPONS[level]);
        engclient_cmd(playerId, LEVEL_WEAPONS[level]);
    }

    giveFullBackpackAmmo(playerId, LEVEL_WEAPONS[level]);
    cs_set_user_armor(playerId, FULL_ARMOR, CS_ARMOR_VESTHELM);
    cs_set_user_money(playerId, 0, 0);

    showLevel(playerId);
}

giveFullBackpackAmmo(playerId, const weaponName[])
{
    new weaponId = get_weaponid(weaponName);
    if (weaponId == CSW_KNIFE || weaponId == CSW_HEGRENADE || weaponId == 0) {
        return;
    }

    // 200 is above every backpack limit, the game clamps it to the maximum.
    cs_set_user_bpammo(playerId, weaponId, 200);
}

public onDeathMessage()
{
    if (gIsGameWon) {
        return;
    }

    new killerId = read_data(1);
    new victimId = read_data(2);

    new isRealKill = (killerId != victimId && is_user_connected(killerId) && is_user_connected(victimId));
    if (!isRealKill) {
        return;
    }

    new weaponName[16];
    read_data(4, weaponName, charsmax(weaponName));

    new lastLevel = sizeof(LEVEL_WEAPONS) - 1;
    new wasKnifeKill = equal(weaponName, "knife");

    if (wasKnifeKill && gPlayerLevel[killerId] == lastLevel) {
        declareWinner(killerId);
        return;
    }

    if (wasKnifeKill) {
        stealLevel(killerId, victimId);
        return;
    }

    gKillsOnLevel[killerId]++;
    if (gKillsOnLevel[killerId] >= get_pcvar_num(gKillsPerLevelCvar)) {
        changeLevel(killerId, 1);
    } else {
        showLevel(killerId);
    }
}

stealLevel(killerId, victimId)
{
    new killerName[MAX_NAME_LENGTH], victimName[MAX_NAME_LENGTH];
    get_user_name(killerId, killerName, charsmax(killerName));
    get_user_name(victimId, victimName, charsmax(victimName));
    client_print(0, print_chat, "[GunGame] %s knifed %s and stole a level!", killerName, victimName);

    changeLevel(killerId, 1);
    if (gPlayerLevel[victimId] > 0) {
        changeLevel(victimId, -1);
    }
}

changeLevel(playerId, levelDelta)
{
    new lastLevel = sizeof(LEVEL_WEAPONS) - 1;
    gPlayerLevel[playerId] = clamp(gPlayerLevel[playerId] + levelDelta, 0, lastLevel);
    gKillsOnLevel[playerId] = 0;

    if (levelDelta > 0 && gPlayerLevel[playerId] == lastLevel) {
        new playerName[MAX_NAME_LENGTH];
        get_user_name(playerId, playerName, charsmax(playerName));
        client_print(0, print_chat, "[GunGame] %s reached the knife level!", playerName);
    }

    // Swap the weapon right away, waiting for the next spawn feels sluggish.
    if (is_user_alive(playerId)) {
        equipForLevel(TASK_EQUIP_PLAYER + playerId);
    }
}

showLevel(playerId)
{
    new level = gPlayerLevel[playerId];
    new killsNeeded = get_pcvar_num(gKillsPerLevelCvar);

    set_hudmessage(255, 200, 0, -1.0, 0.85, 0, 0.0, 3.0, 0.1, 0.5, -1);
    ShowSyncHudMsg(playerId, gHudSync, "Level %d/%d: %s  (%d/%d Kills)", level + 1, sizeof(LEVEL_WEAPONS), LEVEL_TITLES[level], gKillsOnLevel[playerId], killsNeeded);
}

public refillGrenades()
{
    new grenadeLevel = sizeof(LEVEL_WEAPONS) - 2;

    new players[MAX_PLAYERS], playerCount;
    get_players(players, playerCount, "a");

    for (new i = 0; i < playerCount; i++) {
        new playerId = players[i];
        if (gPlayerLevel[playerId] == grenadeLevel && !user_has_weapon(playerId, CSW_HEGRENADE)) {
            give_item(playerId, "weapon_hegrenade");
        }
    }
}

declareWinner(winnerId)
{
    gIsGameWon = true;

    new winnerName[MAX_NAME_LENGTH];
    get_user_name(winnerId, winnerName, charsmax(winnerName));

    set_hudmessage(0, 255, 0, -1.0, 0.3, 1, 1.0, END_MAP_DELAY_SECONDS, 0.2, 0.5, -1);
    show_hudmessage(0, "%s won GunGame!", winnerName);
    client_print(0, print_chat, "[GunGame] %s won! Next map in %d seconds.", winnerName, floatround(END_MAP_DELAY_SECONDS));
    client_cmd(0, "spk buttons/bell1");

    set_task(END_MAP_DELAY_SECONDS, "changeToNextMap", TASK_END_MAP);
}

public changeToNextMap()
{
    new nextMap[MAX_MAPNAME_LENGTH];
    get_cvar_string("amx_nextmap", nextMap, charsmax(nextMap));

    if (!is_map_valid(nextMap)) {
        get_mapname(nextMap, charsmax(nextMap));
    }

    server_cmd("changelevel %s", nextMap);
}
