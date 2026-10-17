// Fun Deathrun - round logic for the deathrun mode.
//
// Each round one player becomes the Terrorist who triggers the traps,
// everybody else runs the course as CT. Humans are preferred as trapper
// (bots do not press trap buttons) and nobody is trapper twice in a row.
// Everybody starts with a knife only, weapons the map hands out at the end of
// the course can still be picked up. Team balance and bots are switched off
// in modes/deathrun.cfg.

#include <amxmodx>
#include <cstrike>
#include <fun>
#include <hamsandwich>
#include <fun_common>

#pragma semicolon 1

#define PLUGIN_NAME "Fun Deathrun"
#define PLUGIN_VERSION "1.0"
#define PLUGIN_AUTHOR "LAN"

#define TASK_EQUIP_PLAYER 9600
#define TASK_ZBOT_HOOKS 9650

const Float:EQUIP_DELAY_SECONDS = 0.2;
const NO_PLAYER = 0;

new bool:gIsDeathrunMode;
new bool:gAreZbotHooksRegistered;
new gTrapperId = NO_PLAYER;
new gLastTrapperId = NO_PLAYER;
new gHudSync;

public plugin_init()
{
    register_plugin(PLUGIN_NAME, PLUGIN_VERSION, PLUGIN_AUTHOR);

    gIsDeathrunMode = is_fun_mode(FUN_MODE_DEATHRUN);
    if (!gIsDeathrunMode) {
        return;
    }

    register_event("HLTV", "onNewRound", "a", "1=0", "2=0");
    RegisterHam(Ham_Spawn, "player", "onPlayerSpawned", 1);

    gHudSync = CreateHudSyncObj();
}

public client_putinserver(playerId)
{
    if (!gIsDeathrunMode || gAreZbotHooksRegistered || !is_zbot(playerId)) {
        return;
    }
    set_task(FUN_ZBOT_HOOK_DELAY, "registerZbotHooks", TASK_ZBOT_HOOKS + playerId);
}

/**
 * zBot bots have their own vtable (see fun_common.inc), so the spawn hook
 * is registered once more on the first bot. All bots share that vtable,
 * a second registration would run the handler twice per spawn.
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

public client_disconnected(playerId)
{
    remove_task(TASK_EQUIP_PLAYER + playerId);
    remove_task(TASK_ZBOT_HOOKS + playerId);

    if (playerId == gTrapperId) {
        gTrapperId = NO_PLAYER;
    }
    if (playerId == gLastTrapperId) {
        gLastTrapperId = NO_PLAYER;
    }
}

public onNewRound()
{
    gTrapperId = chooseTrapper();
    if (gTrapperId == NO_PLAYER) {
        return;
    }
    gLastTrapperId = gTrapperId;

    // HLTV fires before the players respawn, so the new teams spawn on the
    // right side of the map.
    for (new playerId = 1; playerId <= MaxClients; playerId++) {
        if (!is_user_connected(playerId)) {
            continue;
        }

        new CsTeams:team = cs_get_user_team(playerId);
        if (team != CS_TEAM_T && team != CS_TEAM_CT) {
            continue;
        }

        if (playerId == gTrapperId) {
            cs_set_user_team(playerId, CS_TEAM_T, CS_T_LEET);
        } else {
            cs_set_user_team(playerId, CS_TEAM_CT, CS_CT_URBAN);
        }
    }

    new trapperName[MAX_NAME_LENGTH];
    get_user_name(gTrapperId, trapperName, charsmax(trapperName));
    set_hudmessage(255, 60, 60, -1.0, 0.25, 0, 0.0, 5.0, 0.1, 0.5);
    ShowSyncHudMsg(0, gHudSync, "DEATHRUN^n%s sets the traps. Everybody else: run!", trapperName);
}

/**
 * Picks a random human who was not the trapper last round. Falls back to a
 * bot, and to the last trapper only when nobody else is playing.
 */
chooseTrapper()
{
    new humans[MAX_PLAYERS], humanCount = 0;
    new bots[MAX_PLAYERS], botCount = 0;

    for (new playerId = 1; playerId <= MaxClients; playerId++) {
        if (!is_user_connected(playerId) || is_user_hltv(playerId) || playerId == gLastTrapperId) {
            continue;
        }

        new CsTeams:team = cs_get_user_team(playerId);
        if (team != CS_TEAM_T && team != CS_TEAM_CT) {
            continue;
        }

        if (is_user_bot(playerId)) {
            bots[botCount++] = playerId;
        } else {
            humans[humanCount++] = playerId;
        }
    }

    if (humanCount > 0) {
        return humans[random(humanCount)];
    }
    if (botCount > 0) {
        return bots[random(botCount)];
    }
    if (gLastTrapperId != NO_PLAYER && is_user_connected(gLastTrapperId)) {
        return gLastTrapperId;
    }
    return NO_PLAYER;
}

public onPlayerSpawned(playerId)
{
    if (!is_user_alive(playerId)) {
        return;
    }

    // Somebody who joined the Terrorists mid game would be a second trapper.
    if (cs_get_user_team(playerId) == CS_TEAM_T && gTrapperId != NO_PLAYER && playerId != gTrapperId) {
        cs_set_user_team(playerId, CS_TEAM_CT, CS_CT_URBAN);
        ExecuteHamB(Ham_CS_RoundRespawn, playerId);
        return;
    }

    remove_task(TASK_EQUIP_PLAYER + playerId);
    set_task(EQUIP_DELAY_SECONDS, "equipKnifeOnly", TASK_EQUIP_PLAYER + playerId);
}

public equipKnifeOnly(taskId)
{
    new playerId = taskId - TASK_EQUIP_PLAYER;
    if (!is_user_alive(playerId)) {
        return;
    }

    strip_user_weapons(playerId);
    give_item(playerId, "weapon_knife");
}

public CS_OnBuyAttempt(playerId, item)
{
    if (gIsDeathrunMode) {
        return PLUGIN_HANDLED;
    }
    return PLUGIN_CONTINUE;
}
