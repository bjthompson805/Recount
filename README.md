# Recount

<!-- charset-ok: this file is read in a text editor and on the CurseForge/GitHub project page, never
     drawn by the WoW client, so it is not subject to the client's Latin-1 font limit. It has used
     typographic dashes throughout since it was written; normalising them would be churn with no
     reader who benefits. -->

A damage and healing meter for World of Warcraft. Recount records what happens in combat and shows it
as a sortable list of bars — who did the damage, who took it, who healed, who died and why — with
drill-down detail and time graphs behind every bar.

Originally by Cryect, ported through many expansions, and maintained today by Pimptasty.

## Supported game versions

Classic Era, Burning Crusade Classic, Wrath Classic, Cataclysm Classic, MoP Classic, and retail
through Midnight (12.0). One download covers them all.

## Requirements

Recount needs two other addons installed. If you install from CurseForge they come down
automatically; if you install by hand, get them first or Recount will not load.

- **Ace3** — the shared library framework. Kept external rather than bundled so you are not carrying
  five copies of it across your addons.
- **VersionCheck-1.0** — tells you in-game when a new Recount is out.

Everything else Recount needs is bundled.

## Installing

**From CurseForge** (recommended) — search for Recount in the CurseForge app and install. Ace3 and
VersionCheck-1.0 are pulled in for you.

**By hand** — unzip into your AddOns folder so you end up with:

```text
World of Warcraft/<flavor>/Interface/AddOns/Recount/
World of Warcraft/<flavor>/Interface/AddOns/Ace3/
World of Warcraft/<flavor>/Interface/AddOns/VersionCheck-1.0/
```

Then restart the client, or `/reload` if you were already logged in.

## Getting started

The window appears on its own and starts recording as soon as you enter combat. From there:

- **Click a bar** to see that player's breakdown — abilities, targets, hit types, misses, crits.
- **Shift+click a bar** for a graph of their damage or healing across the fight.
- **Ctrl+click a bar** to pop out a small live graph tracking just that player.
- **Right-click a bar** for per-player actions.
- **Right-click the title bar** to change what the meter is showing.
- **Mouse wheel on the title bar with Alt held** pages through the display modes.
- **Drag the bottom corners** to resize; drag the title bar to move.

If the window is in your way, `/recount hide` — or lock it in place with `/recount lock`.

## Display modes

Pick a mode from the title-bar dropdown, a keybinding, or the mouse wheel:

Damage Done · DPS · Friendly Fire · Damage Taken · Healing Done · Absorbs · Healing Taken ·
Overhealing Done · Deaths · DOT Uptime · HOT Uptime · Activity · Threat

The optional tracker modules add more modes to the same list -- Interrupts, Dispels, Dispelled,
CC Breakers, Ressers, **Damage Prevented**, and one per power type gained (Mana, Energy, Rage, Runic
Power, Astral Power, Maelstrom, Fury, Pain) plus **Mana Given**. Each module can be switched off in
the settings if you never use it.

- **Damage Prevented** -- how much damage a mitigation buff actually stopped. Flat and percentage
  reduction never appears in the combat log, because the server takes it off before the event is
  written, but it is still countable: the reduction is a known constant. Bars are the players whose
  buff did the preventing. The buff list starts small on purpose -- every entry needs its exact
  per-rank value confirmed first, and a buff that is not listed is simply not counted, which is the
  right way round to be wrong.
- **Mana Given** -- who *gave* the mana rather than who received it. Power gains were only ever
  recorded against the recipient, so a paladin's Judgement of Wisdom had no record of its own. Mana
  only: rage, energy and focus are self-generated, so a "given" view of them would never have a row.

Both record from v1.18.6 onward, so fights already in your saved data show blank in them.

## Looking deeper

- **Detail window** -- click any bar. Shows the abilities behind the number, who they hit, and the
  spread of hits, crits, misses and resists.
- **Pets** -- by default a pet's damage and healing is merged into its owner, so a hunter's bar is
  the hunter plus the pet. The pet's own abilities are listed in that breakdown too, named like
  `Claw (Fluffy)`, so the numbers under the bar add up to the bar. If you would rather see the pet
  as a bar of its own, untick **Merge Pets w/ Owners** in the Filters settings -- the pet has its own
  record either way, so switching applies to fights you have already recorded.
- **Graph window** — shift+click any bar for a time graph of that player's fight. Needs
  "Record Time Data" switched on in the settings. You can show running totals instead of
  per-second rates, normalise series to a common scale, or stack them.
- **Compare Graph** — the button on the title bar opens a window where you can plot several players
  and metrics against each other. Pick a player and a metric, add the series, repeat. Mix metrics
  freely (one player's damage against another's healing), and limit the plot to a single fight.
- **Death log** — in Deaths mode, clicking a player shows the events leading to each death, with a
  health graph of the incoming hits and heals over the final seconds.

## Fight history

Recount splits data by encounter automatically. The fight button on the title bar opens a list of
previous pulls, so you can go back through them or return to the overall totals for the session. How
many fights are kept is up to you in the settings, and **Keep Only Boss Segments** limits the list to
boss attempts so a run of trash pulls cannot push one out.

## Live meter windows

Small always-on windows that track one number in real time, separate from the main meter. They
remember their own size and position.

