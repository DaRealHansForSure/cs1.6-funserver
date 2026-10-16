// Fun Streaks - rewards for kills in a row, in every mode.
//
// Every 5 kills without dying: a short gold glow and +50 HP (at most 255).
// Every 10 kills: on top of that a rocket jump and a message to everybody.
// Dying resets the streak. Cvar: fun_streaks_enabled (1).
//
// The glow remembers how the player looked before (an admin glow, a ghost
// round) and puts exactly that back afterwards.

#include <amxmodx>
#include <fakemeta>
#include <fun>

#pragma semicolon 1

#define PLUGIN_NAME "Fun Streaks"
#define PLUGIN_VERSION "1.0"
#define PLUGIN_AUTHOR "LAN"

#define TASK_END_GLOW 9900

const SMALL_STREAK = 5;
const BIG_STREAK = 10;
const STREAK_HEALTH_BONUS = 50;

// The HUD shows up to 255, more would look broken.
const MAX_STREAK_HEALTH = 255;

const Float:STREAK_GLOW_SECONDS = 5.0;
const Float:ROCKET_JUMP_SPEED = 900.0;
const STREAK_GLOW_THICKNESS = 30;

new gStreak[MAX_PLAYERS + 1];
new bool:gIsGlowing[MAX_PLAYERS + 1];

// The look before the streak glow: renderfx, rendermode, renderamt, color.
new gSavedRenderFx[MAX_PLAYERS + 1];
new gSavedRenderMode[MAX_PLAYERS + 1];
new Float:gSavedRenderAmount[MAX_PLAYERS + 1];
new Float:gSavedRenderColor[MAX_PLAYERS + 1][3];

new gEnabledCvar;

new const ROCKET_SOUND[] = "weapons/rocketfire1.wav";

public plugin_precache()
{
    precache_sound(ROCKET_SOUND);
}

public plugin_init()
{
    register_plugin(PLUGIN_NAME, PLUGIN_VERSION, PLUGIN_AUTHOR);

    gEnabledCvar = create_cvar("fun_streaks_enabled", "1", _, "Kill streak rewards on (1) or off (0)", true, 0.0, true, 1.0);
    register_event("DeathMsg", "onDeath", "a");
}

public client_putinserver(playerId)
{
    gStreak[playerId] = 0;
    gIsGlowing[playerId] = false;
}

public client_disconnected(playerId)
{
    remove_task(TASK_END_GLOW + playerId);
    gStreak[playerId] = 0;
    gIsGlowing[playerId] = false;
}

public onDeath()
{
    new killerId = read_data(1);
    new victimId = read_data(2);

    if (victimId >= 1 && victimId <= MaxClients) {
        gStreak[victimId] = 0;
    }

    // World kills (falls, traps) and suicides do not count.
    if (killerId < 1 || killerId > MaxClients || killerId == victimId || !is_user_alive(killerId)) {
        return;
    }
    if (!get_pcvar_num(gEnabledCvar)) {
        return;
    }

    gStreak[killerId]++;
    if (gStreak[killerId] % SMALL_STREAK != 0) {
        return;
    }

    rewardStreak(killerId, gStreak[killerId]);
}

rewardStreak(playerId, streak)
{
    new health = min(get_user_health(playerId) + STREAK_HEALTH_BONUS, MAX_STREAK_HEALTH);
    set_user_health(playerId, health);
    startStreakGlow(playerId);

    new playerName[MAX_NAME_LENGTH];
    get_user_name(playerId, playerName, charsmax(playerName));
    log_amx("Kill streak: %s has %d kills in a row", playerName, streak);

    if (streak % BIG_STREAK == 0) {
        rocketJump(playerId);
        client_print(0, print_chat, "[Fun] %s: %d kills in a row! +%d HP and a rocket jump.", playerName, streak, STREAK_HEALTH_BONUS);
        client_cmd(0, "spk ambience/thunder_clap");
        return;
    }

    client_print(playerId, print_chat, "[Fun] %d kills in a row! +%d HP.", streak, STREAK_HEALTH_BONUS);
}

rocketJump(playerId)
{
    new Float:velocity[3];
    pev(playerId, pev_velocity, velocity);
    velocity[2] = ROCKET_JUMP_SPEED;
    set_pev(playerId, pev_velocity, velocity);
    emit_sound(playerId, CHAN_WEAPON, ROCKET_SOUND, VOL_NORM, ATTN_NORM, 0, PITCH_NORM);
}

startStreakGlow(playerId)
{
    // A streak during a streak glow keeps the look saved by the first one.
    if (!gIsGlowing[playerId]) {
        gSavedRenderFx[playerId] = pev(playerId, pev_renderfx);
        gSavedRenderMode[playerId] = pev(playerId, pev_rendermode);
        pev(playerId, pev_renderamt, gSavedRenderAmount[playerId]);
        pev(playerId, pev_rendercolor, gSavedRenderColor[playerId]);
        gIsGlowing[playerId] = true;
    }

    set_user_rendering(playerId, kRenderFxGlowShell, 255, 200, 0, kRenderNormal, STREAK_GLOW_THICKNESS);
    remove_task(TASK_END_GLOW + playerId);
    set_task(STREAK_GLOW_SECONDS, "endStreakGlow", TASK_END_GLOW + playerId);
}

public endStreakGlow(taskId)
{
    new playerId = taskId - TASK_END_GLOW;
    if (!gIsGlowing[playerId]) {
        return;
    }
    gIsGlowing[playerId] = false;

    if (!is_user_connected(playerId)) {
        return;
    }
    set_pev(playerId, pev_renderfx, gSavedRenderFx[playerId]);
    set_pev(playerId, pev_rendermode, gSavedRenderMode[playerId]);
    set_pev(playerId, pev_renderamt, gSavedRenderAmount[playerId]);
    set_pev(playerId, pev_rendercolor, gSavedRenderColor[playerId]);
}
