// Fun Hook - the classic glowing grappling hook.
//
// Bind a key with: bind f "+hook"
// Hold the key to shoot a glowing laser rope at the wall you aim at and get
// pulled there. Release it to let go. Every hook gets a random bright color.
//
// Active in the "classic" and "deathmatch" modes. In GunGame and Zombie the
// hook would break the balance, so it stays off there.
//
// Cvars:
//   fun_hook_enabled     1 = on, 0 = off
//   fun_hook_speed       pull speed in units per second
//   fun_hook_admin_only  1 = only admins (flag "c") may hook
//
// Native for other plugins (library "fun_hook"):
//   bool:fun_hook_get_point(playerId, Float:point[3])

#include <amxmodx>
#include <amxmisc>
#include <fakemeta>
#include <xs>
#include <fun_common>

#pragma semicolon 1

#define PLUGIN_NAME "Fun Hook"
#define PLUGIN_VERSION "1.0"
#define PLUGIN_AUTHOR "LAN"

#define TASK_HOOK_PULL 7100

const Float:HOOK_TICK_SECONDS = 0.1;
const Float:HOOK_ARRIVAL_DISTANCE = 40.0;
const Float:MAX_HOOK_DISTANCE = 4000.0;
const HOOK_ADMIN_FLAG = ADMIN_KICK;

// Beam timings are given in tenths of a second.
const BEAM_LIFE_TENTHS = 2;
const BEAM_WIDTH = 12;
const BEAM_NOISE = 0;
const BEAM_BRIGHTNESS = 220;

new const BEAM_SPRITE[] = "sprites/laserbeam.spr";

new const HOOK_COLORS[][3] = {
    {255, 0, 0},
    {0, 255, 0},
    {0, 128, 255},
    {255, 255, 0},
    {255, 0, 255},
    {0, 255, 255},
    {255, 128, 0},
    {255, 255, 255}
};

new bool:gIsHooking[MAX_PLAYERS + 1];
new Float:gHookPoint[MAX_PLAYERS + 1][3];
new gHookColorIndex[MAX_PLAYERS + 1];
new gBeamSprite;
new gEnabledCvar;
new gSpeedCvar;
new gAdminOnlyCvar;

public plugin_natives() {
    // fun_livemap draws the hook rope on the live map, but must also run
    // without this plugin, so it finds the native through this library name.
    register_library("fun_hook");
    register_native("fun_hook_get_point", "nativeGetHookPoint");
}

public plugin_precache() {
    gBeamSprite = precache_model(BEAM_SPRITE);
}

public plugin_init() {
    register_plugin(PLUGIN_NAME, PLUGIN_VERSION, PLUGIN_AUTHOR);

    gEnabledCvar = create_cvar("fun_hook_enabled", "1", _, "Hook on (1) or off (0)", true, 0.0, true, 1.0);
    gSpeedCvar = create_cvar("fun_hook_speed", "750", _, "Pull speed of the hook", true, 100.0, true, 3000.0);
    gAdminOnlyCvar = create_cvar("fun_hook_admin_only", "0", _, "Only admins may use the hook", true, 0.0, true, 1.0);

    // The hook only fits the relaxed modes, so it switches itself off in the others.
    if (is_fun_mode(FUN_MODE_GUNGAME) || is_fun_mode(FUN_MODE_ZOMBIE) || is_fun_mode(FUN_MODE_DEATHRUN)) {
        set_pcvar_num(gEnabledCvar, 0);
    }

    register_clcmd("+hook", "cmdHookStart");
    register_clcmd("-hook", "cmdHookStop");
    register_event("DeathMsg", "onDeathMessage", "a");
}

public client_disconnected(playerId) {
    stopHook(playerId);
}

public onDeathMessage() {
    stopHook(read_data(2));
}