- **One player** — Ctrl+click their bar (or pick it from the bar's right-click menu) while viewing
  Damage Done, DPS, Damage Taken, Healing Done or Healing Taken.
- **The whole raid** — DPS, DTPS, HPS or HTPS, from **Settings → Realtime** or `/recount realtime`.
- **Client stats** — FPS, latency, upload and download traffic, and remaining addon-message
  bandwidth, from the same place.

## Reporting

Send the current mode to Say, Party, Instance, Raid, Guild, Officer, RealID, a whisper (by name or
straight to your current target), or any chat channel you are joined to — from the report button on
the title bar, `/recount report`, or a keybinding. You choose how many lines go out, and destinations
you cannot use right now are left out of the list, so Raid only appears when you are in one.

## Minimap button and Titan Panel

- **Minimap button** — left-click toggles the window, shift+left-click opens the settings,
  right-click opens Recount's page in the WoW addon settings. Hide it from the settings if you use
  a broker bar instead.
- **Titan Panel / broker bar** — Recount publishes a live stat (DPS, Damage Done, HPS, Healing Done,
  Damage Taken or Deaths) for you, usable by Titan Panel, Bazooka, DockingStation and any other
  LibDataBroker display. Right-click to switch the stat or the data set; hover for all six at once.

## Making it yours

Open the settings with `/recount config`, the minimap button, or the WoW addon settings page.

- **Addon Language** — run Recount's own text in any of the 14 bundled translations regardless of
  your client's language, or leave it on Auto to follow the client. Takes effect after a `/reload`.
  Item, spell and unit names always come from your client.
- **Appearance** — bar texture and font (any you have installed via LibSharedMedia), bar height and
  spacing, window scale, background and border colours, per-class bar colours.
- **What gets recorded** — filter by who (yourself, your group, pets, mobs, bosses) and by where
  (raids, dungeons, battlegrounds, the open world). Optionally hide the window entirely while it is
  not collecting.
- **Pet handling** — roll pet damage and healing into their owner's bar, or list pets separately.
- **Data hygiene** — clear automatically when you enter a new instance or join a group, with or
  without a confirmation prompt.

## Slash commands

| Command | What it does |
| --- | --- |
| `/recount` | List the available commands |
| `/recount toggle` / `show` / `hide` | Control the main window |
| `/recount config` | Open the configuration window |
| `/recount gui` | Open Recount's page in the WoW addon settings |
| `/recount reset` | Clear the current data |
| `/recount resetpos` | Bring every Recount window back to the centre of the screen |
| `/recount pause` | Pause and resume recording |
| `/recount lock` | Lock or unlock the windows in place |
| `/recount minimap` | Show or hide the minimap button |
| `/recount report` | Reporting options |
| `/recount realtime` | Open and close the live meter windows |
| `/recount profile` | Settings profile management |

## Keybindings

Under **Game Menu → Key Bindings → Recount**: jump straight to any display mode, page through modes
forwards and backwards, show/hide/toggle the window, reset data, pause recording, toggle pet
merging, and report the main or detail window to chat.

## Retail Midnight (12.0) notes

Midnight changed how addons may read combat data, and Recount reads it the new supported way. A few
things differ there:

- **Turn the in-game meter on** — Options → Gameplay Enhancements → Damage Meter. Without it there
  is no data for Recount to show.
- Damage, DPS, Healing, Damage Taken, Absorbs and Deaths all work. **Friendly Fire, Healing Taken,
  Overhealing, DOT/HOT Uptime, Activity and Threat** have no data source on Midnight and stay blank.
- There is **no Total bar and no percentages**, because the game does not permit adding those
  numbers up.
- **The bars are in the game's own ranking order**, not one Recount chose, for the same reason.
- **Clicking a bar** still opens a spell-by-spell breakdown, and it keeps up with the fight -- it
  re-reads live data as the meter updates and empties when the meter is reset, rather than holding
  the numbers from the moment you clicked. It names the mobs each spell hit and what it did to each;
  inside a raid or dungeon encounter the game hides the names needed to make that match, so the lower
  list falls back to a plain per-spell view. **Hovering a bar shows no tooltip** -- that is
  deliberate, to keep protected values out of shared frames.
- **Resetting clears the game's own damage-meter sessions too**, because on Midnight that is where
  the numbers actually live. Blizzard's own meter windows empty at the same moment; there is one
  store and no way to clear only Recount's view of it.

Every Classic flavour is unaffected by all of the above.

## If something looks wrong

- **No bars at all.** Check the meter is not paused (`/recount pause`), that the zone and group
  filters in the settings cover where you are, and — on retail Midnight — that the in-game Damage
  Meter is enabled.
- **A yellow "Recount init warning" in chat.** Something failed while starting up. Screenshot it and
  report it; the message names the step that failed.
- **Numbers look low for someone.** Recount only sees what your client's combat log sees. Players out
  of range are filled in by Recount-to-Recount sync when they also run Recount.
- **Graphs are empty.** Time data is off by default because it costs memory — switch on
  "Record Time Data" in the settings.

## Help and links

Questions, bugs and suggestions: [Discord](https://discord.com/invite/bY2R5TmBSz).

`CHANGELOG.md`, shipped alongside this file, has the full history of what changed and when.

## Credits

Created by **Cryect**. Ported to 2.4 by **Elsia**, maintained from 5.4 by **Resike**, and maintained
today by **Pimptasty**. Thanks to everyone who has contributed a translation, a bug report or a fix
over the years.

## Licence

All Rights Reserved — see `LICENSE`.
