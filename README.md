# Questmates

A World of Warcraft **WoW Forever** addon for questing with friends.

- **See what your party is doing**: a Party tracker with everyone's current quest, objectives and progress.
- **Catch up**: for any quest a friend has, see every earlier quest you need, in order, with the quest giver and
  a guided *Take me there* (map spotlight, route arrows, the game's own waypoint arrow).
- **Show a quest to your friend**: pops up on their screen with the whole chain.
- **Share where you're going**: your map pin shows up on their map.
- **Dungeons**: every dungeon's quests; pick one and the whole party is guided to every quest for it, with
  quests shared and accepted automatically.

## Install

Download **Install Questmates.bat** from the [latest release](https://github.com/Bjornaman2/questmates/releases/latest)
and double-click it. It finds WoW Forever, installs Questmates, and keeps it up to date automatically
(it checks at Windows sign-in and every 3 hours; new versions load the next time you start WoW or `/reload`).

In game: `/qm` opens the Party Quest Journal, `/qm demo` shows a preview, `/qm dungeons` the dungeon list.

To stop automatic updates: run
`powershell -ExecutionPolicy Bypass -File "%LOCALAPPDATA%\Questmates\update.ps1" -Uninstall`

## For the developer

- `Questmates/` is the addon. `tools/release.ps1` publishes a version (bump the version in `Questmates.toc` and `Core.lua` first).
- `tools/data/` regenerates `Questmates/QuestData.lua` from QuestieDB (see `qdb.py`).
- `tools/test/sim.py` runs two simulated players against the addon (`pip install --target tools/pylib lupa cbor2`).

## Credits and license

Quest data is generated from [QuestieDB](https://github.com/Questie/QuestieDB) (GPL-3.0). Questmates is
released under the GPL-3.0 as well (see `LICENSE`).
