// Fun Admin Commands - the classic admin toys from the old fun servers.
//
//   amx_glow <target> <red|green|blue|yellow|pink|white|off>
//   amx_godmode <target> <0|1>
//   amx_noclip <target> <0|1>
//   amx_rocket <target>        shoots the player into the sky, then boom
//   amx_speed <target> <factor>  e.g. 2.0 = double speed until next spawn
//
// <target> is a name (or part of it), #userid, @T, @CT or @ALL.
// All commands need the admin flag "e" (slay).

#include <amxmodx>
#include <amxmisc>
#include <fakemeta>
#include <fun>
#include <hamsandwich>

#pragma semicolon 1

#define PLUGIN_NAME "Fun Admin Commands"
#define PLUGIN_VERSION "1.0"
#define PLUGIN_AUTHOR "LAN"

#define TASK_ROCKET_EXPLODE 8100

const FUN_ADMIN_FLAG = ADMIN_SLAY;
const Float:ROCKET_LAUNCH_SPEED = 1100.0;
const Float:ROCKET_FLIGHT_SECONDS = 1.6;
const GLOW_THICKNESS = 25;

// Beam and explosion sizes use the engine's own units.
const TRAIL_LIFE_TENTHS = 10;
const TRAIL_WIDTH = 10;
const EXPLOSION_SCALE = 30;
const EXPLOSION_FRAMERATE = 12;

new const ROCKET_LAUNCH_SOUND[] = "weapons/rocketfire1.wav";
new const TRAIL_SPRITE[] = "sprites/smoke.spr";
new const EXPLOSION_SPRITE[] = "sprites/zerogxplode.spr";

new const GLOW_COLOR_NAMES[][] = {
    "red",
    "green",
    "blue",
    "yellow",
    "pink",
    "white"
};

new const GLOW_COLOR_VALUES[][3] = {
    {255, 0, 0},
    {0, 255, 0},
    {0, 80, 255},
    {255, 255, 0},
    {255, 0, 200},
    {255, 255, 255}
};

new gTrailSprite;
new gExplosionSprite;
new Float:gSpeedFactor[MAX_PLAYERS + 1];

public plugin_precache()
{
    precache_sound(ROCKET_LAUNCH_SOUND);
    gTrailSprite = precache_model(TRAIL_SPRITE);
    gExplosionSprite = precache_model(EXPLOSION_SPRITE);
}

public plugin_init()
{
    register_plugin(PLUGIN_NAME, PLUGIN_VERSION, PLUGIN_AUTHOR);

    register_concmd("amx_glow", "cmdGlow", FUN_ADMIN_FLAG, "<target> <red|green|blue|yellow|pink|white|off>");
    register_concmd("amx_godmode", "cmdGodmode", FUN_ADMIN_FLAG, "<target> <0|1>");
    register_concmd("amx_noclip", "cmdNoclip", FUN_ADMIN_FLAG, "<target> <0|1>");
    register_concmd("amx_rocket", "cmdRocket", FUN_ADMIN_FLAG, "<target>");
    register_concmd("amx_speed", "cmdSpeed", FUN_ADMIN_FLAG, "<target> <factor>");

    RegisterHam(Ham_Spawn, "player", "onPlayerSpawned", 1);
    RegisterHam(Ham_CS_Player_ResetMaxSpeed, "player", "onResetMaxSpeed", 1);
}

public client_putinserver(playerId)
{
    gSpeedFactor[playerId] = 1.0;
}

public client_disconnected(playerId)
{
    remove_task(TASK_ROCKET_EXPLODE + playerId);
}

public onPlayerSpawned(playerId)
{
    // Speed changes are a joke for one life, not a permanent buff.
    gSpeedFactor[playerId] = 1.0;
}

public onResetMaxSpeed(playerId)
{
    if (is_user_alive(playerId) && gSpeedFactor[playerId] != 1.0 && get_user_maxspeed(playerId) > 1.0) {
        set_user_maxspeed(playerId, get_user_maxspeed(playerId) * gSpeedFactor[playerId]);
    }
}

