// Fun Modes - switches the server between the five LAN game modes.
//
// Players start a vote with "/mode" in chat, admins can switch directly
// with "amx_funmode <name>". On a switch the plugin stores the new mode,
// points mapcyclefile at the mode's own map list and changes to a random map
// from it. On every map start it executes modes/base.cfg followed by
// modes/<mode>.cfg, so each mode always starts from the same clean settings.

#include <amxmodx>
#include <amxmisc>
#include <fun_common>

#pragma semicolon 1

#define PLUGIN_NAME "Fun Modes"
#define PLUGIN_VERSION "1.0"
#define PLUGIN_AUTHOR "LAN"

#define TASK_VOTE_END 4100
#define TASK_MAP_CHANGE 4200
#define TASK_BOT_QUOTA 4300
#define LOCAL_CONFIG "local.cfg"
#define TASK_LOCAL_CONFIG 4400

const Float:LOCAL_CONFIG_REAPPLY_DELAY_SECONDS = 1.0;

#define BOTS_LOCAL_CONFIG "local_bots.cfg"

// YaPB runs yapb.cfg again a moment after every map start and puts the
// previous map's yb_quota back (yb_ignore_cvars_on_changelevel), so the bot
// values from our configs are applied again a few times after that.
const Float:BOT_SETTINGS_REAPPLY_INTERVAL_SECONDS = 2.0;
const BOT_SETTINGS_REAPPLY_COUNT = 3;
const BOT_SETTING_COUNT = 5;
const BOT_VALUE_LENGTH = 16;

new const BOT_SETTING_CVARS[BOT_SETTING_COUNT][] = {
    "yb_quota",
    "yb_difficulty",
    "yb_chat",
    "yb_chat_percent",
    "yb_radio_mode"
};

const MODE_COUNT = 5;
const Float:VOTE_DURATION_SECONDS = 15.0;
const Float:VOTE_COOLDOWN_SECONDS = 120.0;
const Float:MAP_CHANGE_DELAY_SECONDS = 5.0;
const Float:WELCOME_DELAY_SECONDS = 8.0;

new const MODE_IDS[MODE_COUNT][] = {
    "classic",
    "gungame",
    "zombie",
    "deathmatch",
    "deathrun"
};

new const MODE_TITLES[MODE_COUNT][] = {
    "Classic Fun (Hook, Grab, Parachute)",
    "GunGame",
    "Zombie Infection",
    "Deathmatch",
    "Deathrun"
};

new gActiveMode[FUN_MODE_LENGTH];
new bool:gIsVoteRunning;
new bool:gIsMapChangePending;
new Float:gNextVoteAllowedAt;
new gVoteMenu;
new gVoteCounts[MODE_COUNT];
new bool:gHasVoted[MAX_PLAYERS + 1];
new gBotSettingPointers[BOT_SETTING_COUNT];
new gWantedBotValues[BOT_SETTING_COUNT][BOT_VALUE_LENGTH];

public plugin_init()
{
    register_plugin(PLUGIN_NAME, PLUGIN_VERSION, PLUGIN_AUTHOR);

    register_clcmd("say /mode", "cmdStartVote");
    register_clcmd("say_team /mode", "cmdStartVote");
    register_concmd("amx_funmode", "cmdSetMode", ADMIN_MAP, "<classic|gungame|zombie|deathmatch|deathrun> - switches the mode right away");

    get_fun_mode(gActiveMode, charsmax(gActiveMode));
}

