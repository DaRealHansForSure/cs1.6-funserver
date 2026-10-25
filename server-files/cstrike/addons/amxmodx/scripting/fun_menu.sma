// Fun Menu - puts the whole fun server on the number keys.
//
// Open it with "/fun" in chat or bind a key: bind F3 "fun_menu"
//
//   1. Start mode vote      everybody
//   2. Switch mode          admin flag "f" (map)
//   3. Change map           admin flag "f", lists the maps of the current mode
//   4. Player fun           admin flag "e" (slay): glow, godmode, noclip,
//                           rocket, speed for one player or everybody
//   5. AMX Mod X admin menu kick, ban, slay, cvars and so on
//
// Every action runs the existing console command (amx_funmode, amx_map,
// amx_glow ...) as if the admin had typed it, so access checks, messages
// and logging stay in one place.

#include <amxmodx>
#include <amxmisc>
#include <fun>
#include <fun_common>

#pragma semicolon 1

#define PLUGIN_NAME "Fun Menu"
#define PLUGIN_VERSION "1.0"
#define PLUGIN_AUTHOR "LAN"

const MODE_ACCESS_FLAG = ADMIN_MAP;
const PLAYER_FUN_ACCESS_FLAG = ADMIN_SLAY;

// Target strings are "#<userid>" or "@ALL", the format amx_glow & co. expect.
const TARGET_LENGTH = 16;

new const MODE_IDS[][] = {
    "classic",
    "gungame",
    "zombie",
    "deathmatch",
    "deathrun"
};

new const MODE_TITLES[][] = {
    "Classic Fun",
    "GunGame",
    "Zombie Infection",
    "Deathmatch",
    "Deathrun"
};

new const GLOW_COLORS[][] = {
    "red",
    "green",
    "blue",
    "yellow",
    "pink",
    "white",
    "off"
};

enum _:PlayerAction {
    ACTION_GLOW,
    ACTION_GODMODE,
    ACTION_NOCLIP,
    ACTION_ROCKET,
    ACTION_SPEED_FAST,
    ACTION_SPEED_NORMAL
};

new const PLAYER_ACTION_TITLES[PlayerAction][] = {
    "Glow...",
    "Godmode on/off",
    "Noclip on/off",
    "Rocket",
    "Speed x2",
    "Speed normal"
};

new gSelectedTarget[MAX_PLAYERS + 1][TARGET_LENGTH];
new gModeAccessCallback;
new gPlayerFunAccessCallback;

public plugin_init() {
    register_plugin(PLUGIN_NAME, PLUGIN_VERSION, PLUGIN_AUTHOR);

    register_clcmd("say /fun", "cmdOpenMenu");
    register_clcmd("say_team /fun", "cmdOpenMenu");
    register_clcmd("say /menu", "cmdOpenMenu");
    register_clcmd("say_team /menu", "cmdOpenMenu");
    register_clcmd("fun_menu", "cmdOpenMenu", _, "- opens the fun menu");

    gModeAccessCallback = menu_makecallback("callbackModeAccess");
    gPlayerFunAccessCallback = menu_makecallback("callbackPlayerFunAccess");
}

public cmdOpenMenu(playerId) {
    showMainMenu(playerId);
    return PLUGIN_HANDLED;
}

// --- Main menu ---------------------------------------------------------------

showMainMenu(playerId) {
    new activeMode[FUN_MODE_LENGTH];
    get_fun_mode(activeMode, charsmax(activeMode));

    new currentMap[MAX_MAPNAME_LENGTH];
    get_mapname(currentMap, charsmax(currentMap));

    new title[128];
    formatex(title, charsmax(title), "\yFun Menu^n\wMode: %s, map: %s", MODE_TITLES[findModeIndex(activeMode)], currentMap);

    new menu = menu_create(title, "handleMainMenu");
    menu_additem(menu, "Start mode vote");
    menu_additem(menu, "Switch mode", _, _, gModeAccessCallback);
    menu_additem(menu, "Change map", _, _, gModeAccessCallback);
    menu_additem(menu, "Player fun", _, _, gPlayerFunAccessCallback);
    menu_additem(menu, "AMX Mod X admin menu");
    menu_display(playerId, menu);
}

public handleMainMenu(playerId, menu, item) {
    menu_destroy(menu);

    switch (item) {
        case 0: {
            amxclient_cmd(playerId, "say", "/mode");
        }
        case 1: {
            showModeMenu(playerId);
        }
        case 2: {
            showMapMenu(playerId);
        }
        case 3: {
            showTargetMenu(playerId);
        }
        case 4: {
            client_cmd(playerId, "amxmodmenu");
        }
    }
    return PLUGIN_HANDLED;
}

