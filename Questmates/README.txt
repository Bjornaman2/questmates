QUESTMATES 2 - party questing for WoW Forever

Everyone in the party needs it. Easiest: double-click "Install Questmates.bat", then start the game.
(Manual: put the Questmates folder in World of Warcraft\_forever_\Interface\AddOns\.)
Try it alone first: type  /qm demo

WHAT YOU GET

Party tracker (on screen, under your quest tracker style)
  Each party member: portrait, where they are, the quest they're on right now, its objectives and a
  progress bar, and what it means for you:
    "Questing together" / "You have it - 3/10" (+ Join button) / "You need this - 2 steps to catch up".
  Click a block: open the journal.  Right-click: waypoint to their objective area.
  Click the header to collapse, drag it to move.

Party notes (banners at the very top of the screen; move them in Esc > Options > AddOns > Questmates)
  When a party member picks up, finishes or turns in a quest, starts a different one, places a map pin,
  or shows you a quest. Click a note to open it; right-click to dismiss.

Party Quest Journal  (/qm, the book button on the tracker, or the AddOns menu)
  "Start here" page: What can we do together? - what each friend is doing right now (Join them / Take me
  there), quests to turn in together, quests to do together, quests to pick up to catch up (nearest first),
  and your quests your friends are missing. Every line has one button.
  Pick a person: their quests in plain groups ("Doing right now", "You have these too", ...).
  Right: everyone's progress, and HOW TO GET IT: the chain of earlier quests that unlock it, where each one
  starts (NPC, zone, coordinates, yards away) and which you've already done.
  Buttons: Show on Map, Waypoint, Ask to Share, Show Party, Set as Now, Share.

World map
  A small name tag beside each party member (their current quest); their class icon, softly pulsing, where
  their quest objective is; their class icon labelled "is going here" for their map pin; a ! where a quest
  they have (and you don't) starts; numbered catch-up steps (a lock = do the earlier step first); gold
  arrows for your route. A legend in the map corner explains whatever is showing. Hover for details, click
  to go there. Markers never pile up: less important ones hide until you zoom in.

Showing a quest to your friend
  Open the quest log, pick a quest, press "Show Party" (or "Show Party" in the journal).
  It pops up on their screen; clicking it shows the whole chain and where to get the first step.

Sharing where you're going
  Place a map pin (Ctrl-click on the world map). Your party gets "<you> placed a map pin" and can click to
  follow it. Their pin shows on your map too.

Tooltips
  Hovering a party member shows what they're questing on. Hovering a quest creature also shows your
  party members' counts.

TAKE ME THERE
  Opens the map on the spot: a gold marker drops in with pulsing rings, a bouncing arrow and a "Go here"
  card, and a glowing trail runs from you to it. The game's own arrow guides you in the world, a note at the
  top says where to go, and another says "You're there! Talk to <NPC>" when you arrive.
  Catch-up steps are strictly in order: only the next step you can do has a button; later steps are locked.
  If the next step is a quest already in your log, "Show me" points the game's arrow at that quest.

DUNGEONS  (/qm dungeons, or "Dungeons" in the journal)
  Every WoW Forever dungeon and raid with all of its quests, the dungeons that fit your level first.
  Press "Get ready" and the whole party gets the same dungeon goal:
  - the journal, the tracker and the Start page show the NEXT STOP: which quest giver to visit, which quests
    they give, how far away. "Take me there" guides you; after each stop a note says where to go next.
  - quests that need an earlier quest first are planned in order (the earlier one comes first).
  - stops are nearest first; when everything is picked up it takes you to the dungeon entrance.
  - quests you pick up for it are shared with your party automatically, and quests your friends share for it
    are accepted automatically (both can be switched off in the settings).
  - "Share all with party" shares every quest for it your friends still need.
  Dungeons where you've done every quest you can do move to "All done" at the bottom, crossed out.
  WoW Forever's newest dungeons (like Krol'dok Stronghold) are only partly in the quest database, so
  Questmates also LEARNS from the game and shares it with your party: quests your quest log files under a
  dungeon's name (or that the game tags Dungeon / Raid), and every dungeon someone enters, with its entrance.

WHEN A QUEST ISN'T AVAILABLE TO YOU YET
  The quest database can miss a prerequisite (WoW Forever's newest quests especially). So Questmates asks the
  game itself which quests you can pick up right now (the same data the map's "!" quest offers use) for the
  maps that matter - no NPC visit needed. A quest that isn't available is planned automatically: if you have a
  quest from the same quest giver in your log, "finish it first"; if a friend did a nearby quest you haven't,
  that one first. It also checks when you talk to a quest giver. If a quest you were sent for isn't there, you get a note,
  the guide moves on, and the quest's page shows "What probably unlocks it": that NPC's other quests around that
  level you haven't done - the ones your friends have done first. Once you get it, the real prerequisite is
  remembered and shared with your party.

HOW CATCH-UP PATHS ARE LEARNED
  Questmates includes the WoW Forever quest database (QuestieDB): quest givers, positions and prerequisites
  for every quest, so catch-up paths are known from the start.
  Questmates remembers where every quest is picked up and turned in, and when you accept a quest from the
  NPC you just turned one in to, it records that the second follows the first. Party members share what
  they know with each other, so the chains fill in as you play. Quests picked up before Questmates was
  installed have no start recorded.

COMMANDS
  /qm             Party Quest Journal
  /qm demo        a pretend party member, to try everything alone
  /qm dungeons    every dungeon's quests; get the party ready for one
  /qm options     settings (also Esc > Options > AddOns > Questmates)
  /qm movenotes   move the party notes          /qm reset   reset the tracker position
  /qm sync        resend your quest log
  /qm tracker | notes | map | share | tooltips | sound | chat | button   switch a part on/off

CREDITS
  Quest data (QuestData.lua) is generated from QuestieDB, https://github.com/Questie/QuestieDB,
  licensed GPL-3.0. Thanks to the Questie team and its data contributors.
