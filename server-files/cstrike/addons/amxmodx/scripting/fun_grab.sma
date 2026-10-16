// Fun Grab - admins pick up players with a glowing beam and throw them around.
//
// Bind a key with: bind g "+grab"
// Aim at a player and hold the key to lift them. While holding:
//   - fire (left mouse) throws the player away
//   - "grab_closer" / "grab_farther" change the distance, e.g.
//     bind mwheelup grab_closer; bind mwheeldown grab_farther
// Needs the admin flag "c" (kick) and works in every mode.

#include <amxmodx>
#include <amxmisc>
#include <fakemeta>
#include <fun>
#include <xs>

#pragma semicolon 1

#define PLUGIN_NAME "Fun Grab"
#define PLUGIN_VERSION "1.0"
#define PLUGIN_AUTHOR "LAN"

#define TASK_GRAB_HOLD 7200

const GRAB_ADMIN_FLAG = ADMIN_KICK;
const Float:GRAB_TICK_SECONDS = 0.05;
const Float:MIN_GRAB_DISTANCE = 90.0;
const Float:MAX_GRAB_DISTANCE = 1500.0;
const Float:GRAB_DISTANCE_STEP = 40.0;
const Float:FOLLOW_STRENGTH = 8.0;
const Float:THROW_SPEED = 1500.0;
const GLOW_THICKNESS = 25;

// Beam timings are given in tenths of a second.
const BEAM_LIFE_TENTHS = 1;
const BEAM_WIDTH = 8;
const BEAM_BRIGHTNESS = 200;

new const BEAM_SPRITE[] = "sprites/laserbeam.spr";

new gGrabbedTarget[MAX_PLAYERS + 1];
new Float:gGrabDistance[MAX_PLAYERS + 1];
new gBeamSprite;

public plugin_precache()
{
    gBeamSprite = precache_model(BEAM_SPRITE);
}

public plugin_init()
{
    register_plugin(PLUGIN_NAME, PLUGIN_VERSION, PLUGIN_AUTHOR);

    register_clcmd("+grab", "cmdGrabStart", GRAB_ADMIN_FLAG, "- grabs the player you aim at");
    register_clcmd("-grab", "cmdGrabStop");
    register_clcmd("grab_closer", "cmdGrabCloser");
    register_clcmd("grab_farther", "cmdGrabFarther");
    register_event("DeathMsg", "onDeathMessage", "a");
}

public client_disconnected(playerId)
{
    releaseGrab(playerId);
    releaseEveryGrabOn(playerId);
}

public onDeathMessage()
{
    new victimId = read_data(2);
    releaseGrab(victimId);
    releaseEveryGrabOn(victimId);
}

public cmdGrabStart(playerId, level)
{
    if (!(get_user_flags(playerId) & level) || !is_user_alive(playerId)) {
        return PLUGIN_HANDLED;
    }

    if (gGrabbedTarget[playerId] != 0) {
        return PLUGIN_HANDLED;
    }

    new targetId, bodyPart;
    get_user_aiming(playerId, targetId, bodyPart);

    if (!is_user_alive(targetId) || isAlreadyGrabbed(targetId)) {
        return PLUGIN_HANDLED;
    }

    new Float:grabberOrigin[3], Float:targetOrigin[3];
    pev(playerId, pev_origin, grabberOrigin);
    pev(targetId, pev_origin, targetOrigin);

    gGrabbedTarget[playerId] = targetId;
    gGrabDistance[playerId] = floatclamp(get_distance_f(grabberOrigin, targetOrigin), MIN_GRAB_DISTANCE, MAX_GRAB_DISTANCE);

    set_user_rendering(targetId, kRenderFxGlowShell, random_num(50, 255), random_num(50, 255), random_num(50, 255), kRenderNormal, GLOW_THICKNESS);
    set_task(GRAB_TICK_SECONDS, "holdGrabbedTarget", TASK_GRAB_HOLD + playerId, _, _, "b");

    return PLUGIN_HANDLED;
}

public cmdGrabStop(playerId)
{
    releaseGrab(playerId);
    return PLUGIN_HANDLED;
}