public plugin_cfg()
{
    // base.cfg resets everything the other modes might have changed, then
    // the mode file only has to list what makes that mode special.
    server_cmd("exec modes/base.cfg");
    server_cmd("exec modes/%s.cfg", gActiveMode);

    // What the host set in the Server Control window for the bots: first for
    // every mode (difficulty, chat ...), then for this mode only (bot count).
    // Both run before the map configs on purpose, so a map like surf or
    // de_rats can still overrule them.
    execIfExists(BOTS_LOCAL_CONFIG);
    new modeLocalConfig[64];
    formatex(modeLocalConfig, charsmax(modeLocalConfig), "local_%s.cfg", gActiveMode);
    execIfExists(modeLocalConfig);

    // Some map types need settings of their own in every mode, surf for
    // example needs a high sv_airaccelerate: modes/maps/<prefix>.cfg. Single
    // maps can go further with modes/maps/<mapname>.cfg, which runs after it.
    new mapName[MAX_MAPNAME_LENGTH];
    get_mapname(mapName, charsmax(mapName));
    strtolower(mapName);

    new mapTypeConfig[64];
    if (findMapTypeConfig(mapName, mapTypeConfig, charsmax(mapTypeConfig))) {
        server_cmd("exec %s", mapTypeConfig);
        log_amx("Map type settings: %s", mapTypeConfig);
    }

    new mapConfig[64];
    formatex(mapConfig, charsmax(mapConfig), "modes/maps/%s.cfg", mapName);
    if (file_exists(mapConfig) && !equal(mapConfig, mapTypeConfig)) {
        server_cmd("exec %s", mapConfig);
        log_amx("Map settings: %s", mapConfig);
    }

    // local.cfg holds what the host set in the Server Control window (server
    // name, RCON password ...). It lives only in server\cstrike, the installer
    // never overwrites it, and it runs last so it wins over the mode defaults.
    // On the first map the engine runs server.cfg after this, which would
    // reset hostname and friends, so local.cfg runs once more a second later.
    if (file_exists(LOCAL_CONFIG)) {
        server_cmd("exec %s", LOCAL_CONFIG);
        set_task(LOCAL_CONFIG_REAPPLY_DELAY_SECONDS, "reapplyLocalConfig", TASK_LOCAL_CONFIG);
    }
    server_exec();

    log_amx("Active mode: %s", gActiveMode);

    // Without YaPB the pointers stay 0 and nothing is re-applied.
    new isYapbLoaded = false;
    for (new i = 0; i < BOT_SETTING_COUNT; i++) {
        gBotSettingPointers[i] = get_cvar_pointer(BOT_SETTING_CVARS[i]);
        if (gBotSettingPointers[i]) {
            get_pcvar_string(gBotSettingPointers[i], gWantedBotValues[i], BOT_VALUE_LENGTH - 1);
            isYapbLoaded = true;
        }
    }
    if (isYapbLoaded) {
        set_task(BOT_SETTINGS_REAPPLY_INTERVAL_SECONDS, "reapplyBotSettings", TASK_BOT_QUOTA, _, _, "a", BOT_SETTINGS_REAPPLY_COUNT);
    }
}

execIfExists(const configFile[])
{
    if (file_exists(configFile)) {
        server_cmd("exec %s", configFile);
    }
}

public reapplyLocalConfig()
{
    server_cmd("exec %s", LOCAL_CONFIG);
}

public reapplyBotSettings()
{
    new currentValue[BOT_VALUE_LENGTH];
    for (new i = 0; i < BOT_SETTING_COUNT; i++) {
        if (!gBotSettingPointers[i]) {
            continue;
        }

        get_pcvar_string(gBotSettingPointers[i], currentValue, charsmax(currentValue));
        if (equal(currentValue, gWantedBotValues[i])) {
            continue;
        }

        log_amx("%s was %s, setting it back to %s from the configs", BOT_SETTING_CVARS[i], currentValue, gWantedBotValues[i]);
        set_pcvar_string(gBotSettingPointers[i], gWantedBotValues[i]);
    }
}

/**
 * Builds modes/maps/<prefix>.cfg from the part of the (lower case) map name
 * before the first underscore and returns true when that file exists.
 */
bool:findMapTypeConfig(const mapName[], configPath[], length)
{
    new prefix[MAX_MAPNAME_LENGTH];
    copy(prefix, charsmax(prefix), mapName);

    new underscorePosition = contain(prefix, "_");
    if (underscorePosition <= 0) {
        return false;
    }
    prefix[underscorePosition] = EOS;

    formatex(configPath, length, "modes/maps/%s.cfg", prefix);
    return bool:file_exists(configPath);
}

public client_putinserver(playerId)
{
    gHasVoted[playerId] = false;
    set_task(WELCOME_DELAY_SECONDS, "showWelcomeMessage", playerId);
}

public client_disconnected(playerId)
{
    remove_task(playerId);
}