public callbackModeAccess(playerId, menu, item) {
    if (get_user_flags(playerId) & MODE_ACCESS_FLAG) {
        return ITEM_ENABLED;
    }
    return ITEM_DISABLED;
}

public callbackPlayerFunAccess(playerId, menu, item) {
    if (get_user_flags(playerId) & PLAYER_FUN_ACCESS_FLAG) {
        return ITEM_ENABLED;
    }
    return ITEM_DISABLED;
}

// --- Switch mode ---------------------------------------------------------------

showModeMenu(playerId) {
    new activeMode[FUN_MODE_LENGTH];
    get_fun_mode(activeMode, charsmax(activeMode));

    new menu = menu_create("\ySwitch mode", "handleModeMenu");
    for (new modeIndex = 0; modeIndex < sizeof(MODE_IDS); modeIndex++) {
        new itemTitle[64];
        if (equal(MODE_IDS[modeIndex], activeMode)) {
            formatex(itemTitle, charsmax(itemTitle), "%s \d(running now)", MODE_TITLES[modeIndex]);
        } else {
            copy(itemTitle, charsmax(itemTitle), MODE_TITLES[modeIndex]);
        }
        menu_additem(menu, itemTitle);
    }
    menu_display(playerId, menu);
}

public handleModeMenu(playerId, menu, item) {
    menu_destroy(menu);

    if (item < 0 || item >= sizeof(MODE_IDS)) {
        return PLUGIN_HANDLED;
    }

    amxclient_cmd(playerId, "amx_funmode", MODE_IDS[item]);
    return PLUGIN_HANDLED;
}

// --- Change map ----------------------------------------------------------------

showMapMenu(playerId) {
    // mapcyclefile always points at the current mode's list, so the admin only
    // sees maps that fit what is running.
    new mapCycleFile[64];
    get_cvar_string("mapcyclefile", mapCycleFile, charsmax(mapCycleFile));

    new fileHandle = fopen(mapCycleFile, "rt");
    if (!fileHandle) {
        client_print(playerId, print_chat, "[Fun] Map list %s not found.", mapCycleFile);
        return;
    }

    new title[96];
    formatex(title, charsmax(title), "\yChange map^n\w%s", mapCycleFile);
    new menu = menu_create(title, "handleMapMenu");

    new currentMap[MAX_MAPNAME_LENGTH];
    get_mapname(currentMap, charsmax(currentMap));

    new line[128];
    while (!feof(fileHandle)) {
        fgets(fileHandle, line, charsmax(line));
        trim(line);

        new isCommentOrEmpty = (line[0] == EOS || line[0] == ';' || (line[0] == '/' && line[1] == '/'));
        if (isCommentOrEmpty) {
            continue;
        }

        new mapName[MAX_MAPNAME_LENGTH];
        parse(line, mapName, charsmax(mapName));
        if (!is_map_valid(mapName)) {
            continue;
        }

        // The map name doubles as item info, so the handler needs no lookup.
        if (equali(mapName, currentMap)) {
            new itemTitle[64];
            formatex(itemTitle, charsmax(itemTitle), "%s \d(running now)", mapName);
            menu_additem(menu, itemTitle, mapName);
        } else {
            menu_additem(menu, mapName, mapName);
        }
    }
    fclose(fileHandle);

    if (menu_items(menu) == 0) {
        menu_destroy(menu);
        client_print(playerId, print_chat, "[Fun] No installed maps in %s.", mapCycleFile);
        return;
    }

    menu_display(playerId, menu);
}

public handleMapMenu(playerId, menu, item) {
    if (item < 0) {
        menu_destroy(menu);
        return PLUGIN_HANDLED;
    }

    new mapName[MAX_MAPNAME_LENGTH], access, callback;
    menu_item_getinfo(menu, item, access, mapName, charsmax(mapName), _, _, callback);
    menu_destroy(menu);

    amxclient_cmd(playerId, "amx_map", mapName);
    return PLUGIN_HANDLED;
}

// --- Player fun ----------------------------------------------------------------

showTargetMenu(playerId) {
    new menu = menu_create("\yPlayer fun^n\wWho?", "handleTargetMenu");
    menu_additem(menu, "Everybody", "@ALL");

    new players[MAX_PLAYERS], playerCount;
    get_players(players, playerCount, "a");

    for (new i = 0; i < playerCount; i++) {
        new targetName[MAX_NAME_LENGTH];
        get_user_name(players[i], targetName, charsmax(targetName));

        new targetInfo[TARGET_LENGTH];
        formatex(targetInfo, charsmax(targetInfo), "#%d", get_user_userid(players[i]));
        menu_additem(menu, targetName, targetInfo);
    }
    menu_display(playerId, menu);
}

