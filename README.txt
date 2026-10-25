CS 1.6 LAN FUN SERVER
=====================

A ready-made package for a Counter-Strike 1.6 fun server on your LAN, just
like the old days: Hook, Grab, Parachute, Quake announcements, GunGame,
Zombie, Deathmatch and Deathrun, switchable by vote, plus bots and fun maps.


GETTING STARTED (3 STEPS)
-------------------------

1. Unpack the folder to a permanent location, e.g. C:\Games\CS16-FunServer
   (do not run it directly from the Downloads folder).

2. Double-click 4_SERVER_CONTROL.exe. Before the first install it opens on
   the Install screen. Press "Install or repair", which installs:
   - the official server via SteamCMD and all mods
     (about 600 MB, needs internet once),
   - bots, fun plugins and the map pack.
   It asks for your player name and an admin password for the admin menus.

3. Press Start on the Server screen. The bar at the top shows the address,
   e.g. 192.168.1.50:27015. The server shows up under "LAN" in everyone's
   game.

On the first start the window offers to add the Windows Firewall rules
(Windows asks for administrator rights once). Without them, click "Allow
access" for private networks when Windows asks about hlds.exe.

Other players only need a normal CS 1.6 (Steam). Missing maps and sounds
are downloaded quickly from the server automatically when they connect.

"Update maps" on the Install screen updates only the maps. Everything runs
inside that one program, nothing else needs to be installed. For desktop
shortcuts the exe also takes --install, --start and --update-maps.


SERVER CONTROL WINDOW
---------------------

4_SERVER_CONTROL.exe controls the server with the mouse and shows the game
live. Above every screen a bar shows map, mode, players and bots, next map,
time left, LAN address and uptime.

  Live Map   3D wireframe of the current map with every player on it in
             real time: team color, view direction, trails, hook beam,
             dead marker. "Shots" draws every bullet path for a moment in
             the shooter's team color, a hit thicker and with a small
             cross. Player list, details of the selected player
             (follow camera, slay, kick) and the kill feed with the game's
             own weapon icons.
             Camera: left drag moves, right drag orbits, wheel zooms,
             W/A/S/D move, Q/E rotate, R/F tilt, T top view, Home resets.
             "Nav mesh" shows the areas, links and hiding spots the bots
             navigate by (debug view).
  Server     Start, Stop, Restart. Settings come first (see below). Pick a
             mode and a map, then Apply: the
             server switches to exactly that mode and map at once, Discard
             goes back to what runs. "Details" (or a double-click) on a map
             opens its preview, a top-down overview and stats (spawns,
             size, objective, bot navigation, how often it was played,
             kills, best player). Console with RCON command input;
             "Follow" keeps the newest line in view, scrolling up to read
             turns it off.
             Round (runs at once): force the next fun round, restart the
             round, hook on/off for this map, a message to everybody.
             Settings (draft, saved in server\cstrike\local.cfg on Apply):
             server name, join password, max players (from the next
             start), fun rounds on/off and how often, hook speed, hook for
             admins only. TV: see below.
             Game rules, per mode (draft, saved in
             server\cstrike\local_<mode>.cfg): map time, round time,
             freeze time, buy time, start money, max rounds, C4 timer,
             gravity, friendly fire. An empty field keeps the mode's own
             value, which the field shows. A value for Classic never
             changes GunGame, and a running server gets it at once.
  Bots       zBot settings: difficulty, fill count, teams, weapons, radio
             and chat. Everything is a draft until Apply, also kicking a
             bot, adding bots and building navigation files; Discard drops
             it all. The package defaults stay in modes\base.cfg; your
             changes go into server\cstrike\local_bots.cfg, and "Reset to
             defaults" (then Apply) goes back to the package values.
  Maps       every installed map in one table: picture, the modes that
             play it, where it came from (stock, map pack, custom), its
             navigation file and size. Search and a Show filter (per mode,
             missing navigation, missing picture, not playable). Details,
             Pick (puts mode and map on the Server screen as a draft) and
             Next (next map at once). Buttons to render the missing
             pictures, queue all missing navigation files on the Bots
             screen, open the custom-maps folder and update the maps (with
             its log right there, it also works while the server runs).
             Market tab: the Counter-Strike 1.6 maps on GameBanana, search
             by name, category (Fight Yard, Surf, Zombie Mod...) and sort
             (most downloaded, liked, viewed, newest). Install downloads the
             map, puts it on the server with its picture and adds it to the
             map lists of the modes it fits; Remove takes a market map off
             again. Only files that passed GameBanana's virus scan are
             installed, and only map files (maps, textures, sounds, models,
             sprites) are copied. Market maps are listed in
             tools\market.csv, so "Update maps" restores them too.
  Stats      leaderboard of this map or the last 12 hours (kills, deaths,
             K/D, knife, HE, best weapon), the maps played tonight with
             mode and duration, and how far the current map is.
  Install    install or repair and rebuild plugins, with the log (map
             updates run on the Maps screen, their log shows in both).
  Options    server address (automatic, or a fixed network adapter), the
             ports, the Windows Firewall rules with "Add or repair rules",
             a new RCON password, the screen the window opens on, and the
             folders. A draft like the other screens; address and password
             only change while the server is stopped.