public cmdGlow(adminId, level, commandId)
{
    if (!cmd_access(adminId, level, commandId, 3)) {
        return PLUGIN_HANDLED;
    }

    new colorName[16];
    read_argv(2, colorName, charsmax(colorName));
    strtolower(colorName);

    new colorIndex = findGlowColor(colorName);
    new isTurningOff = equal(colorName, "off");

    if (colorIndex == -1 && !isTurningOff) {
        console_print(adminId, "Colors: red, green, blue, yellow, pink, white or off");
        return PLUGIN_HANDLED;
    }

    new targets[MAX_PLAYERS], targetCount;
    if (!collectTargets(adminId, targets, targetCount)) {
        return PLUGIN_HANDLED;
    }

    for (new i = 0; i < targetCount; i++) {
        if (isTurningOff) {
            set_user_rendering(targets[i]);
        } else {
            set_user_rendering(targets[i], kRenderFxGlowShell, GLOW_COLOR_VALUES[colorIndex][0], GLOW_COLOR_VALUES[colorIndex][1], GLOW_COLOR_VALUES[colorIndex][2], kRenderNormal, GLOW_THICKNESS);
        }
    }

    announceAction(adminId, targets, targetCount, "makes glow:");
    return PLUGIN_HANDLED;
}

public cmdGodmode(adminId, level, commandId)
{
    if (!cmd_access(adminId, level, commandId, 3)) {
        return PLUGIN_HANDLED;
    }

    new isOn = read_argv_int(2);

    new targets[MAX_PLAYERS], targetCount;
    if (!collectTargets(adminId, targets, targetCount)) {
        return PLUGIN_HANDLED;
    }

    for (new i = 0; i < targetCount; i++) {
        set_user_godmode(targets[i], isOn);
    }

    if (isOn) {
        announceAction(adminId, targets, targetCount, "makes immortal:");
    } else {
        announceAction(adminId, targets, targetCount, "makes mortal again:");
    }
    return PLUGIN_HANDLED;
}

public cmdNoclip(adminId, level, commandId)
{
    if (!cmd_access(adminId, level, commandId, 3)) {
        return PLUGIN_HANDLED;
    }

    new isOn = read_argv_int(2);

    new targets[MAX_PLAYERS], targetCount;
    if (!collectTargets(adminId, targets, targetCount)) {
        return PLUGIN_HANDLED;
    }

    for (new i = 0; i < targetCount; i++) {
        set_user_noclip(targets[i], isOn);
    }

    if (isOn) {
        announceAction(adminId, targets, targetCount, "lets fly through walls:");
    } else {
        announceAction(adminId, targets, targetCount, "brings back to the ground:");
    }
    return PLUGIN_HANDLED;
}

public cmdSpeed(adminId, level, commandId)
{
    if (!cmd_access(adminId, level, commandId, 3)) {
        return PLUGIN_HANDLED;
    }

    new Float:speedFactor = floatclamp(read_argv_float(2), 0.2, 5.0);

    new targets[MAX_PLAYERS], targetCount;
    if (!collectTargets(adminId, targets, targetCount)) {
        return PLUGIN_HANDLED;
    }

    for (new i = 0; i < targetCount; i++) {
        gSpeedFactor[targets[i]] = speedFactor;
        ExecuteHamB(Ham_CS_Player_ResetMaxSpeed, targets[i]);
    }

    announceAction(adminId, targets, targetCount, "changes the speed of");
    return PLUGIN_HANDLED;
}

public cmdRocket(adminId, level, commandId)
{
    if (!cmd_access(adminId, level, commandId, 2)) {
        return PLUGIN_HANDLED;
    }

    new targets[MAX_PLAYERS], targetCount;
    if (!collectTargets(adminId, targets, targetCount)) {
        return PLUGIN_HANDLED;
    }

    for (new i = 0; i < targetCount; i++) {
        launchRocket(targets[i]);
    }

    announceAction(adminId, targets, targetCount, "launches as a rocket:");
    return PLUGIN_HANDLED;
}

