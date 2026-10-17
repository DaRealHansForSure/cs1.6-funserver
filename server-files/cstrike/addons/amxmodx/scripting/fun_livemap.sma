// Fun Live Map - streams player positions to the Server Control app.
//
// Every fun_livemap_interval seconds one UDP snapshot with the round state
// and all players goes to fun_livemap_target:fun_livemap_port, and every
// kill is sent at once as its own packet. The app draws them on a 3D map.
// The feed is meant for the server PC only, so the default target is
// 127.0.0.1 and the installer opens no firewall port for it.
//
// Packet format (text, lines separated by a newline):
//   CSLIVE1|S|<map>|<mode>|<roundSecondsLeft>|<maxPlayers>
//   P|<userid>|<name>|<team>|<alive>|<bot>|<hp>|<x>|<y>|<z>|<yaw>|<frags>|<deaths>|<weapon>|<hooking>|<hx>|<hy>|<hz>|<glowR>|<glowG>|<glowB>
//   CSLIVE1|K|<killerUserid>|<victimUserid>|<weapon>|<headshot>
//   CSLIVE1|T, then one line per bullet: <shooterUserid>|<sx>|<sy>|<sz>|<ex>|<ey>|<ez>|<hitPlayer>
//
// The glow color is the glow shell a player has right now (amx_glow, kill
// streaks, Juggernaut, zombies all use it), -1|-1|-1 without one. The app
// also reads player lines that end after <hz>, from older versions.
//
// Shot traces are the real bullet paths: while a gun fires, the engine's
// TraceLine calls of that shot are recorded (spread, shotgun pellets and
// wall penetration included). They are collected and sent once per
// snapshot, so a full auto spray does not mean one packet per bullet.
//
// Cvars:
//   fun_livemap_target    IP address of the app (default 127.0.0.1)
//   fun_livemap_port      UDP port of the app (default 27090)
//   fun_livemap_interval  seconds between snapshots (default 0.2)

#include <amxmodx>
#include <fakemeta>
#include <hamsandwich>
#include <sockets>
#include <fun_common>

#pragma semicolon 1

// fun_hook is optional: without it the natives below stay unresolved and
// the module and native filters keep this plugin running anyway.
#pragma reqlib fun_hook
native bool:fun_hook_get_point(playerId, Float:point[3]);

#define PLUGIN_NAME "Fun Live Map"
#define PLUGIN_VERSION "1.0"
#define PLUGIN_AUTHOR "LAN"

#define TASK_SNAPSHOT 9500

#define HOOK_LIBRARY "fun_hook"
#define PACKET_PREFIX "CSLIVE1"
#define WEAPON_PREFIX "weapon_"
#define TEAM_NAME_LENGTH 8
#define WEAPON_NAME_LENGTH 32
#define HOST_LENGTH 64

const Float:MIN_INTERVAL_SECONDS = 0.05;
const SOCKET_CLOSED = -1;
const ROUND_TIME_UNKNOWN = -1;

const TEAM_TERRORIST = 1;
const TEAM_CT = 2;

const MAX_SHOTS_PER_PACKET = 80;

// 32 players at about 110 bytes per line fit with plenty of room. Global,
// because a plugin only gets 16 KB of stack and heap.
new gPacket[4096];
new gKillPacket[256];
// About 45 characters per bullet; bullets beyond MAX_SHOTS_PER_PACKET are dropped.
new gShotPacket[4096];
new gShotPacketLength;
new gShotCount;

// Set only while a gun fires, so the TraceLine forward is not active for
// the thousands of traces bots do every second to look around.
new gShooterId;
new gTraceForward = -1;

new gSocket = SOCKET_CLOSED;
new gTargetCvar;
new gPortCvar;
new gIntervalCvar;
new gRoundTimeCvar;
new gRoundInfiniteCvar;

new bool:gHasRoundStarted;
new Float:gRoundStartedAt;
new bool:gIsHookLibraryLoaded;

public plugin_natives()
{
    set_module_filter("filterMissingLibrary");
    set_native_filter("filterMissingNative");
}

public filterMissingLibrary(const library[], LibType:type)
{
    if (equal(library, HOOK_LIBRARY)) {
        return PLUGIN_HANDLED;
    }
    return PLUGIN_CONTINUE;
}

public filterMissingNative(const nativeName[], nativeIndex, isTrap)
{
    // A missing native only matters when it is really called, and every
    // call is guarded by gIsHookLibraryLoaded.
    if (!isTrap) {
        return PLUGIN_HANDLED;
    }
    return PLUGIN_CONTINUE;
}

