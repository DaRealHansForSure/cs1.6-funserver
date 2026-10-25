// Fun Rounds - every few rounds in Classic a surprise rule for one round.
//
//   knives    knives only
//   awp       AWP only
//   lowgrav   low gravity
//   speed     everybody runs much faster
//   headshot  only headshots do damage
//   deagle    one bullet Deagle, every kill gives a new bullet, one shot kills
//   hewar     HE grenades only, refilled endlessly
//   ghost     everybody is almost invisible
//   juggernaut one player with 1000 HP and an M249 against everybody else
//
// Cvars: fun_rounds_enabled (1), fun_rounds_every (3 = every third round).
// Admins force the next round with: amx_funround <name|random|off>
//
// Only runs in the classic mode, and not on maps with their own weapon rules
// (35hp_, ka_, he_, deathrun_, surf_). Everything is applied on spawn and
// undone on the next spawn, so nothing outlives its round.

#include <amxmodx>
#include <amxmisc>
#include <cstrike>
#include <fakemeta>
#include <fun>
#include <hamsandwich>
#include <fun_common>

#pragma semicolon 1

#define PLUGIN_NAME "Fun Rounds"
#define PLUGIN_VERSION "1.0"
#define PLUGIN_AUTHOR "LAN"

#define TASK_EQUIP_PLAYER 9100
#define TASK_HE_REFILL 9200
#define TASK_ZBOT_HOOKS 9300

const FUN_ROUND_ADMIN_FLAG = ADMIN_SLAY;
const NO_EVENT = -1;

// ReGameDLL hands out the spawn weapons right after spawn, so equipping
// waits a moment to strip those instead of racing them.
const Float:EQUIP_DELAY_SECONDS = 0.2;
const Float:HE_REFILL_INTERVAL_SECONDS = 1.0;
const Float:LOW_GRAVITY = 0.35;
const Float:FAST_SPEED_FACTOR = 1.8;
const Float:ONE_SHOT_DAMAGE = 500.0;
const GHOST_ALPHA = 25;
const AWP_RESERVE_AMMO = 30;
const JUGGERNAUT_HEALTH = 1000;
const JUGGERNAUT_ARMOR = 200;
const JUGGERNAUT_RESERVE_AMMO = 200;
const NO_PLAYER = 0;

enum _:FunEvent {
    EVENT_KNIVES,
    EVENT_AWP,
    EVENT_LOW_GRAVITY,
    EVENT_SPEED,
    EVENT_HEADSHOT,
    EVENT_DEAGLE,
    EVENT_HE_WAR,
    EVENT_GHOST,
    EVENT_JUGGERNAUT
};

new const EVENT_IDS[FunEvent][] = {
    "knives",
    "awp",
    "lowgrav",
    "speed",
    "headshot",
    "deagle",
    "hewar",
    "ghost",
    "juggernaut"
};

new const EVENT_TITLES[FunEvent][] = {
    "KNIVES ONLY",
    "AWP ONLY",
    "LOW GRAVITY",
    "SPEED ROUND",
    "HEADSHOTS ONLY",
    "ONE BULLET DEAGLE",
    "HE GRENADE WAR",
    "GHOST ROUND",
    "JUGGERNAUT"
};

new const EVENT_HINTS[FunEvent][] = {
    "Buying is off, sharpen your knife.",
    "Buying is off, everybody gets an AWP.",
    "Jump!",
    "Everybody runs almost twice as fast.",
    "Body shots do nothing.",
    "One shot kills. Every kill gives you a new bullet.",
    "Endless grenades, no guns.",
    "Everybody is almost invisible.",
    "One player with 1000 HP and an M249 against everybody else."
};

new const SPECIAL_MAP_PATTERN[][] = {
    "35hp",
    "ka_",
    "he_",
    "deathrun_",
    "surf_"
};

new bool:gIsEnabledHere;
new bool:gAreZbotHooksRegistered;
new gActiveEvent = NO_EVENT;
new gLastEvent = NO_EVENT;
new gForcedEvent = NO_EVENT;
new bool:gIsForcedOff;
new gRoundsPlayed;
new gEnabledCvar;
new gEveryCvar;
new gHudSync;
new gJuggernautId = NO_PLAYER;

