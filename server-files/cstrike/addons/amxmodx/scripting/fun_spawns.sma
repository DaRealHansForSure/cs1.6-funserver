// Fun Spawns - random spawns all over the map in GunGame and Deathmatch.
//
// ReGameDLL's mp_randomspawn needs a .nav file per map, which most fun maps
// do not have. So the plugin learns spawn points instead: every few seconds
// it remembers where players and bots stand on solid ground. Those spots are
// reachable by definition, and after a few minutes of bots running around
// they cover the whole map. The points are kept per map in
// addons/amxmodx/data/fun_spawns/<map>.txt and grow with every match.
//
// On spawn a player is moved to a random learned spot with nobody close by
// and room for a player. Until enough spots are known, the spawn points of
// both teams are used, so an FFA map does not start with two team camps.

#include <amxmodx>
#include <amxmisc>
#include <fakemeta>
#include <hamsandwich>
#include <fun_common>

#pragma semicolon 1

#define PLUGIN_NAME "Fun Spawns"
#define PLUGIN_VERSION "1.0"
#define PLUGIN_AUTHOR "LAN"

#define TASK_LEARN 9700
#define TASK_SAVE 9800
#define TASK_ZBOT_HOOKS 9900

const MAX_SPAWN_POINTS = 512;
const MIN_LEARNED_POINTS = 24;
const Float:LEARN_INTERVAL_SECONDS = 2.0;
const Float:SAVE_INTERVAL_SECONDS = 60.0;

// Points closer than this are the same spot, so the list spreads over the map.
const Float:MIN_POINT_DISTANCE = 160.0;

// Nobody may stand this close to a fresh spawn (about 7 m), no spawn kills.
const Float:SAFE_SPAWN_DISTANCE = 280.0;
const SPAWN_ATTEMPTS = 30;

// The engine's player hull, used to make sure a spot is free.
const HULL_HUMAN_INDEX = 1;
const WORLD_ENTITY = 0;

new Float:gPoints[MAX_SPAWN_POINTS][3];
new gPointCount;
new gLearnedCount;
new bool:gIsActive;
new bool:gHasUnsavedPoints;
new bool:gAreZbotHooksRegistered;
new gPointsFile[128];

public plugin_init() {
    register_plugin(PLUGIN_NAME, PLUGIN_VERSION, PLUGIN_AUTHOR);

    gIsActive = is_fun_mode(FUN_MODE_GUNGAME) || is_fun_mode(FUN_MODE_DEATHMATCH);
    if (!gIsActive) {
        return;
    }

    RegisterHam(Ham_Spawn, "player", "onPlayerSpawned", 1);
}

public client_putinserver(playerId) {
    if (!gIsActive || gAreZbotHooksRegistered || !is_zbot(playerId)) {
        return;
    }
    set_task(FUN_ZBOT_HOOK_DELAY, "registerZbotHooks", TASK_ZBOT_HOOKS + playerId);
}

public client_disconnected(playerId) {
    remove_task(TASK_ZBOT_HOOKS + playerId);
}

/**
 * zBot bots have their own vtable (see fun_common.inc), so the spawn hook
 * is registered once more on the first bot. All bots share that vtable,
 * a second registration would move every bot twice.
 */
public registerZbotHooks(taskId) {
    new botId = taskId - TASK_ZBOT_HOOKS;
    if (gAreZbotHooksRegistered || !is_user_connected(botId)) {
        return;
    }
    gAreZbotHooksRegistered = true;

    RegisterHamFromEntity(Ham_Spawn, botId, "onPlayerSpawned", 1);
}

public plugin_cfg() {
    if (!gIsActive) {
        return;
    }

    new dataDir[96];
    get_datadir(dataDir, charsmax(dataDir));
    new folder[112];
    formatex(folder, charsmax(folder), "%s/fun_spawns", dataDir);
    if (!dir_exists(folder)) {
        mkdir(folder);
    }

    new mapName[MAX_MAPNAME_LENGTH];
    get_mapname(mapName, charsmax(mapName));
    strtolower(mapName);
    formatex(gPointsFile, charsmax(gPointsFile), "%s/%s.txt", folder, mapName);

    loadLearnedPoints();
    gLearnedCount = gPointCount;
    addTeamSpawnPoints();
    log_amx("Random spawns on %s: %d learned points, %d with team spawns", mapName, gLearnedCount, gPointCount);

    set_task(LEARN_INTERVAL_SECONDS, "learnPoints", TASK_LEARN, _, _, "b");
    set_task(SAVE_INTERVAL_SECONDS, "saveLearnedPoints", TASK_SAVE, _, _, "b");
}

public plugin_end() {
    if (gIsActive) {
        saveLearnedPoints();
    }
}

public onPlayerSpawned(playerId) {
    if (!is_user_alive(playerId) || gPointCount == 0) {
        return;
    }

    new Float:spot[3];
    if (!findFreeSpot(playerId, spot)) {
        // No free spot right now, the normal spawn is better than none.
        return;
    }

    engfunc(EngFunc_SetOrigin, playerId, spot);
    set_pev(playerId, pev_velocity, Float:{0.0, 0.0, 0.0});

    new Float:angles[3];
    angles[1] = random_float(-180.0, 180.0);
    set_pev(playerId, pev_angles, angles);
    set_pev(playerId, pev_v_angle, angles);
    set_pev(playerId, pev_fixangle, 1);
}

/**
 * Picks random points until one has nobody close by and room for a player.
 * Learned points are preferred once there are enough of them, the team
 * spawns at the end of the list then only fill gaps.
 */