public cmdHookStart(playerId) {
    if (!canUseHook(playerId) || gIsHooking[playerId]) {
        return PLUGIN_HANDLED;
    }

    new aimOrigin[3];
    get_user_origin(playerId, aimOrigin, Origin_AimEndEyes);
    IVecFVec(aimOrigin, gHookPoint[playerId]);

    new Float:playerOrigin[3];
    pev(playerId, pev_origin, playerOrigin);
    if (get_distance_f(playerOrigin, gHookPoint[playerId]) > MAX_HOOK_DISTANCE) {
        client_print(playerId, print_center, "Too far away!");
        return PLUGIN_HANDLED;
    }

    gIsHooking[playerId] = true;
    gHookColorIndex[playerId] = random(sizeof(HOOK_COLORS));

    pullTowardsHookPoint(TASK_HOOK_PULL + playerId);
    set_task(HOOK_TICK_SECONDS, "pullTowardsHookPoint", TASK_HOOK_PULL + playerId, _, _, "b");

    return PLUGIN_HANDLED;
}

// native bool:fun_hook_get_point(playerId, Float:point[3])
public bool:nativeGetHookPoint(pluginId, paramCount) {
    new playerId = get_param(1);
    if (playerId < 1 || playerId > MaxClients) {
        return false;
    }

    if (!gIsHooking[playerId]) {
        return false;
    }

    set_array_f(2, gHookPoint[playerId], sizeof(gHookPoint[]));
    return true;
}

public cmdHookStop(playerId) {
    stopHook(playerId);
    return PLUGIN_HANDLED;
}

bool:canUseHook(playerId) {
    if (!get_pcvar_num(gEnabledCvar)) {
        client_print(playerId, print_center, "The hook is off in this mode.");
        return false;
    }

    if (!is_user_alive(playerId)) {
        return false;
    }

    new isAdminOnly = get_pcvar_num(gAdminOnlyCvar);
    if (isAdminOnly && !(get_user_flags(playerId) & HOOK_ADMIN_FLAG)) {
        client_print(playerId, print_center, "Only admins may use the hook.");
        return false;
    }

    return true;
}

stopHook(playerId) {
    if (playerId < 1 || playerId > MaxClients) {
        return;
    }

    gIsHooking[playerId] = false;
    remove_task(TASK_HOOK_PULL + playerId);
}

public pullTowardsHookPoint(taskId) {
    new playerId = taskId - TASK_HOOK_PULL;

    if (!is_user_alive(playerId)) {
        stopHook(playerId);
        return;
    }

    new Float:playerOrigin[3];
    pev(playerId, pev_origin, playerOrigin);

    new Float:towardsHook[3];
    xs_vec_sub(gHookPoint[playerId], playerOrigin, towardsHook);

    new Float:distance = xs_vec_len(towardsHook);
    new Float:velocity[3];

    // Once there, hang on the wall instead of jittering around the point.
    if (distance > HOOK_ARRIVAL_DISTANCE) {
        xs_vec_normalize(towardsHook, velocity);
        xs_vec_mul_scalar(velocity, get_pcvar_float(gSpeedCvar), velocity);
    }

    set_pev(playerId, pev_velocity, velocity);
    drawHookBeam(playerId);
}

drawHookBeam(playerId) {
    new colorIndex = gHookColorIndex[playerId];

    message_begin(MSG_BROADCAST, SVC_TEMPENTITY);
    write_byte(TE_BEAMENTPOINT);
    write_short(playerId);
    engfunc(EngFunc_WriteCoord, gHookPoint[playerId][0]);
    engfunc(EngFunc_WriteCoord, gHookPoint[playerId][1]);
    engfunc(EngFunc_WriteCoord, gHookPoint[playerId][2]);
    write_short(gBeamSprite);
    write_byte(0);
    write_byte(0);
    write_byte(BEAM_LIFE_TENTHS);
    write_byte(BEAM_WIDTH);
    write_byte(BEAM_NOISE);
    write_byte(HOOK_COLORS[colorIndex][0]);
    write_byte(HOOK_COLORS[colorIndex][1]);
    write_byte(HOOK_COLORS[colorIndex][2]);
    write_byte(BEAM_BRIGHTNESS);
    write_byte(0);
    message_end();
}