public showWelcomeMessage(playerId)
{
    if (!is_user_connected(playerId)) {
        return;
    }

    new modeIndex = findModeIndex(gActiveMode);
    client_print(playerId, print_chat, "[Fun] Current mode: %s. Type /mode to start a vote.", MODE_TITLES[modeIndex]);
}

public cmdStartVote(playerId)
{
    if (gIsVoteRunning) {
        client_print(playerId, print_chat, "[Fun] A vote is already running.");
        return PLUGIN_HANDLED;
    }

    if (gIsMapChangePending) {
        client_print(playerId, print_chat, "[Fun] The mode is being switched right now.");
        return PLUGIN_HANDLED;
    }

    new Float:secondsUntilAllowed = gNextVoteAllowedAt - get_gametime();
    if (secondsUntilAllowed > 0.0) {
        client_print(playerId, print_chat, "[Fun] Next vote possible in %d seconds.", floatround(secondsUntilAllowed, floatround_ceil));
        return PLUGIN_HANDLED;
    }

    startModeVote(playerId);
    return PLUGIN_CONTINUE;
}

public cmdSetMode(playerId, level, commandId)
{
    if (!cmd_access(playerId, level, commandId, 2)) {
        return PLUGIN_HANDLED;
    }

    new requestedMode[FUN_MODE_LENGTH];
    read_argv(1, requestedMode, charsmax(requestedMode));
    strtolower(requestedMode);

    new modeIndex = findModeIndex(requestedMode);
    if (!equal(MODE_IDS[modeIndex], requestedMode)) {
        console_print(playerId, "Unknown mode. Possible: classic, gungame, zombie, deathmatch, deathrun");
        return PLUGIN_HANDLED;
    }

    new adminName[MAX_NAME_LENGTH];
    get_user_name(playerId, adminName, charsmax(adminName));
    client_print(0, print_chat, "[Fun] Admin %s switches to %s.", adminName, MODE_TITLES[modeIndex]);

    switchToMode(modeIndex);
    return PLUGIN_HANDLED;
}

startModeVote(starterId)
{
    gIsVoteRunning = true;
    arrayset(gVoteCounts, 0, sizeof(gVoteCounts));
    arrayset(gHasVoted, false, sizeof(gHasVoted));

    gVoteMenu = menu_create("\yWhich mode should run next?", "handleVoteMenu");

    for (new modeIndex = 0; modeIndex < MODE_COUNT; modeIndex++) {
        new itemTitle[64];
        if (equal(MODE_IDS[modeIndex], gActiveMode)) {
            formatex(itemTitle, charsmax(itemTitle), "%s \d(running now)", MODE_TITLES[modeIndex]);
        } else {
            copy(itemTitle, charsmax(itemTitle), MODE_TITLES[modeIndex]);
        }
        menu_additem(gVoteMenu, itemTitle);
    }

    menu_setprop(gVoteMenu, MPROP_EXIT, MEXIT_NEVER);

    new players[MAX_PLAYERS], playerCount;
    get_players(players, playerCount, "ch");

    for (new i = 0; i < playerCount; i++) {
        menu_display(players[i], gVoteMenu);
    }

    new starterName[MAX_NAME_LENGTH];
    get_user_name(starterId, starterName, charsmax(starterName));
    client_print(0, print_chat, "[Fun] %s started a mode vote (%d seconds).", starterName, floatround(VOTE_DURATION_SECONDS));

    set_task(VOTE_DURATION_SECONDS, "finishModeVote", TASK_VOTE_END);
}

public handleVoteMenu(playerId, menu, item)
{
    // Destroying the menu at the end of the vote calls this handler with
    // MENU_EXIT for everybody who still had it open, so this guard matters.
    if (!gIsVoteRunning || item < 0 || item >= MODE_COUNT) {
        return PLUGIN_HANDLED;
    }

    if (gHasVoted[playerId]) {
        return PLUGIN_HANDLED;
    }

    gHasVoted[playerId] = true;
    gVoteCounts[item]++;

    new voterName[MAX_NAME_LENGTH];
    get_user_name(playerId, voterName, charsmax(voterName));
    client_print(0, print_chat, "[Fun] %s votes for %s.", voterName, MODE_TITLES[item]);

    return PLUGIN_HANDLED;
}