public plugin_init()
{
    register_plugin(PLUGIN_NAME, PLUGIN_VERSION, PLUGIN_AUTHOR);

    gTargetCvar = create_cvar("fun_livemap_target", "127.0.0.1", _, "IP address the live map packets go to");
    gPortCvar = create_cvar("fun_livemap_port", "27090", _, "UDP port the live map packets go to", true, 1.0, true, 65535.0);
    gIntervalCvar = create_cvar("fun_livemap_interval", "0.2", _, "Seconds between two live map snapshots", true, MIN_INTERVAL_SECONDS, true, 10.0);

    hook_cvar_change(gTargetCvar, "onTargetChanged");
    hook_cvar_change(gPortCvar, "onTargetChanged");
    hook_cvar_change(gIntervalCvar, "onIntervalChanged");

    register_event("DeathMsg", "onDeathMessage", "a");
    register_logevent("onRoundStart", 2, "1=Round_Start");

    // Knife and grenades are left out on purpose: they fire no bullets.
    new const gunClassNames[][] = {
        "weapon_p228", "weapon_scout", "weapon_xm1014", "weapon_mac10", "weapon_aug", "weapon_elite",
        "weapon_fiveseven", "weapon_ump45", "weapon_sg550", "weapon_galil", "weapon_famas", "weapon_usp",
        "weapon_glock18", "weapon_awp", "weapon_mp5navy", "weapon_m249", "weapon_m3", "weapon_m4a1",
        "weapon_tmp", "weapon_g3sg1", "weapon_deagle", "weapon_sg552", "weapon_ak47", "weapon_p90"
    };
    for (new index = 0; index < sizeof(gunClassNames); index++) {
        RegisterHam(Ham_Weapon_PrimaryAttack, gunClassNames[index], "onGunFirePre", 0);
        RegisterHam(Ham_Weapon_PrimaryAttack, gunClassNames[index], "onGunFirePost", 1);
    }
    resetShotPacket();
}

public plugin_cfg()
{
    // Both cvars come from ReGameDLL; a pointer of 0 simply means unknown.
    gRoundTimeCvar = get_cvar_pointer("mp_roundtime");
    gRoundInfiniteCvar = get_cvar_pointer("mp_round_infinite");
    gIsHookLibraryLoaded = bool:LibraryExists(HOOK_LIBRARY, LibType_Library);

    openSocket();
    startSnapshotTask();
}

public plugin_end()
{
    closeSocket();
}

public onTargetChanged(pointer, const oldValue[], const newValue[])
{
    openSocket();
}

public onIntervalChanged(pointer, const oldValue[], const newValue[])
{
    startSnapshotTask();
}

openSocket()
{
    closeSocket();

    new host[HOST_LENGTH];
    get_pcvar_string(gTargetCvar, host, charsmax(host));
    new port = get_pcvar_num(gPortCvar);

    new errorCode = 0;
    new socket = socket_open(host, port, SOCKET_UDP, errorCode);
    if (errorCode != SOCK_ERROR_OK || socket < 0) {
        log_amx("Live map: could not open UDP socket to %s:%d (error %d)", host, port, errorCode);
        return;
    }

    gSocket = socket;
    log_amx("Live map: sending to %s:%d", host, port);
}

closeSocket()
{
    if (gSocket == SOCKET_CLOSED) {
        return;
    }

    socket_close(gSocket);
    gSocket = SOCKET_CLOSED;
}

startSnapshotTask()
{
    remove_task(TASK_SNAPSHOT);

    new Float:interval = get_pcvar_float(gIntervalCvar);
    if (interval < MIN_INTERVAL_SECONDS) {
        interval = MIN_INTERVAL_SECONDS;
    }
    set_task(interval, "sendSnapshot", TASK_SNAPSHOT, _, _, "b");
}

public onRoundStart()
{
    gHasRoundStarted = true;
    gRoundStartedAt = get_gametime();
}