public plugin_init() {
    register_plugin(PLUGIN_NAME, PLUGIN_VERSION, PLUGIN_AUTHOR);

    gEnabledCvar = create_cvar("fun_rounds_enabled", "1", _, "Fun rounds on (1) or off (0)", true, 0.0, true, 1.0);
    gEveryCvar = create_cvar("fun_rounds_every", "3", _, "A fun round every n rounds", true, 1.0, true, 20.0);

    register_concmd("amx_funround", "cmdForceEvent", FUN_ROUND_ADMIN_FLAG, "<knives|awp|lowgrav|speed|headshot|deagle|hewar|ghost|juggernaut|random|off> - sets the next round");

    register_event("HLTV", "onNewRound", "a", "1=0", "2=0");
    register_event("DeathMsg", "onDeath", "a");

    RegisterHam(Ham_Spawn, "player", "onPlayerSpawned", 1);
    RegisterHam(Ham_TakeDamage, "player", "onPlayerTakeDamage");
    RegisterHam(Ham_TraceAttack, "player", "onPlayerTraceAttack");
    RegisterHam(Ham_CS_Player_ResetMaxSpeed, "player", "onResetMaxSpeed", 1);
    RegisterHam(Ham_Touch, "weaponbox", "onWeaponTouched");
    RegisterHam(Ham_Touch, "armoury_entity", "onWeaponTouched");
    RegisterHam(Ham_Touch, "weapon_shield", "onWeaponTouched");

    gHudSync = CreateHudSyncObj();
}

public plugin_cfg() {
    // A mode switch always changes the map, so checking once per map is enough.
    gIsEnabledHere = is_fun_mode(FUN_MODE_CLASSIC) && !isSpecialMap();
}

public client_putinserver(playerId) {
    if (!gIsEnabledHere || gAreZbotHooksRegistered || !is_zbot(playerId)) {
        return;
    }
    set_task(FUN_ZBOT_HOOK_DELAY, "registerZbotHooks", TASK_ZBOT_HOOKS + playerId);
}

public client_disconnected(playerId) {
    remove_task(TASK_EQUIP_PLAYER + playerId);
    remove_task(TASK_ZBOT_HOOKS + playerId);
}

/**
 * zBot bots have their own vtable (see fun_common.inc), so the player hooks
 * are registered once more on the first bot. All bots share that vtable,
 * a second registration would run every handler twice.
 */
public registerZbotHooks(taskId) {
    new botId = taskId - TASK_ZBOT_HOOKS;
    if (gAreZbotHooksRegistered || !is_user_connected(botId)) {
        return;
    }
    gAreZbotHooksRegistered = true;

    RegisterHamFromEntity(Ham_Spawn, botId, "onPlayerSpawned", 1);
    RegisterHamFromEntity(Ham_TakeDamage, botId, "onPlayerTakeDamage");
    RegisterHamFromEntity(Ham_TraceAttack, botId, "onPlayerTraceAttack");
    RegisterHamFromEntity(Ham_CS_Player_ResetMaxSpeed, botId, "onResetMaxSpeed", 1);
}

public cmdForceEvent(adminId, level, commandId) {
    if (!cmd_access(adminId, level, commandId, 2)) {
        return PLUGIN_HANDLED;
    }

    new requested[16];
    read_argv(1, requested, charsmax(requested));
    strtolower(requested);

    if (equal(requested, "off")) {
        gForcedEvent = NO_EVENT;
        gIsForcedOff = true;
        console_print(adminId, "The next round is a normal round.");
        return PLUGIN_HANDLED;
    }

    new eventIndex = NO_EVENT;
    if (equal(requested, "random")) {
        eventIndex = pickRandomEvent();
    } else {
        eventIndex = findEvent(requested);
    }

    if (eventIndex == NO_EVENT) {
        console_print(adminId, "Unknown fun round. Possible: knives, awp, lowgrav, speed, headshot, deagle, hewar, ghost, juggernaut, random, off");
        return PLUGIN_HANDLED;
    }

    gForcedEvent = eventIndex;
    gIsForcedOff = false;
    console_print(adminId, "Next round: %s", EVENT_TITLES[eventIndex]);
    if (!gIsEnabledHere) {
        console_print(adminId, "Note: fun rounds only run in Classic and not on knife, HE, deathrun or surf maps.");
    }
    return PLUGIN_HANDLED;
}

public onNewRound() {
    remove_task(TASK_HE_REFILL);
    gActiveEvent = NO_EVENT;
    gJuggernautId = NO_PLAYER;

    if (!gIsEnabledHere || !get_pcvar_num(gEnabledCvar)) {
        return;
    }

    gRoundsPlayed++;
    gActiveEvent = chooseEventForRound();
    if (gActiveEvent == NO_EVENT) {
        return;
    }

    // HLTV fires before the players respawn, so the teams set here spawn right.
    if (gActiveEvent == EVENT_JUGGERNAUT && !setUpJuggernaut()) {
        gActiveEvent = NO_EVENT;
        return;
    }

    gLastEvent = gActiveEvent;
    announceEvent(gActiveEvent);
    if (gActiveEvent == EVENT_JUGGERNAUT) {
        new juggernautName[MAX_NAME_LENGTH];
        get_user_name(gJuggernautId, juggernautName, charsmax(juggernautName));
        client_print(0, print_chat, "[Fun] %s is the Juggernaut. Everybody else: hunt them down!", juggernautName);
        log_amx("Juggernaut round: %s", juggernautName);
    }

    if (gActiveEvent == EVENT_HE_WAR) {
        set_task(HE_REFILL_INTERVAL_SECONDS, "refillGrenades", TASK_HE_REFILL, _, _, "b");
    }
}