public finishModeVote()
{
    gIsVoteRunning = false;
    gNextVoteAllowedAt = get_gametime() + VOTE_COOLDOWN_SECONDS;
    menu_destroy(gVoteMenu);

    new winnerIndex = -1;
    new winnerVotes = 0;

    // On a tie the mode listed first wins, which keeps the result predictable.
    for (new modeIndex = 0; modeIndex < MODE_COUNT; modeIndex++) {
        if (gVoteCounts[modeIndex] > winnerVotes) {
            winnerVotes = gVoteCounts[modeIndex];
            winnerIndex = modeIndex;
        }
    }

    if (winnerIndex == -1) {
        client_print(0, print_chat, "[Fun] Nobody voted, the mode stays.");
        return;
    }

    if (equal(MODE_IDS[winnerIndex], gActiveMode)) {
        client_print(0, print_chat, "[Fun] %s stays (%d votes).", MODE_TITLES[winnerIndex], winnerVotes);
        return;
    }

    client_print(0, print_chat, "[Fun] %s won (%d votes).", MODE_TITLES[winnerIndex], winnerVotes);
    switchToMode(winnerIndex);
}

switchToMode(modeIndex)
{
    set_localinfo(FUN_MODE_KEY, MODE_IDS[modeIndex]);

    // mapchooser and nextmap read this cvar on the next map, so they will
    // offer only maps that fit the new mode.
    new mapCycleFile[64];
    formatex(mapCycleFile, charsmax(mapCycleFile), "mapcycle_%s.txt", MODE_IDS[modeIndex]);
    set_cvar_string("mapcyclefile", mapCycleFile);

    new nextMap[MAX_MAPNAME_LENGTH];
    pickRandomMapFromCycle(mapCycleFile, nextMap, charsmax(nextMap));

    gIsMapChangePending = true;
    client_print(0, print_chat, "[Fun] Switching to %s on %s in %d seconds...", MODE_TITLES[modeIndex], nextMap, floatround(MAP_CHANGE_DELAY_SECONDS));

    set_task(MAP_CHANGE_DELAY_SECONDS, "changeToMap", TASK_MAP_CHANGE, nextMap, sizeof(nextMap));
}

public changeToMap(const mapName[])
{
    server_cmd("changelevel %s", mapName);
}

/**
 * Picks a random installed map from the cycle file, preferring one that is
 * not the current map. Falls back to the current map when the list is empty.
 */
pickRandomMapFromCycle(const mapCycleFile[], mapName[], length)
{
    new currentMap[MAX_MAPNAME_LENGTH];
    get_mapname(currentMap, charsmax(currentMap));
    copy(mapName, length, currentMap);

    new fileHandle = fopen(mapCycleFile, "rt");
    if (!fileHandle) {
        log_amx("Map list %s is missing, staying on %s", mapCycleFile, currentMap);
        return;
    }

    // Reservoir sampling: the n-th candidate replaces the pick with chance
    // 1/n, which gives every map the same odds without storing the list.
    // A list of 128 names used to fill the plugin's whole 16 KB stack and
    // crashed the server at the end of every successful vote.
    new candidateCount = 0;
    new line[128];
    while (!feof(fileHandle)) {
        fgets(fileHandle, line, charsmax(line));
        trim(line);

        new isCommentOrEmpty = (line[0] == EOS || line[0] == ';' || (line[0] == '/' && line[1] == '/'));
        if (isCommentOrEmpty) {
            continue;
        }

        // A mapcycle line may carry extra settings after the name.
        new lineMap[MAX_MAPNAME_LENGTH];
        parse(line, lineMap, charsmax(lineMap));

        if (!is_map_valid(lineMap) || equali(lineMap, currentMap)) {
            continue;
        }

        candidateCount++;
        if (random(candidateCount) == 0) {
            copy(mapName, length, lineMap);
        }
    }
    fclose(fileHandle);
}

/**
 * Returns the index of the mode with this id, or 0 (classic) when unknown.
 */
findModeIndex(const modeId[])
{
    for (new modeIndex = 0; modeIndex < MODE_COUNT; modeIndex++) {
        if (equal(MODE_IDS[modeIndex], modeId)) {
            return modeIndex;
        }
    }
    return 0;
}
