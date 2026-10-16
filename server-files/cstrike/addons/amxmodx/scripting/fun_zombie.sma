// Fun Zombie - a lightweight zombie infection mode without custom models.
//
// Only active while the server runs the "zombie" mode. Everybody starts the
// round as a human on the CT side. After a short countdown a few random
// players turn into zombies (Terrorists): green glow, lots of health, fast,
// low gravity and knife only. A zombie hit infects a human instead of hurting
// them, only the last human can be killed for real. Zombies that die come
// back after a few seconds while the round is running.
//
// The round ends through the normal game rules: when the last human dies the
// zombies win, when the round time runs out the humans win. That is why
// modes/zombie.cfg disables the bomb and limits the cycle to maps without
// hostages.

#include <amxmodx>
#include <cstrike>
#include <fun>
#include <hamsandwich>
#include <fakemeta>
#include <fun_common>

#pragma semicolon 1

#define PLUGIN_NAME "Fun Zombie"
#define PLUGIN_VERSION "1.0"
#define PLUGIN_AUTHOR "LAN"

#define TASK_COUNTDOWN 6100
#define TASK_ZOMBIE_RESPAWN 6200

const INFECTION_COUNTDOWN_SECONDS = 10;
const PLAYERS_PER_FIRST_ZOMBIE = 6;
const MIN_PLAYERS_FOR_ROUND = 2;
const FIRST_ZOMBIE_HEALTH = 3000;
const ZOMBIE_HEALTH = 2000;
const Float:ZOMBIE_SPEED = 290.0;
const Float:ZOMBIE_GRAVITY = 0.7;
const Float:ZOMBIE_RESPAWN_SECONDS = 5.0;
const HUMAN_MONEY = 16000;

new const INFECTION_SOUND[] = "zombie/zo_alert10.wav";
new const ZOMBIE_DEATH_SOUND[] = "zombie/zo_die1.wav";

new bool:gIsZombie[MAX_PLAYERS + 1];
new bool:gIsInfectionStarted;
new bool:gIsRoundRunning;
new gCountdownSecondsLeft;
new gHudSync;
new gScreenFadeMessage;

public plugin_precache()
{
    if (!is_fun_mode(FUN_MODE_ZOMBIE)) {
        return;
    }

    precache_sound(INFECTION_SOUND);
    precache_sound(ZOMBIE_DEATH_SOUND);
}

public plugin_init()
{
    register_plugin(PLUGIN_NAME, PLUGIN_VERSION, PLUGIN_AUTHOR);

    if (!is_fun_mode(FUN_MODE_ZOMBIE)) {
        return;
    }

    // HLTV fires before players respawn for a new round, the perfect moment
    // to move everybody back to the human side.
    register_event("HLTV", "onNewRound", "a", "1=0", "2=0");
    register_logevent("onRoundStart", 2, "1=Round_Start");
    register_logevent("onRoundEnd", 2, "1=Round_End");

    RegisterHam(Ham_Spawn, "player", "onPlayerSpawned", 1);
    RegisterHam(Ham_Killed, "player", "onPlayerKilled", 1);
    RegisterHam(Ham_TakeDamage, "player", "onPlayerTakeDamage");
    RegisterHam(Ham_CS_Player_ResetMaxSpeed, "player", "onResetMaxSpeed", 1);
    RegisterHam(Ham_AddPlayerItem, "player", "onAddPlayerItem");
    RegisterHam(Ham_Touch, "weaponbox", "onWeaponTouched");
    RegisterHam(Ham_Touch, "armoury_entity", "onWeaponTouched");

    gHudSync = CreateHudSyncObj();
    gScreenFadeMessage = get_user_msgid("ScreenFade");
}

public client_putinserver(playerId)
{
    gIsZombie[playerId] = false;
}

public client_disconnected(playerId)
{
    remove_task(TASK_ZOMBIE_RESPAWN + playerId);

    new wasZombie = gIsZombie[playerId];
    gIsZombie[playerId] = false;

    // If the only zombie leaves, the round would stall with humans only.
    if (wasZombie && gIsInfectionStarted && countAliveZombies() == 0) {
        infectRandomHumans(1);
    }
}

public onNewRound()
{
    gIsInfectionStarted = false;
    gIsRoundRunning = false;
    remove_task(TASK_COUNTDOWN);

    for (new playerId = 1; playerId <= MaxClients; playerId++) {
        remove_task(TASK_ZOMBIE_RESPAWN + playerId);
        gIsZombie[playerId] = false;

        if (!is_user_connected(playerId)) {
            continue;
        }

        new CsTeams:team = cs_get_user_team(playerId);
        if (team == CS_TEAM_T || team == CS_TEAM_CT) {
            cs_set_user_team(playerId, CS_TEAM_CT, CS_CT_URBAN);
        }
    }
}

