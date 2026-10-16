CS 1.6 LAN FUN SERVER
=====================

A ready-made package for a Counter-Strike 1.6 fun server on your LAN, just
like the old days: Hook, Grab, Parachute, Quake announcements, GunGame,
Zombie, Deathmatch and Deathrun, switchable by vote, plus bots and fun maps.


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

Instead of step 3 you can also use the window: 4_SERVER_CONTROL.exe
(see SERVER CONTROL WINDOW below).


SERVER CONTROL WINDOW
---------------------

4_SERVER_CONTROL.exe controls the whole server with the mouse:
  Server     pick the mode and first map, start and stop, LAN address
  Maps       every installed map with a picture, filter by mode,
             Play = change map now, First map = start the server on it
  Players    who is on, bots +1 / -1 / off, glow, rocket, godmode,
             noclip, slay, kick
  Fun        force the next fun round, switch mode, restart round,
             hook on/off, chat message to everybody
  Settings   server name, join password, max players, fun rounds,
             hook speed (saved in server\cstrike\local.cfg)
  Console    any server command at the bottom, with the answer

It talks to the server over RCON with a random password that lives only
in server\cstrike\local.cfg. A server started with 2_START_SERVER.bat
works with the window too.

The exe is built from the source in gui\ with
  powershell -ExecutionPolicy Bypass -File tools\build-gui.ps1
which needs the .NET 10 SDK once (winget install Microsoft.DotNet.SDK.10).


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
  - fun_rounds     surprise fun rounds in Classic (knives, AWP, low gravity ...)
  - fun_deathrun   the Deathrun mode (one trapper, everybody runs)

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
                                     ghost     everybody almost invisible
Admins pick the next round with  amx_funround <name|random|off>
Change how often:  fun_rounds_every 3   (off: fun_rounds_enabled 0)
Not on knife, HE, deathrun and surf maps, those have their own rules.

DEATHRUN
  How to start: pick 5) Deathrun in 2_START_SERVER.bat, vote for it with
  /mode, or as admin /fun -> Switch mode -> Deathrun.
  Maps: deathrun_temple, deathrun_dojo, deathrun_projetocs,
  deathrun_forest, deathrun_crash_egypt (plus your own deathrun_ maps).
  How it plays:
    - Each round one player is the Terrorist. They stand at the trap
      buttons and press them (E) when the runners pass.
    - Everybody else runs the course as CT, knife only, no buying. Weapons
      the map hands out at the end of the course can be picked up.
    - The trapper is picked at random, humans first, never twice in a row.
    - Hook and parachute are off (they would skip the traps), auto
      bunnyhop is on.
  Bots: off in Deathrun, they do not know the traps. Back on in the other
  modes. To allow some bots, change yb_quota in
  server-files\cstrike\modes\deathrun.cfg.

SURF
  Maps: surf_ski_2, surf_water-run, surf_ninja. They run in Classic and
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
modes by their name (zm_ = Zombie, deathrun_ = Deathrun, fy_/aim_/awp_
etc. = GunGame and Deathmatch, surf_ = Classic and Deathmatch, everything
else = Classic). Knife and grenade maps (35hp_, ka_, he_) only run in
Classic.

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
they connect. Needs 7-Zip (7-zip.org) to unpack the .rar packs.

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

  Server name, password      server\cstrike\server.cfg
  Rules per mode             server\cstrike\modes\*.cfg
  Number of bots             yb_quota in the mode files
  Max players, ports         top of tools\start-server.ps1
  Hook for admins only       fun_hook_admin_only 1 in modes\base.cfg

1_INSTALL.bat can be run again at any time (repair).
Note: this copies the files from server-files again. So it is best to make
your own changes directly in server-files\cstrike.


FAST DOWNLOAD (FASTDL)
----------------------

What it is: a tiny web server on this PC (port 27080) that hands out maps,
sounds, models and sprites to the other players. Without it, CS sends
missing files through the game connection, which is extremely slow (a
10 MB map can take minutes). With it, a player who does not have a map
downloads it in seconds when joining or on a map change.

When it runs: automatically. 2_START_SERVER.bat starts it in a minimized
window titled "CS 1.6 Fast Download" and stops it again when the server
stops. You never have to start it by hand. Leave that window open, closing
it does not stop the game, but new players fall back to the slow download.

What it shares: only files from server\cstrike\maps, sound, models,
sprites, gfx, overviews and the map textures (.wad). Configs, plugins and
the admin password are never served.

Good to know:
  - Windows asks once to allow it in the firewall, click "Allow access"
    (TCP port 27080, 1_INSTALL.bat adds the rule when run as admin).
  - The minimized window logs every downloaded file, handy to see that it
    works.
  - Run it by hand only for testing:
      powershell -ExecutionPolicy Bypass -File tools\fastdl-server.ps1 -Root server\cstrike
    then open http://<this PC's IP>:27080/maps/de_rats.bsp in a browser.


TROUBLESHOOTING
---------------

  Players download maps very slowly:
    The fast download window is closed or blocked by the firewall. Restart
    the server with 2_START_SERVER.bat and allow TCP 27080.

  Server not visible on the LAN:
    Check the firewall (allow incoming UDP 27015 and TCP 27080)
    or connect directly with  connect IP:27015

  Map download fails (.rar/.7z):
    Install 7-Zip (7-zip.org) and run 3_UPDATE_MAPS.bat.

  Bots lag briefly on new maps:
    Normal. YaPB learns new maps by itself the first time and saves that.

  Logs:
    server\cstrike\addons\amxmodx\logs\