public onDeathMessage()
{
    if (gSocket == SOCKET_CLOSED) {
        return;
    }

    new killerId = read_data(1);
    new victimId = read_data(2);
    new isHeadshot = read_data(3);

    // DeathMsg already carries the short name ("ak47", "knife").
    new weaponName[WEAPON_NAME_LENGTH];
    read_data(4, weaponName, charsmax(weaponName));

    new killerUserId = 0;
    if (killerId >= 1 && killerId <= MaxClients && is_user_connected(killerId)) {
        killerUserId = get_user_userid(killerId);
    }

    new victimUserId = 0;
    if (victimId >= 1 && victimId <= MaxClients && is_user_connected(victimId)) {
        victimUserId = get_user_userid(victimId);
    }

    new length = formatex(gKillPacket, charsmax(gKillPacket), "%s|K|%d|%d|%s|%d",
        PACKET_PREFIX, killerUserId, victimUserId, weaponName, isHeadshot ? 1 : 0);
    socket_send2(gSocket, gKillPacket, length);
}

public onGunFirePre(weaponId)
{
    if (gSocket == SOCKET_CLOSED) {
        return HAM_IGNORED;
    }

    new ownerId = pev(weaponId, pev_owner);
    if (ownerId < 1 || ownerId > MaxClients || !is_user_alive(ownerId)) {
        return HAM_IGNORED;
    }

    gShooterId = ownerId;
    if (gTraceForward == -1) {
        gTraceForward = register_forward(FM_TraceLine, "onTraceLine", 1);
    }
    return HAM_IGNORED;
}

public onGunFirePost(weaponId)
{
    stopRecordingShot();
    return HAM_IGNORED;
}

stopRecordingShot()
{
    gShooterId = 0;
    if (gTraceForward != -1) {
        unregister_forward(FM_TraceLine, gTraceForward, 1);
        gTraceForward = -1;
    }
}

public onTraceLine(const Float:start[3], const Float:end[3], noMonsters, skipEntity, traceHandle)
{
    // Only the shooter's own traces: a plugin reacting to the shot inside
    // the same call could trace for something else.
    if (gShooterId == 0 || skipEntity != gShooterId) {
        return FMRES_IGNORED;
    }
    if (gShotCount >= MAX_SHOTS_PER_PACKET) {
        return FMRES_IGNORED;
    }

    new Float:hitPoint[3];
    get_tr2(traceHandle, TR_vecEndPos, hitPoint);
    new hitEntity = get_tr2(traceHandle, TR_pHit);
    new isPlayerHit = hitEntity >= 1 && hitEntity <= MaxClients;

    gShotPacketLength += formatex(gShotPacket[gShotPacketLength], charsmax(gShotPacket) - gShotPacketLength,
        "^n%d|%d|%d|%d|%d|%d|%d|%d",
        get_user_userid(gShooterId),
        floatround(start[0]), floatround(start[1]), floatround(start[2]),
        floatround(hitPoint[0]), floatround(hitPoint[1]), floatround(hitPoint[2]),
        isPlayerHit ? 1 : 0);
    gShotCount++;
    return FMRES_IGNORED;
}

resetShotPacket()
{
    gShotPacketLength = formatex(gShotPacket, charsmax(gShotPacket), "%s|T", PACKET_PREFIX);
    gShotCount = 0;
}

sendShots()
{
    if (gShotCount == 0) {
        return;
    }
    socket_send2(gSocket, gShotPacket, gShotPacketLength);
    resetShotPacket();
}

public sendSnapshot()
{
    if (gSocket == SOCKET_CLOSED) {
        return;
    }

    // A shot whose post hook never came (another plugin blocked it) must not
    // leave the trace forward running.
    if (gTraceForward != -1) {
        stopRecordingShot();
    }
    sendShots();

    new mapName[MAX_MAPNAME_LENGTH];
    get_mapname(mapName, charsmax(mapName));

    new mode[FUN_MODE_LENGTH];
    get_fun_mode(mode, charsmax(mode));

    new length = formatex(gPacket, charsmax(gPacket), "%s|S|%s|%s|%d|%d",
        PACKET_PREFIX, mapName, mode, getRoundSecondsLeft(), MaxClients);

    for (new playerId = 1; playerId <= MaxClients; playerId++) {
        if (!is_user_connected(playerId) || is_user_hltv(playerId)) {
            continue;
        }

        length += appendPlayerLine(playerId, length);
        if (length >= charsmax(gPacket)) {
            break;
        }
    }

    socket_send2(gSocket, gPacket, length);
}

/**
 * Writes the "P|..." line of one player into gPacket at the given offset
 * and returns the number of characters written.
 */