launchRocket(playerId)
{
    new Float:velocity[3];
    velocity[2] = ROCKET_LAUNCH_SPEED;
    set_pev(playerId, pev_velocity, velocity);

    emit_sound(playerId, CHAN_WEAPON, ROCKET_LAUNCH_SOUND, VOL_NORM, ATTN_NORM, 0, PITCH_NORM);
    drawSmokeTrail(playerId);

    set_task(ROCKET_FLIGHT_SECONDS, "explodeRocket", TASK_ROCKET_EXPLODE + playerId);
}

public explodeRocket(taskId)
{
    new playerId = taskId - TASK_ROCKET_EXPLODE;
    if (!is_user_alive(playerId)) {
        return;
    }

    new Float:origin[3];
    pev(playerId, pev_origin, origin);

    message_begin(MSG_BROADCAST, SVC_TEMPENTITY);
    write_byte(TE_EXPLOSION);
    engfunc(EngFunc_WriteCoord, origin[0]);
    engfunc(EngFunc_WriteCoord, origin[1]);
    engfunc(EngFunc_WriteCoord, origin[2]);
    write_short(gExplosionSprite);
    write_byte(EXPLOSION_SCALE);
    write_byte(EXPLOSION_FRAMERATE);
    write_byte(TE_EXPLFLAG_NONE);
    message_end();

    user_kill(playerId, 1);
}

drawSmokeTrail(playerId)
{
    message_begin(MSG_BROADCAST, SVC_TEMPENTITY);
    write_byte(TE_BEAMFOLLOW);
    write_short(playerId);
    write_short(gTrailSprite);
    write_byte(TRAIL_LIFE_TENTHS);
    write_byte(TRAIL_WIDTH);
    write_byte(255);
    write_byte(160);
    write_byte(40);
    write_byte(200);
    message_end();
}

/**
 * Resolves the first argument (name, #userid, @T, @CT, @ALL) into alive
 * players. Prints a hint to the admin and returns false when nobody matches.
 */
bool:collectTargets(adminId, targets[MAX_PLAYERS], &targetCount)
{
    targetCount = 0;

    new targetArgument[MAX_NAME_LENGTH];
    read_argv(1, targetArgument, charsmax(targetArgument));

    if (targetArgument[0] == '@') {
        collectTeamTargets(targetArgument, targets, targetCount);
    } else {
        new targetId = cmd_target(adminId, targetArgument, CMDTARGET_ALLOW_SELF | CMDTARGET_ONLY_ALIVE);
        if (targetId) {
            targets[0] = targetId;
            targetCount = 1;
        }
    }

    if (targetCount == 0) {
        console_print(adminId, "No matching living player found.");
        return false;
    }
    return true;
}

collectTeamTargets(const teamArgument[], targets[MAX_PLAYERS], &targetCount)
{
    if (equali(teamArgument, "@T")) {
        get_players(targets, targetCount, "ae", "TERRORIST");
    } else if (equali(teamArgument, "@CT")) {
        get_players(targets, targetCount, "ae", "CT");
    } else if (equali(teamArgument, "@ALL")) {
        get_players(targets, targetCount, "a");
    } else {
        targetCount = 0;
    }
}

announceAction(adminId, const targets[MAX_PLAYERS], targetCount, const actionText[])
{
    new adminName[MAX_NAME_LENGTH];
    get_user_name(adminId, adminName, charsmax(adminName));

    if (targetCount > 1) {
        client_print(0, print_chat, "[Fun] Admin %s %s %d players.", adminName, actionText, targetCount);
        return;
    }

    new targetName[MAX_NAME_LENGTH];
    get_user_name(targets[0], targetName, charsmax(targetName));
    client_print(0, print_chat, "[Fun] Admin %s %s %s.", adminName, actionText, targetName);
}

findGlowColor(const colorName[])
{
    for (new i = 0; i < sizeof(GLOW_COLOR_NAMES); i++) {
        if (equal(GLOW_COLOR_NAMES[i], colorName)) {
            return i;
        }
    }
    return -1;
}