bool:findFreeSpot(playerId, Float:spot[3]) {
    new usableCount = gLearnedCount >= MIN_LEARNED_POINTS ? gLearnedCount : gPointCount;

    for (new attempt = 0; attempt < SPAWN_ATTEMPTS; attempt++) {
        new index = random(usableCount);
        if (isNearOtherPlayer(playerId, gPoints[index]) || !isRoomForPlayer(playerId, gPoints[index])) {
            continue;
        }

        spot[0] = gPoints[index][0];
        spot[1] = gPoints[index][1];
        spot[2] = gPoints[index][2];
        return true;
    }
    return false;
}

bool:isNearOtherPlayer(playerId, const Float:point[3]) {
    new players[MAX_PLAYERS], playerCount;
    get_players(players, playerCount, "a");

    new Float:origin[3];
    for (new i = 0; i < playerCount; i++) {
        if (players[i] == playerId) {
            continue;
        }
        pev(players[i], pev_origin, origin);
        if (get_distance_f(origin, point) < SAFE_SPAWN_DISTANCE) {
            return true;
        }
    }
    return false;
}

bool:isRoomForPlayer(playerId, const Float:point[3]) {
    new trace = create_tr2();
    engfunc(EngFunc_TraceHull, point, point, DONT_IGNORE_MONSTERS, HULL_HUMAN_INDEX, playerId, trace);
    new bool:isFree = !get_tr2(trace, TR_StartSolid) && !get_tr2(trace, TR_AllSolid);
    free_tr2(trace);
    return isFree;
}

/**
 * Remembers where alive players stand, but only safe spots: on the world
 * itself (not on boxes, lifts or other players), standing, not in water,
 * not on a ladder and not flying through walls with noclip.
 */
public learnPoints() {
    if (gPointCount >= MAX_SPAWN_POINTS) {
        return;
    }

    new players[MAX_PLAYERS], playerCount;
    get_players(players, playerCount, "a");

    new Float:origin[3];
    for (new i = 0; i < playerCount && gPointCount < MAX_SPAWN_POINTS; i++) {
        new playerId = players[i];
        if (!isSafeStandingSpot(playerId)) {
            continue;
        }

        pev(playerId, pev_origin, origin);
        if (isKnownPoint(origin)) {
            continue;
        }

        addPointAt(gLearnedCount, origin);
        gLearnedCount++;
        gHasUnsavedPoints = true;
    }
}

bool:isSafeStandingSpot(playerId) {
    new flags = pev(playerId, pev_flags);
    if (!(flags & FL_ONGROUND) || (flags & FL_DUCKING)) {
        return false;
    }
    if (pev(playerId, pev_groundentity) != WORLD_ENTITY) {
        return false;
    }
    if (pev(playerId, pev_waterlevel) > 0 || pev(playerId, pev_movetype) != MOVETYPE_WALK) {
        return false;
    }
    return true;
}

bool:isKnownPoint(const Float:origin[3]) {
    for (new i = 0; i < gPointCount; i++) {
        if (get_distance_f(gPoints[i], origin) < MIN_POINT_DISTANCE) {
            return true;
        }
    }
    return false;
}

/**
 * Inserts a learned point at the end of the learned block. The team spawns
 * that follow it move up by one, so the list stays learned first.
 */
addPointAt(index, const Float:origin[3]) {
    for (new i = gPointCount; i > index; i--) {
        gPoints[i][0] = gPoints[i - 1][0];
        gPoints[i][1] = gPoints[i - 1][1];
        gPoints[i][2] = gPoints[i - 1][2];
    }
    gPoints[index][0] = origin[0];
    gPoints[index][1] = origin[1];
    gPoints[index][2] = origin[2];
    gPointCount++;
}

addTeamSpawnPoints() {
    new const spawnClasses[][] = { "info_player_start", "info_player_deathmatch" };
    new Float:origin[3];

    for (new classIndex = 0; classIndex < sizeof(spawnClasses); classIndex++) {
        new entity = -1;
        while ((entity = engfunc(EngFunc_FindEntityByString, entity, "classname", spawnClasses[classIndex])) > 0) {
            if (gPointCount >= MAX_SPAWN_POINTS) {
                return;
            }
            pev(entity, pev_origin, origin);
            gPoints[gPointCount][0] = origin[0];
            gPoints[gPointCount][1] = origin[1];
            gPoints[gPointCount][2] = origin[2];
            gPointCount++;
        }
    }
}

loadLearnedPoints() {
    new file = fopen(gPointsFile, "rt");
    if (!file) {
        return;
    }

    new line[96], xText[24], yText[24], zText[24];
    while (!feof(file) && gPointCount < MAX_SPAWN_POINTS) {
        fgets(file, line, charsmax(line));
        trim(line);
        if (line[0] == EOS) {
            continue;
        }

        parse(line, xText, charsmax(xText), yText, charsmax(yText), zText, charsmax(zText));
        gPoints[gPointCount][0] = str_to_float(xText);
        gPoints[gPointCount][1] = str_to_float(yText);
        gPoints[gPointCount][2] = str_to_float(zText);
        gPointCount++;
    }
    fclose(file);
}

public saveLearnedPoints() {
    if (!gHasUnsavedPoints) {
        return;
    }

    new file = fopen(gPointsFile, "wt");
    if (!file) {
        log_amx("Could not write %s", gPointsFile);
        return;
    }
    for (new i = 0; i < gLearnedCount; i++) {
        fprintf(file, "%.1f %.1f %.1f^n", gPoints[i][0], gPoints[i][1], gPoints[i][2]);
    }
    fclose(file);
    gHasUnsavedPoints = false;
}