appendPlayerLine(playerId, offset)
{
    new name[MAX_NAME_LENGTH];
    get_user_name(playerId, name, charsmax(name));
    // The separators must never show up inside a field.
    replace_string(name, charsmax(name), "|", "/");
    replace_string(name, charsmax(name), "^n", "/");
    replace_string(name, charsmax(name), "^r", "/");

    new teamName[TEAM_NAME_LENGTH];
    getTeamName(playerId, teamName, charsmax(teamName));

    new isAlive = is_user_alive(playerId);

    // Dead players keep sending their last origin, so the app can mark the
    // spot where they fell.
    new Float:origin[3];
    pev(playerId, pev_origin, origin);

    new Float:viewAngles[3];
    pev(playerId, pev_v_angle, viewAngles);

    new health = 0;
    if (isAlive) {
        health = get_user_health(playerId);
    }

    new weaponName[WEAPON_NAME_LENGTH];
    if (isAlive) {
        getShortWeaponName(playerId, weaponName, charsmax(weaponName));
    }

    new Float:hookPoint[3];
    new isHooking = 0;
    if (gIsHookLibraryLoaded && isAlive && fun_hook_get_point(playerId, hookPoint)) {
        isHooking = 1;
    }

    new glowRed = -1;
    new glowGreen = -1;
    new glowBlue = -1;
    if (isAlive && pev(playerId, pev_renderfx) == kRenderFxGlowShell) {
        new Float:glowColor[3];
        pev(playerId, pev_rendercolor, glowColor);
        glowRed = floatround(glowColor[0]);
        glowGreen = floatround(glowColor[1]);
        glowBlue = floatround(glowColor[2]);
    }

    return formatex(gPacket[offset], charsmax(gPacket) - offset,
        "^nP|%d|%s|%s|%d|%d|%d|%d|%d|%d|%d|%d|%d|%s|%d|%d|%d|%d|%d|%d|%d",
        get_user_userid(playerId),
        name,
        teamName,
        isAlive ? 1 : 0,
        is_user_bot(playerId) ? 1 : 0,
        health,
        floatround(origin[0]),
        floatround(origin[1]),
        floatround(origin[2]),
        floatround(viewAngles[1]),
        get_user_frags(playerId),
        get_user_deaths(playerId),
        weaponName,
        isHooking,
        floatround(hookPoint[0]),
        floatround(hookPoint[1]),
        floatround(hookPoint[2]),
        glowRed,
        glowGreen,
        glowBlue);
}

getTeamName(playerId, teamName[], length)
{
    // Unassigned players are still choosing a team, the app shows them as
    // spectators.
    new team = get_user_team(playerId);
    if (team == TEAM_TERRORIST) {
        copy(teamName, length, "T");
        return;
    }
    if (team == TEAM_CT) {
        copy(teamName, length, "CT");
        return;
    }
    copy(teamName, length, "SPEC");
}

getShortWeaponName(playerId, weaponName[], length)
{
    new weaponId = get_user_weapon(playerId);
    if (weaponId <= 0) {
        return;
    }

    new fullName[WEAPON_NAME_LENGTH];
    get_weaponname(weaponId, fullName, charsmax(fullName));

    new prefixLength = strlen(WEAPON_PREFIX);
    if (equal(fullName, WEAPON_PREFIX, prefixLength)) {
        copy(weaponName, length, fullName[prefixLength]);
        return;
    }
    copy(weaponName, length, fullName);
}

/**
 * Seconds left in the current round, or -1 when rounds never end
 * (mp_round_infinite) or no round has started on this map yet.
 */
getRoundSecondsLeft()
{
    if (!gHasRoundStarted || isRoundInfinite() || !gRoundTimeCvar) {
        return ROUND_TIME_UNKNOWN;
    }

    new Float:roundSeconds = get_pcvar_float(gRoundTimeCvar) * 60.0;
    new Float:elapsedSeconds = get_gametime() - gRoundStartedAt;
    new secondsLeft = floatround(roundSeconds - elapsedSeconds, floatround_ceil);
    if (secondsLeft < 0) {
        return 0;
    }
    return secondsLeft;
}

bool:isRoundInfinite()
{
    if (!gRoundInfiniteCvar) {
        return false;
    }

    // ReGameDLL takes "1" or a set of flag letters like "abc", so anything
    // but empty or "0" means at least some rounds never time out.
    new value[32];
    get_pcvar_string(gRoundInfiniteCvar, value, charsmax(value));
    if (value[0] == EOS || equal(value, "0")) {
        return false;
    }
    return true;
}