The player card on the Live Map also has the fun commands for the selected
player: glow (pick a color), rocket, godmode, noclip, and Reset to switch
glow, godmode and noclip off again. They run at once, like Slay. The same
commands are in the right-click menu of every row in the Players list.
A glowing player (amx_glow, a kill streak, the Juggernaut, a zombie) shows
the glow in the window too: a halo on the 3D map, a ring around the team
dot in the list and the color in the player card.

TV for a big screen: tick "Broadcast to a TV" on the Server screen and
Apply. That starts an HLTV proxy. On the PC at the TV or projector start
CS and type in the console
  connect <server IP>:27020
That PC watches as a spectator with the automatic camera, 10 seconds
behind the game. The TV uses one player slot and stops with the server.

The live map gets its data from the plugin fun_livemap on this PC only
(UDP 127.0.0.1:27090, never on the LAN). Showing it on a projector for
everybody works like a wallhack, that is your call.

Navigation files (maps\<map>.nav) are what the bots walk by. A missing one
is built by zBot when a bot first joins that map. "Generate" on the Bots
screen builds it right away in a hidden second server on 127.0.0.1:27016,
without changing the map of the running game. "Generate all missing" queues
every map without one; worth doing once before a LAN evening, it takes
roughly a minute per map (a big one like de_survivor about ten). A file
made for another version of the map shows as "Outdated" and is rebuilt
the same way. The hidden server runs on an invisible desktop,
so it never pops up or takes the focus from a game.

The window talks to the server over RCON with a random password stored in
%APPDATA%\CsServerControl\settings.json (and in server\cstrike\local.cfg,
so a server started outside the window accepts it too). The
status is read with the normal server query, so the game logs do not fill
up with RCON lines.

Map pictures: the installer downloads one screenshot per fun map from
GameBanana into tools\previews\ (the ModId column of tools\maps.csv),
stock maps show their radar image. For any other map put a <mapname>.jpg
or .png into tools\previews\, the installer never replaces it. "Generate
missing pictures" on the Maps screen draws the rest from above out of the
map geometry (tools\previews\auto\); your own picture always wins.

Broken maps: a map that needs a model or sprite the server does not have
would freeze the server when it loads. The installer copies such files
from the map's archive to where the map expects them; a map that still
misses one stays out of every map list (the Install log says which file)
and shows as "not playable" on the Maps screen.

The exe is built from the source in app\ with
  dotnet publish app\CsServerControl -c Release
(runs the tests first; add -p:PackRelease=true for release\CS16-FunServer.zip)
which needs the .NET 10 SDK once (winget install Microsoft.DotNet.SDK.10).


WHAT'S INCLUDED
---------------

Foundation (downloaded from the official sources during installation):
  - HLDS (Valve, via SteamCMD)
  - ReHLDS 3.15            more stable, faster engine
  - ReGameDLL 5.30         game logic with respawn, free-for-all, bunnyhop
  - Metamod-R 1.3          plugin loader
  - AMX Mod X 1.10         admin mod
  - zBot (in ReGameDLL)    bots, fill up to 8 players and make room as
                           soon as real players join