public onRoundStart()
{
    gIsRoundRunning = true;
    gCountdownSecondsLeft = INFECTION_COUNTDOWN_SECONDS;
    set_task(1.0, "tickCountdown", TASK_COUNTDOWN, _, _, "a", INFECTION_COUNTDOWN_SECONDS);
}

public onRoundEnd()
{
    gIsRoundRunning = false;
    remove_task(TASK_COUNTDOWN);

    if (!gIsInfectionStarted) {
        return;
    }

    set_hudmessage(0, 255, 0, -1.0, 0.25, 0, 0.0, 5.0, 0.1, 0.5, -1);
    if (countAliveHumans() == 0) {
        ShowSyncHudMsg(0, gHudSync, "The zombies won!");
    } else {
        ShowSyncHudMsg(0, gHudSync, "The humans survived!");
    }
}

public tickCountdown()
{
    gCountdownSecondsLeft--;

    if (gCountdownSecondsLeft > 0) {
        set_hudmessage(255, 50, 50, -1.0, 0.25, 0, 0.0, 1.1, 0.0, 0.0, -1);
        ShowSyncHudMsg(0, gHudSync, "Infection in %d...", gCountdownSecondsLeft);
        return;
    }

    new humanCount = countAliveHumans();
    if (humanCount < MIN_PLAYERS_FOR_ROUND) {
        set_hudmessage(255, 255, 255, -1.0, 0.25, 0, 0.0, 4.0, 0.1, 0.5, -1);
        ShowSyncHudMsg(0, gHudSync, "Not enough players for an infection.");
        return;
    }

    gIsInfectionStarted = true;
    infectRandomHumans(max(1, humanCount / PLAYERS_PER_FIRST_ZOMBIE));
}

infectRandomHumans(zombieCount)
{
    for (new i = 0; i < zombieCount; i++) {
        new humans[MAX_PLAYERS], humanCount = 0;
        collectAliveHumans(humans, humanCount);

        // Always leave at least one human, otherwise the round ends instantly.
        if (humanCount < 2) {
            return;
        }

        new chosenId = humans[random(humanCount)];
        turnIntoZombie(chosenId, FIRST_ZOMBIE_HEALTH);

        new zombieName[MAX_NAME_LENGTH];
        get_user_name(chosenId, zombieName, charsmax(zombieName));
        client_print(0, print_chat, "[Zombie] %s is the first zombie! Run!", zombieName);
    }
}

turnIntoZombie(playerId, health)
{
    gIsZombie[playerId] = true;

    cs_set_user_team(playerId, CS_TEAM_T, CS_T_LEET);
    applyZombieTraits(playerId, health);

    emit_sound(playerId, CHAN_VOICE, INFECTION_SOUND, VOL_NORM, ATTN_NORM, 0, PITCH_NORM);
    flashScreenGreen(playerId);
}

applyZombieTraits(playerId, health)
{
    strip_user_weapons(playerId);
    give_item(playerId, "weapon_knife");

    set_user_health(playerId, health);
    set_user_gravity(playerId, ZOMBIE_GRAVITY);
    cs_set_user_armor(playerId, 0, CS_ARMOR_NONE);
    cs_set_user_money(playerId, 0, 0);
    set_user_rendering(playerId, kRenderFxGlowShell, 0, 255, 0, kRenderNormal, 20);

    cs_set_user_nvg(playerId, 1);
    client_cmd(playerId, "nightvision");

    // Trigger the speed hook below without waiting for a weapon switch.
    ExecuteHamB(Ham_CS_Player_ResetMaxSpeed, playerId);
}

clearZombieTraits(playerId)
{
    set_user_gravity(playerId, 1.0);
    set_user_rendering(playerId);
    cs_set_user_nvg(playerId, 0);
}

flashScreenGreen(playerId)
{
    const FADE_DURATION_UNITS = 1 << 12;
    const FADE_IN = 0x0000;

    message_begin(MSG_ONE_UNRELIABLE, gScreenFadeMessage, _, playerId);
    write_short(FADE_DURATION_UNITS);
    write_short(FADE_DURATION_UNITS);
    write_short(FADE_IN);
    write_byte(0);
    write_byte(200);
    write_byte(0);
    write_byte(120);
    message_end();
}

public onPlayerSpawned(playerId)
{
    if (!is_user_alive(playerId)) {
        return;
    }

    if (gIsZombie[playerId]) {
        applyZombieTraits(playerId, ZOMBIE_HEALTH);
        return;
    }

    clearZombieTraits(playerId);
    cs_set_user_money(playerId, HUMAN_MONEY, 0);
}