public handleTargetMenu(playerId, menu, item) {
    if (item < 0) {
        menu_destroy(menu);
        return PLUGIN_HANDLED;
    }

    new access, callback;
    menu_item_getinfo(menu, item, access, gSelectedTarget[playerId], TARGET_LENGTH - 1, _, _, callback);
    menu_destroy(menu);

    showActionMenu(playerId);
    return PLUGIN_HANDLED;
}

showActionMenu(playerId) {
    new targetLabel[MAX_NAME_LENGTH];
    describeTarget(gSelectedTarget[playerId], targetLabel, charsmax(targetLabel));

    new title[96];
    formatex(title, charsmax(title), "\yPlayer fun^n\wTarget: %s", targetLabel);

    new menu = menu_create(title, "handleActionMenu");
    for (new action = 0; action < PlayerAction; action++) {
        menu_additem(menu, PLAYER_ACTION_TITLES[action]);
    }
    menu_display(playerId, menu);
}

public handleActionMenu(playerId, menu, item) {
    menu_destroy(menu);

    if (item < 0) {
        return PLUGIN_HANDLED;
    }

    new target[TARGET_LENGTH];
    copy(target, charsmax(target), gSelectedTarget[playerId]);

    switch (item) {
        case ACTION_GLOW: {
            showGlowMenu(playerId);
            return PLUGIN_HANDLED;
        }
        case ACTION_GODMODE: {
            amxclient_cmd(playerId, "amx_godmode", target, isToggleOn(target, ACTION_GODMODE) ? "1" : "0");
        }
        case ACTION_NOCLIP: {
            amxclient_cmd(playerId, "amx_noclip", target, isToggleOn(target, ACTION_NOCLIP) ? "1" : "0");
        }
        case ACTION_ROCKET: {
            amxclient_cmd(playerId, "amx_rocket", target);
        }
        case ACTION_SPEED_FAST: {
            amxclient_cmd(playerId, "amx_speed", target, "2.0");
        }
        case ACTION_SPEED_NORMAL: {
            amxclient_cmd(playerId, "amx_speed", target, "1.0");
        }
    }

    // Back to the same target, so several toys can be used in a row.
    showActionMenu(playerId);
    return PLUGIN_HANDLED;
}

showGlowMenu(playerId) {
    new menu = menu_create("\yGlow color", "handleGlowMenu");
    for (new colorIndex = 0; colorIndex < sizeof(GLOW_COLORS); colorIndex++) {
        menu_additem(menu, GLOW_COLORS[colorIndex]);
    }
    menu_display(playerId, menu);
}

public handleGlowMenu(playerId, menu, item) {
    menu_destroy(menu);

    if (item < 0 || item >= sizeof(GLOW_COLORS)) {
        return PLUGIN_HANDLED;
    }

    amxclient_cmd(playerId, "amx_glow", gSelectedTarget[playerId], GLOW_COLORS[item]);
    showActionMenu(playerId);
    return PLUGIN_HANDLED;
}

/**
 * Decides whether a godmode or noclip toggle should switch on. For a single
 * player it flips the current state, for everybody it switches on unless
 * the first living player already has it, so pressing twice turns it off.
 */
bool:isToggleOn(const target[], action) {
    new referenceId = 0;
    if (target[0] == '#') {
        referenceId = find_player_ex(FindPlayer_MatchUserId, str_to_num(target[1]));
    } else {
        new players[MAX_PLAYERS], playerCount;
        get_players(players, playerCount, "a");
        if (playerCount > 0) {
            referenceId = players[0];
        }
    }

    if (!referenceId) {
        return true;
    }

    if (action == ACTION_GODMODE) {
        return !get_user_godmode(referenceId);
    }
    return !get_user_noclip(referenceId);
}

describeTarget(const target[], label[], length) {
    if (target[0] != '#') {
        copy(label, length, "Everybody");
        return;
    }

    new targetId = find_player_ex(FindPlayer_MatchUserId, str_to_num(target[1]));
    if (!targetId) {
        copy(label, length, "(left the server)");
        return;
    }
    get_user_name(targetId, label, length);
}

findModeIndex(const modeId[]) {
    for (new modeIndex = 0; modeIndex < sizeof(MODE_IDS); modeIndex++) {
        if (equal(MODE_IDS[modeIndex], modeId)) {
            return modeIndex;
        }
    }
    return 0;
}