chooseEventForRound() {
    if (gIsForcedOff) {
        gIsForcedOff = false;
        return NO_EVENT;
    }

    if (gForcedEvent != NO_EVENT) {
        new forcedEvent = gForcedEvent;
        gForcedEvent = NO_EVENT;
        return forcedEvent;
    }

    if (gRoundsPlayed % get_pcvar_num(gEveryCvar) != 0) {
        return NO_EVENT;
    }
    return pickRandomEvent();
}

/**
 * Picks a random event that differs from the previous one, so the same
 * surprise never comes twice in a row.
 */
pickRandomEvent() {
    new eventIndex = random(FunEvent);
    if (eventIndex == gLastEvent) {
        eventIndex = (eventIndex + 1 + random(FunEvent - 1)) % FunEvent;
    }
    return eventIndex;
}

announceEvent(eventIndex) {
    set_hudmessage(255, 200, 0, -1.0, 0.25, 1, 3.0, 6.0, 0.1, 0.5);
    ShowSyncHudMsg(0, gHudSync, "FUN ROUND: %s^n%s", EVENT_TITLES[eventIndex], EVENT_HINTS[eventIndex]);
    client_print(0, print_chat, "[Fun] Fun round: %s - %s", EVENT_TITLES[eventIndex], EVENT_HINTS[eventIndex]);
    client_cmd(0, "spk buttons/bell1");
}

public onPlayerSpawned(playerId) {
    if (!is_user_alive(playerId)) {
        return;
    }

    // Undo the previous round first, every player spawns at a round start.
    set_user_gravity(playerId, 1.0);
    set_user_rendering(playerId);

    if (gActiveEvent == NO_EVENT) {
        return;
    }

    remove_task(TASK_EQUIP_PLAYER + playerId);
    set_task(EQUIP_DELAY_SECONDS, "applyEventToPlayer", TASK_EQUIP_PLAYER + playerId);
}

public applyEventToPlayer(taskId) {
    new playerId = taskId - TASK_EQUIP_PLAYER;
    if (!is_user_alive(playerId)) {
        return;
    }

    switch (gActiveEvent) {
        case EVENT_KNIVES: {
            equipOnly(playerId, "");
        }
        case EVENT_AWP: {
            equipOnly(playerId, "weapon_awp");
            cs_set_user_bpammo(playerId, CSW_AWP, AWP_RESERVE_AMMO);
        }
        case EVENT_LOW_GRAVITY: {
            set_user_gravity(playerId, LOW_GRAVITY);
        }
        case EVENT_SPEED: {
            ExecuteHamB(Ham_CS_Player_ResetMaxSpeed, playerId);
        }
        case EVENT_DEAGLE: {
            new deagle = equipOnly(playerId, "weapon_deagle");
            if (deagle > 0) {
                cs_set_weapon_ammo(deagle, 1);
            }
            cs_set_user_bpammo(playerId, CSW_DEAGLE, 0);
        }
        case EVENT_HE_WAR: {
            equipOnly(playerId, "weapon_hegrenade");
        }
        case EVENT_JUGGERNAUT: {
            if (playerId == gJuggernautId) {
                equipJuggernaut(playerId);
            }
        }
        case EVENT_GHOST: {
            set_user_rendering(playerId, kRenderFxNone, 0, 0, 0, kRenderTransAlpha, GHOST_ALPHA);
        }
    }
}

/**
 * Picks a random player as the Juggernaut and puts them alone on the
 * Terrorist side, everybody else on CT. The normal team balance mixes the
 * teams again for the next round. Needs at least two players.
 */
bool:setUpJuggernaut() {
    new candidates[MAX_PLAYERS], candidateCount = 0;
    for (new playerId = 1; playerId <= MaxClients; playerId++) {
        if (!is_user_connected(playerId) || is_user_hltv(playerId)) {
            continue;
        }
        new CsTeams:team = cs_get_user_team(playerId);
        if (team == CS_TEAM_T || team == CS_TEAM_CT) {
            candidates[candidateCount++] = playerId;
        }
    }
    if (candidateCount < 2) {
        return false;
    }

    gJuggernautId = candidates[random(candidateCount)];
    for (new i = 0; i < candidateCount; i++) {
        if (candidates[i] == gJuggernautId) {
            cs_set_user_team(candidates[i], CS_TEAM_T, CS_T_LEET);
        } else {
            cs_set_user_team(candidates[i], CS_TEAM_CT, CS_CT_URBAN);
        }
    }
    return true;
}