Custom fun plugins (source code included, compiled during installation):
  - fun_modes      mode switching by vote
  - fun_hook       the glowing grappling hook (random color)
  - fun_grab       admins grab players with a laser beam and throw them
  - fun_parachute  parachute with E
  - fun_admincmds  amx_rocket, amx_glow, amx_godmode, amx_noclip, amx_speed
  - fun_gungame    GunGame with 24 weapon levels
  - fun_zombie     zombie infection
  - fun_menu       the Fun menu (/fun): modes, maps and admin toys on number keys
  - fun_rounds     surprise fun rounds in Classic (knives, AWP, low gravity ...)
  - fun_deathrun   the Deathrun mode (one trapper, everybody runs)
  - fun_spawns     random spawns all over the map in GunGame and Deathmatch
  - fun_streaks    kill streak rewards: glow, +50 HP, rocket jump
  - fun_livemap    sends player positions and kills to the Server Control
                   window (UDP 127.0.0.1:27090, stays on the server PC)

Also enabled: miscstats (announcements like "Headshot", "Monster Kill",
"Humiliation") and statsx (/rank, /top15).


THE FIVE MODES
--------------

Type  /mode  in chat, then everyone votes for 15 seconds.
Admins switch immediately with /fun -> Switch mode, or in the console:
  amx_funmode classic|gungame|zombie|deathmatch|deathrun

  Classic Fun   Normal CS with Hook, Grab, Parachute and auto bunnyhop
                (hold the space bar).
  GunGame       Free-for-all. Every kill = next weapon, the knife comes
                last. A knife kill steals a level from the victim.
  Zombie        Everyone starts as a human. After 10 seconds random
                players turn into green glowing zombies (fast, lots of HP,
                knife only). One zombie hit infects. If the humans survive
                the round time, they win.
  Deathmatch    Free-for-all, instant respawn, random weapon, buy anywhere,
                Hook is on.
                GunGame and Deathmatch spawn players at random spots all
                over the map. The server learns those spots from where
                players and bots walk (addons\amxmodx\data\fun_spawns\),
                so a new map starts with the spawns of both teams and gets
                more spread out within a few minutes of play.
  Deathrun      One player sets off the traps, everybody else runs the
                course. Details below.

Each mode has its own map list, so the map vote at the end of a map only
offers suitable maps.

Fun rounds (Classic only): every third round brings a surprise rule for
that round, announced at the round start:
  knives    knives only              headshot  only headshots do damage
  awp       AWP only                 deagle    one bullet, one shot kills,
  lowgrav   low gravity                        every kill gives a bullet
  speed     everybody runs fast      hewar     endless HE grenades
  juggernaut  one player (alone as T) gets  ghost     everybody almost invisible
              1000 HP, armor and an M249,
              everybody else hunts them
Admins pick the next round with  amx_funround <name|random|off>
Change how often:  fun_rounds_every 3   (off: fun_rounds_enabled 0)

Kill streaks (every mode): 5 kills without dying give a short gold glow
and +50 HP (up to 255), every 10 kills also a rocket jump and a message
to everybody. Dying starts again at 0. Off: fun_streaks_enabled 0
Not on knife, HE, deathrun and surf maps, those have their own rules.

DEATHRUN
  How to start: pick Deathrun on the Server screen, vote for it with
  /mode, or as admin /fun -> Switch mode -> Deathrun.
  Maps: deathrun_temple, deathrun_dojo, deathrun_projetocs,
  deathrun_forest, deathrun_crash_egypt, deathrun_cxx-inc, deathrun_death
  (plus your own deathrun_ maps).
  How it plays:
    - Each round one player is the Terrorist. They stand at the trap
      buttons and press them (E) when the runners pass.
    - Everybody else runs the course as CT, knife only, no buying. Weapons
      the map hands out at the end of the course can be picked up.
    - The trapper is picked at random, humans first, never twice in a row.
    - Hook and parachute are off (they would skip the traps), auto
      bunnyhop is on.
  Bots: off in Deathrun, they do not know the traps. Back on in the other
  modes. To allow some bots, change bot_quota in
  server-files\cstrike\modes\deathrun.cfg.

