// Shared helpers for the LAN fun server plugins.
//
// The active game mode is kept in the server's localinfo buffer instead of a
// cvar, because localinfo survives a map change while every plugin is
// reloaded. fun_modes.amxx writes it, all other fun plugins only read it.

#if defined _fun_common_included
    #endinput
#endif
#define _fun_common_included

#define FUN_MODE_KEY "fun_mode"
#define FUN_MODE_LENGTH 16

stock const FUN_MODE_CLASSIC[] = "classic";
stock const FUN_MODE_GUNGAME[] = "gungame";
stock const FUN_MODE_ZOMBIE[] = "zombie";
stock const FUN_MODE_DEATHMATCH[] = "deathmatch";

/**
 * Copies the active game mode into the buffer, falling back to classic.
 */
stock get_fun_mode(mode[], length)
{
    get_localinfo(FUN_MODE_KEY, mode, length);

    if (mode[0] == EOS) {
        copy(mode, length, FUN_MODE_CLASSIC);
    }
}

/**
 * Returns true when the given mode is the one currently running.
 */
stock bool:is_fun_mode(const wantedMode[])
{
    new activeMode[FUN_MODE_LENGTH];
    get_fun_mode(activeMode, charsmax(activeMode));

    return bool:equal(activeMode, wantedMode);
}