equipJuggernaut(playerId) {
    equipOnly(playerId, "weapon_m249");
    cs_set_user_bpammo(playerId, CSW_M249, JUGGERNAUT_RESERVE_AMMO);
    set_user_health(playerId, JUGGERNAUT_HEALTH);
    cs_set_user_armor(playerId, JUGGERNAUT_ARMOR, CS_ARMOR_VESTHELM);
    set_user_rendering(playerId, kRenderFxGlowShell, 255, 30, 30, kRenderNormal, 25);
}

/**
 * Leaves the player with a knife plus the given weapon (empty for none) and
 * returns the entity of that weapon.
 */
equipOnly(playerId, const weaponName[]) {
    strip_user_weapons(playerId);
    give_item(playerId, "weapon_knife");

    if (weaponName[0] == EOS) {
        return 0;
    }
    return give_item(playerId, weaponName);
}

public refillGrenades() {
    new players[MAX_PLAYERS], playerCount;
    get_players(players, playerCount, "a");

    for (new i = 0; i < playerCount; i++) {
        if (!user_has_weapon(players[i], CSW_HEGRENADE)) {
            give_item(players[i], "weapon_hegrenade");
        }
    }
}

public onDeath() {
    if (gActiveEvent != EVENT_DEAGLE) {
        return;
    }

    new killerId = read_data(1);
    new victimId = read_data(2);
    if (killerId == victimId || !is_user_alive(killerId)) {
        return;
    }

    new deagle = findWeaponOfPlayer(killerId, "weapon_deagle");
    if (deagle > 0) {
        cs_set_weapon_ammo(deagle, cs_get_weapon_ammo(deagle) + 1);
    }
}

findWeaponOfPlayer(playerId, const weaponName[]) {
    new weaponId = -1;
    while ((weaponId = engfunc(EngFunc_FindEntityByString, weaponId, "classname", weaponName)) > 0) {
        if (pev(weaponId, pev_owner) == playerId) {
            return weaponId;
        }
    }
    return 0;
}

public onPlayerTakeDamage(victimId, inflictorId, attackerId, Float:damage, damageBits) {
    if (gActiveEvent != EVENT_DEAGLE) {
        return HAM_IGNORED;
    }

    new isDeagleShot = is_user_alive(attackerId) && (damageBits & DMG_BULLET) && get_user_weapon(attackerId) == CSW_DEAGLE;
    if (!isDeagleShot) {
        return HAM_IGNORED;
    }

    SetHamParamFloat(4, ONE_SHOT_DAMAGE);
    return HAM_HANDLED;
}

public onPlayerTraceAttack(victimId, attackerId, Float:damage, Float:direction[3], traceHandle, damageBits) {
    if (gActiveEvent != EVENT_HEADSHOT) {
        return HAM_IGNORED;
    }

    if (get_tr2(traceHandle, TR_iHitgroup) == HIT_HEAD) {
        return HAM_IGNORED;
    }
    return HAM_SUPERCEDE;
}

public onResetMaxSpeed(playerId) {
    if (gActiveEvent != EVENT_SPEED || !is_user_alive(playerId)) {
        return;
    }

    // Freeze time sets the speed to 1, which must stay frozen.
    new Float:currentSpeed = get_user_maxspeed(playerId);
    if (currentSpeed > 1.0) {
        set_user_maxspeed(playerId, currentSpeed * FAST_SPEED_FACTOR);
    }
}

public onWeaponTouched(weaponId, toucherId) {
    if (!isWeaponRestricted() || !is_user_alive(toucherId)) {
        return HAM_IGNORED;
    }
    return HAM_SUPERCEDE;
}

public CS_OnBuyAttempt(playerId, item) {
    if (isWeaponRestricted()) {
        return PLUGIN_HANDLED;
    }
    return PLUGIN_CONTINUE;
}

bool:isWeaponRestricted() {
    switch (gActiveEvent) {
        case EVENT_KNIVES, EVENT_AWP, EVENT_DEAGLE, EVENT_HE_WAR: {
            return true;
        }
    }
    return false;
}

bool:isSpecialMap() {
    new mapName[MAX_MAPNAME_LENGTH];
    get_mapname(mapName, charsmax(mapName));

    for (new i = 0; i < sizeof(SPECIAL_MAP_PATTERN); i++) {
        if (equali(mapName, SPECIAL_MAP_PATTERN[i], strlen(SPECIAL_MAP_PATTERN[i]))) {
            return true;
        }
    }
    return false;
}

findEvent(const eventId[]) {
    for (new eventIndex = 0; eventIndex < FunEvent; eventIndex++) {
        if (equal(EVENT_IDS[eventIndex], eventId)) {
            return eventIndex;
        }
    }
    return NO_EVENT;
}