SURF
  Maps: surf_ski_2, surf_water-run, surf_ninja, surf_green_delux2 (easy). They run in Classic and
  Deathmatch (with instant respawn and random weapons).
  How to surf: hold strafe (A or D) towards the slanted ramp and steer
  with the mouse, do not press W.
  Stuck on the ramp? Type  fps_max 100  in the game console. With more
  than 100 FPS the old engine's physics break on ramps. Every player has
  to set this in their own game, the server can not do it for them.
  On surf maps the server switches to surf physics (sv_airaccelerate 100),
  turns fall damage and bots off. This comes from
  server-files\cstrike\modes\maps\surf.cfg and is undone on the next map.
  The same works for any map type: modes\maps\<prefix>.cfg runs on every
  map whose name starts with <prefix>_ (e.g. kz.cfg for kz_ maps).
  And for a single map: modes\maps\<mapname>.cfg (e.g. de_rats.cfg), which
  runs after the map type file.


BOTS (zBot)
-----------

The bots are zBot, the Condition Zero bots built into ReGameDLL. The
installer turns them on (bot_enable "1" in server\cstrike\game_init.cfg)
and installs their names, skills and voice lines (BotProfile.db,
BotChatter.db, sound\radio\bot\).

Set in the Server Control window, Bots screen, for all modes:
  bot_difficulty      0 Easy, 1 Normal, 2 Hard, 3 Expert (only new bots)
  bot_quota           fill up to this many players (fill mode)
  bot_quota_mode      fill, normal (fixed count) or match (per human)
  bot_join_team       any, CT or T
  bot_auto_vacate     1 = a bot leaves when a human joins
  bot_deathmatch      1 = only fight, ignore bomb and hostages
  bot_defer_to_human  1 = humans do the mission objectives
  bot_allow_pistols, _shotguns, _sub_machine_guns, _rifles, _snipers,
  _machine_guns, _grenades, _shield   which weapons bots buy
  bot_chatter         normal, radio, minimal or off
The window keeps them in a marked block at the end of
server-files\cstrike\modes\base.cfg (and the copy in server\cstrike), so
they survive a reinstall. Without the window, edit that block by hand.
Handy console commands: bot_add, bot_add_t, bot_add_ct, bot_kick,
bot_kick "<name>", bot_kill.

Mode and map rules win over these: GunGame and Deathmatch set
bot_deathmatch 1, Deathrun and surf maps run without bots, the rats maps
(de_rats, de_rats4, cs_rats2) with 4 bots on Expert, because bots handle the
jumps onto chairs and shelves badly there. See server-files\cstrike\modes\
maps\de_rats.cfg to change that.

Navigation files:
  zBot walks along a navigation mesh per map, server\cstrike\maps\<map>.nav.
  When a bot joins a map without one, zBot analyzes the map by itself
  (a few seconds to a few minutes, the round restarts afterwards) and saves
  the file, so the next time the map loads at once.
  To rebuild it, for example after a map update, run on that map in the
  server console (or via RCON):
    bot_nav_analyze
  Deleting the .nav file has the same effect the next time bots join.


BINDING KEYS (in the CS console, key ^)
---------------------------------------

  bind f "+hook"          Hook (Classic and Deathmatch)
  bind g "+grab"          Grab (admins only), left click throws
  bind mwheelup grab_closer
  bind mwheeldown grab_farther
  bind F3 "fun_menu"      Fun menu (or type /fun in chat)
  Parachute:              hold E while falling


ADMIN
-----

Once in the game, enter this in the console (password from the
installation):

  setinfo _pw "yourpassword"

Then reconnect.

Fun menu: type  /fun  in chat (or bind a key, see above).
  1. Start mode vote   (everybody)
  2. Switch mode
  3. Change map        lists the maps of the current mode
  4. Player fun        glow, godmode, noclip, rocket, speed
  5. AMX Mod X admin menu (kick, ban, slay, map vote ...)
Non-admins only see the mode vote enabled.

Admin menu without the Fun menu:  amxmodmenu
More admins go in  server\cstrike\addons\amxmodx\configs\users.ini

Fun commands (target = name, @T, @CT or @ALL):
  amx_rocket <target>
  amx_glow <target> <color>  (red, green, blue, yellow, pink, white, off)
                             the glow stays across rounds until 'off'
  amx_godmode <target> 1
  amx_noclip <target> 1
  amx_speed <target> <factor>

Examples:
  amx_rocket Peter
  amx_glow @CT green
  amx_godmode Peter 1
  amx_noclip Peter 1
  amx_speed @ALL 2


MAPS
----