public cmdGrabCloser(playerId)
{
    if (gGrabbedTarget[playerId] != 0) {
        gGrabDistance[playerId] = floatmax(gGrabDistance[playerId] - GRAB_DISTANCE_STEP, MIN_GRAB_DISTANCE);
    }
    return PLUGIN_HANDLED;
}

public cmdGrabFarther(playerId)
{
    if (gGrabbedTarget[playerId] != 0) {
        gGrabDistance[playerId] = floatmin(gGrabDistance[playerId] + GRAB_DISTANCE_STEP, MAX_GRAB_DISTANCE);
    }
    return PLUGIN_HANDLED;
}

public holdGrabbedTarget(taskId)
{
    new grabberId = taskId - TASK_GRAB_HOLD;
    new targetId = gGrabbedTarget[grabberId];

    if (!is_user_alive(grabberId) || !is_user_alive(targetId)) {
        releaseGrab(grabberId);
        return;
    }

    new Float:aimDirection[3];
    getAimDirection(grabberId, aimDirection);

    if (pev(grabberId, pev_button) & IN_ATTACK) {
        throwTarget(grabberId, targetId, aimDirection);
        return;
    }

    new Float:eyePosition[3], Float:holdPosition[3];
    getEyePosition(grabberId, eyePosition);
    xs_vec_mul_scalar(aimDirection, gGrabDistance[grabberId], holdPosition);
    xs_vec_add(eyePosition, holdPosition, holdPosition);

    // Steering by velocity instead of teleporting keeps the target from
    // getting stuck inside walls.
    new Float:targetOrigin[3], Float:velocity[3];
    pev(targetId, pev_origin, targetOrigin);
    xs_vec_sub(holdPosition, targetOrigin, velocity);
    xs_vec_mul_scalar(velocity, FOLLOW_STRENGTH, velocity);
    set_pev(targetId, pev_velocity, velocity);

    drawGrabBeam(grabberId, targetId);
}

throwTarget(grabberId, targetId, const Float:aimDirection[3])
{
    new Float:velocity[3];
    xs_vec_mul_scalar(aimDirection, THROW_SPEED, velocity);
    set_pev(targetId, pev_velocity, velocity);

    releaseGrab(grabberId);
}

releaseGrab(grabberId)
{
    if (grabberId < 1 || grabberId > MaxClients) {
        return;
    }

    remove_task(TASK_GRAB_HOLD + grabberId);

    new targetId = gGrabbedTarget[grabberId];
    gGrabbedTarget[grabberId] = 0;

    if (is_user_connected(targetId)) {
        set_user_rendering(targetId);
    }
}

releaseEveryGrabOn(targetId)
{
    for (new grabberId = 1; grabberId <= MaxClients; grabberId++) {
        if (gGrabbedTarget[grabberId] == targetId) {
            releaseGrab(grabberId);
        }
    }
}

bool:isAlreadyGrabbed(targetId)
{
    for (new grabberId = 1; grabberId <= MaxClients; grabberId++) {
        if (gGrabbedTarget[grabberId] == targetId) {
            return true;
        }
    }
    return false;
}

getAimDirection(playerId, Float:direction[3])
{
    new Float:viewAngles[3];
    pev(playerId, pev_v_angle, viewAngles);
    angle_vector(viewAngles, ANGLEVECTOR_FORWARD, direction);
}

getEyePosition(playerId, Float:eyePosition[3])
{
    new Float:origin[3], Float:viewOffset[3];
    pev(playerId, pev_origin, origin);
    pev(playerId, pev_view_ofs, viewOffset);
    xs_vec_add(origin, viewOffset, eyePosition);
}

drawGrabBeam(grabberId, targetId)
{
    message_begin(MSG_BROADCAST, SVC_TEMPENTITY);
    write_byte(TE_BEAMENTS);
    write_short(grabberId);
    write_short(targetId);
    write_short(gBeamSprite);
    write_byte(0);
    write_byte(0);
    write_byte(BEAM_LIFE_TENTHS);
    write_byte(BEAM_WIDTH);
    write_byte(0);
    write_byte(random_num(50, 255));
    write_byte(random_num(50, 255));
    write_byte(random_num(50, 255));
    write_byte(BEAM_BRIGHTNESS);
    write_byte(0);
    message_end();
}