public onPlayerKilled(victimId, killerId, shouldGib)
{
    if (!gIsZombie[victimId]) {
        return;
    }

    emit_sound(victimId, CHAN_VOICE, ZOMBIE_DEATH_SOUND, VOL_NORM, ATTN_NORM, 0, PITCH_NORM);

    if (gIsRoundRunning) {
        set_task(ZOMBIE_RESPAWN_SECONDS, "respawnZombie", TASK_ZOMBIE_RESPAWN + victimId);
    }
}

public respawnZombie(taskId)
{
    new playerId = taskId - TASK_ZOMBIE_RESPAWN;

    new canRespawn = gIsRoundRunning && gIsZombie[playerId] && is_user_connected(playerId) && !is_user_alive(playerId);
    if (canRespawn) {
        ExecuteHamB(Ham_CS_RoundRespawn, playerId);
    }
}

public onPlayerTakeDamage(victimId, inflictorId, attackerId, Float:damage, damageBits)
{
    new isZombieHittingHuman = (is_user_connected(attackerId) && attackerId != victimId && gIsZombie[attackerId] && !gIsZombie[victimId]);
    if (!isZombieHittingHuman) {
        return HAM_IGNORED;
    }

    // The last human has to be killed for real so the round can end.
    if (countAliveHumans() <= 1) {
        return HAM_IGNORED;
    }

    infectByAttack(victimId, attackerId);
    return HAM_SUPERCEDE;
}

infectByAttack(victimId, attackerId)
{
    turnIntoZombie(victimId, ZOMBIE_HEALTH);
    set_user_frags(attackerId, get_user_frags(attackerId) + 1);

    new attackerName[MAX_NAME_LENGTH], victimName[MAX_NAME_LENGTH];
    get_user_name(attackerId, attackerName, charsmax(attackerName));
    get_user_name(victimId, victimName, charsmax(victimName));
    client_print(0, print_chat, "[Zombie] %s infected %s.", attackerName, victimName);

    if (countAliveHumans() == 1) {
        announceLastHuman();
    }
}

announceLastHuman()
{
    new humans[MAX_PLAYERS], humanCount = 0;
    collectAliveHumans(humans, humanCount);
    if (humanCount == 0) {
        return;
    }

    new lastHumanName[MAX_NAME_LENGTH];
    get_user_name(humans[0], lastHumanName, charsmax(lastHumanName));

    set_hudmessage(255, 255, 0, -1.0, 0.25, 0, 0.0, 4.0, 0.1, 0.5, -1);
    ShowSyncHudMsg(0, gHudSync, "%s is the last human!", lastHumanName);
}

public onResetMaxSpeed(playerId)
{
    // A max speed of 1 means the player is frozen (freeze time), leave that alone.
    if (is_user_alive(playerId) && gIsZombie[playerId] && get_user_maxspeed(playerId) > 1.0) {
        set_user_maxspeed(playerId, ZOMBIE_SPEED);
    }
}

public onAddPlayerItem(playerId, itemEntity)
{
    if (!gIsZombie[playerId] || !pev_valid(itemEntity)) {
        return HAM_IGNORED;
    }

    if (cs_get_weapon_id(itemEntity) == CSW_KNIFE) {
        return HAM_IGNORED;
    }

    // Zombies only fight with claws. The rejected item would otherwise stay
    // around as an invisible entity, so remove it.
    set_pev(itemEntity, pev_flags, pev(itemEntity, pev_flags) | FL_KILLME);
    return HAM_SUPERCEDE;
}

public onWeaponTouched(weaponEntity, toucherId)
{
    if (is_user_alive(toucherId) && gIsZombie[toucherId]) {
        return HAM_SUPERCEDE;
    }
    return HAM_IGNORED;
}

collectAliveHumans(humans[MAX_PLAYERS], &humanCount)
{
    humanCount = 0;
    for (new playerId = 1; playerId <= MaxClients; playerId++) {
        if (is_user_alive(playerId) && !gIsZombie[playerId]) {
            humans[humanCount] = playerId;
            humanCount++;
        }
    }
}

countAliveHumans()
{
    new humans[MAX_PLAYERS], humanCount = 0;
    collectAliveHumans(humans, humanCount);
    return humanCount;
}

countAliveZombies()
{
    new zombieCount = 0;
    for (new playerId = 1; playerId <= MaxClients; playerId++) {
        if (is_user_alive(playerId) && gIsZombie[playerId]) {
            zombieCount++;
        }
    }
    return zombieCount;
}
