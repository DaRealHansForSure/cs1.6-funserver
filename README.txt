CS 1.6 LAN FUN SERVER
=====================

A ready-made package for a Counter-Strike 1.6 fun server on your LAN, just
like the old days: Hook, Grab, Parachute, Quake announcements, GunGame,
Zombie and Deathmatch, switchable by vote, plus bots and fun maps.


GETTING STARTED (3 STEPS)
-------------------------

1. Unpack the folder to a permanent location, e.g. C:\Games\CS16-FunServer
   (do not run it directly from the Downloads folder).

2. Double-click 1_INSTALL.bat.
   - Downloads the official server via SteamCMD and all mods
     (about 600 MB, needs internet once).
   - At the end it asks for your player name and an admin password.
   - Tip: right-click and choose "Run as administrator" to have the
     firewall rules added automatically.

3. Double-click 2_START_SERVER.bat, pick a start mode, done.
   The window shows the address, e.g.  connect 192.168.1.50:27015
   The server shows up under "LAN" in everyone's game.

If Windows asks about the firewall on first start, click "Allow access"
for private networks (for hlds.exe and for PowerShell).

Other players only need a normal CS 1.6 (Steam). Missing maps and sounds
are downloaded quickly from the server automatically when they connect.


WHAT'S INCLUDED
---------------

Foundation (downloaded from the official sources during installation):
  - HLDS (Valve, via SteamCMD)
  - ReHLDS 3.15            more stable, faster engine
  - ReGameDLL 5.30         game logic with respawn, free-for-all, bunnyhop
  - Metamod-R 1.3          plugin loader
  - AMX Mod X 1.10         admin mod
  - YaPB 4.4               bots, fill up to 8 players and make room as
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

Also enabled: miscstats (announcements like "Headshot", "Monster Kill",
"Humiliation") and statsx (/rank, /top15).


THE FOUR MODES
--------------

Type  /mode  in chat, then everyone votes for 15 seconds.
Admins switch immediately with:  amx_funmode classic|gungame|zombie|deathmatch

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

Each mode has its own map list, so the map vote at the end of a map only
offers suitable maps.


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
"custom-maps" folder and run 3_UPDATE_MAPS.bat. Maps are assigned to the
modes by their name (zm_ = Zombie, fy_/aim_/awp_ etc. = GunGame and
Deathmatch, everything except zm_ = Classic). Knife and grenade maps
(35hp_, ka_, he_) only run in Classic.

The map list for the download is in tools\maps.csv.

Listing and changing maps:
  say nextmap / say timeleft   in chat, for everybody
  /fun -> Change map           admins, pick from the current mode
  amx_map de_rats              admins, in the console
  amx_votemapmenu              admins, let everybody vote on maps
  maps *                       in the server window, lists all installed maps
The map lists per mode are server\cstrike\mapcycle_<mode>.txt.


QUAKE SOUNDS (optional)
-----------------------

The announcements always appear as text. For the real sounds, get a Quake
sounds pack (e.g. from GameBanana) and put the .wav files into
  server\cstrike\sound\misc\
using these names:
  headshot, multikill, ultrakill, killingspree, rampage, unstoppable,
  monsterkill, godlike, humiliation, doublekill, firstblood, prepare,
  oneandonly, maytheforce  (each as .wav)
Other players download the sounds automatically when they connect.


CHANGING SETTINGS
-----------------

  Server name, password      server\cstrike\server.cfg
  Rules per mode             server\cstrike\modes\*.cfg
  Number of bots             yb_quota in the mode files
  Max players, ports         top of tools\start-server.ps1
  Hook for admins only       fun_hook_admin_only 1 in modes\base.cfg

1_INSTALL.bat can be run again at any time (repair).
Note: this copies the files from server-files again. So it is best to make
your own changes directly in server-files\cstrike.


TROUBLESHOOTING
---------------

  Server not visible on the LAN:
    Check the firewall (allow incoming UDP 27015 and TCP 27080)
    or connect directly with  connect IP:27015

  Map download fails (.rar/.7z):
    Install 7-Zip (7-zip.org) and run 3_UPDATE_MAPS.bat.

  Bots lag briefly on new maps:
    Normal. YaPB learns new maps by itself the first time and saves that.

  Logs:
    server\cstrike\addons\amxmodx\logs\