The installation downloads these fun maps from GameBanana:
  fy_iceworld, fy_pool_day, fy_snow, fy_buzzkill, aim_map, aim_headshot,
  aim_ak-colt, awp_india, awp_map, de_rats, de_rats4, cs_rats2, cs_mansion,
  de_dust2_2x2, 35hp_2, he_glass, ka_matrix, fun_allinone, cs_bikini,
  gg_mini_simpsons, zm_ice_attack3, zm_dust_world
All standard CS 1.6 maps are included as well.

Your own maps: put .bsp files or whole .zip/.rar/.7z archives into the
"custom-maps" folder and press "Update maps" on the Install screen. Maps
are assigned to the modes by their name (zm_ = Zombie, deathrun_ =
Deathrun, fy_/aim_/awp_ etc. = GunGame and Deathmatch, surf_ = Classic and
Deathmatch, everything else = Classic). Knife and grenade maps (35hp_, ka_,
he_) only run in Classic.

The map list for the download is in tools\maps.csv.

Listing and changing maps:
  say nextmap / say timeleft   in chat, for everybody
  /fun -> Change map           admins, pick from the current mode
  amx_map de_rats              admins, in the console
  amx_votemapmenu              admins, let everybody vote on maps
  maps *                       in the server window, lists all installed maps
The map lists per mode are server\cstrike\mapcycle_<mode>.txt.


QUAKE SOUNDS
------------

"Headshot!", "Double Kill", "Monster Kill", "Humiliation" (knife kill) and
the other announcements play out loud. The installer downloads two sound
packs from GameBanana and puts the files into server\cstrike\sound\misc\
(plus djeyl\grenade.wav). Other players download them automatically when
they connect.

Your own sounds win: a file that already exists there is never replaced.
To use another sound, overwrite it with a .wav of the same name (22050 Hz,
mono works best):
  headshot, multikill, ultrakill, killingspree, rampage, unstoppable,
  monsterkill, godlike, humiliation, doublekill, firstblood, prepare,
  oneandonly, maytheforce

Credits:
  "Blackshot Killstreak Quakesound!" by Apicvector (gamebanana.com)
  "Kill sounds pack (UT recreation)" by Mike Isakov (gamebanana.com),
  license CC BY-NC-ND 4.0


CHANGING SETTINGS
-----------------

  Server name, password      Server Control, Server screen, Settings
  Rules per mode             server\cstrike\modes\*.cfg
  Number of bots             Server Control, Bots screen
  Max players                Server Control, Server screen, Settings
  Hook for admins only       fun_hook_admin_only 1 in modes\base.cfg

"Install or repair" on the Install screen can be run again
at any time.
Note: this copies the files from server-files again. So it is best to make
your own changes directly in server-files\cstrike.


FAST DOWNLOAD (FASTDL)
----------------------

What it is: a tiny web server on this PC (port 27080) that hands out maps,
sounds, models and sprites to the other players. Without it, CS sends
missing files through the game connection, which is extremely slow (a
10 MB map can take minutes). With it, a player who does not have a map
downloads it in seconds when joining or on a map change.

When it runs: automatically, whenever the server runs. 4_SERVER_CONTROL.exe
starts it as a second copy of itself without a window, and it ends by
itself when the server stops. Closing the Server Control window does not
stop it. You never have to start it by hand.

What it shares: only files from server\cstrike\maps, sound, models,
sprites, gfx, overviews and the map textures (.wad). Configs, plugins and
the admin password are never served.

Good to know:
  - It needs TCP port 27080 open in the firewall; the window offers to add
    the rule on the first start.
  - To check it: while the server runs, open
    http://<this PC's IP>:27080/maps/de_rats.bsp in a browser.


TROUBLESHOOTING
---------------

  Players download maps very slowly:
    The fast download window is closed or blocked by the firewall. Restart
    the server from the Server screen and allow TCP 27080.

  Server not visible on the LAN:
    Check the firewall (allow incoming UDP 27015 and TCP 27080)
    or connect directly with  connect IP:27015

  Map download fails (.rar/.7z):
    Press "Update maps" on the Install screen again.

  Bots lag briefly on new maps:
    Normal. zBot analyzes a new map the first time and saves maps\<map>.nav.

  Logs:
    server\cstrike\addons\amxmodx\logs\
