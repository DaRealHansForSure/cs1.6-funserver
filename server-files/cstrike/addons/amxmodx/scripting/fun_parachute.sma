// Fun Parachute - hold the use key (E) while falling to float down slowly.
//
// No model and no extra download: it simply caps the falling speed while the
// key is held. Works in every mode, turn it off with fun_parachute_enabled 0.

#include <amxmodx>
#include <fakemeta>

#pragma semicolon 1

#define PLUGIN_NAME "Fun Parachute"
#define PLUGIN_VERSION "1.0"
#define PLUGIN_AUTHOR "LAN"

const Float:MAX_FALL_SPEED = 100.0;

new gEnabledCvar;

public plugin_init()
{
    register_plugin(PLUGIN_NAME, PLUGIN_VERSION, PLUGIN_AUTHOR);

    gEnabledCvar = create_cvar("fun_parachute_enabled", "1", _, "Parachute on (1) or off (0)", true, 0.0, true, 1.0);
    register_forward(FM_PlayerPreThink, "onPlayerPreThink");
}

public onPlayerPreThink(playerId)
{
    if (!get_pcvar_num(gEnabledCvar) || !is_user_alive(playerId)) {
        return FMRES_IGNORED;
    }

    if (!(pev(playerId, pev_button) & IN_USE)) {
        return FMRES_IGNORED;
    }

    new Float:velocity[3];
    pev(playerId, pev_velocity, velocity);

    // Velocity is negative while falling, so "too fast" means below -MAX.
    if (velocity[2] < -MAX_FALL_SPEED) {
        velocity[2] = -MAX_FALL_SPEED;
        set_pev(playerId, pev_velocity, velocity);
    }

    return FMRES_IGNORED;
}
