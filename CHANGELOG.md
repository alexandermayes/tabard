# Changelog

## 1.1.3

- Promotion shoutouts read right: "MORUU IS A YIKER!! hell yeah" instead of "MORUU IS YIKER!!". The new `{a rank}` placeholder puts "a" or "an" before the rank ("a Raider", "an Officer"), and `{A RANK}` does the same in capitals.
- Eight promotion lines instead of three, among them "GZZZ MORUU!! officially an Officer <3" and "welcome to the Raider club Moruu :D". "welcome to {rank} {name}" is gone (it read like the rank was a place).
- New gold logo, easier to spot in the CurseForge app.

## 1.1.2

- Guild chat shoutouts sound like a guildie cheering now instead of a polite bot: "GZZZ AUREY 10!!", "AUREY 40!!! MOUNT TIME", "LOOK WHO'S BACK!! hi Aurey <3". The lines follow a read of real Forever guild chat: short, no full stops, capitals and stretched letters for the hype, the rest lowercase with a :D or <3. Every stock pool (milestones, other levels, promotions, welcome-backs) was rewritten.
- New placeholders `{NAME}` and `{RANK}` put the name or rank in capitals. The line editor lists them.
- The "how long it took" fact only shows up for a real stretch (five levels or more), so no more "9 to 10 in under a day". Facts go in brackets at the end: "AUREY 20!! (10 to 20 in 2 days)".
- Lines you wrote yourself are untouched; only the stock pools changed.

## 1.1.1

- Level shoutouts no longer call 30 "halfway" or 20 "a third of the way". XP per level keeps growing, so 30 is half the levels but far less than half the XP to 60 (by the classic XP table, XP halfway is around level 48). The new 30 line says exactly that: "halfway in levels, nowhere near it in xp".

## 1.1.0

- Overview: click a class in the Classes panel to see that class's level spread in the Levels panel, drawn in the class colour, with the highest-level player named ("highest 41: Turik"). Click the class again, or "all classes" beside the Levels title, to go back to the whole guild.
- Hovering a class shows how many are in the guild, their average level and the top five by level.
- Every level bar is now a button: it opens the Members list for that level range (and the picked class, if any), highest level first. The filter button shows what is applied ("Mage, 41-50"); choosing any filter from it clears that.

## 1.0.1

- Welcome whispers no longer add a sentence about the new member's class ("Rogues are handy for us..."). It read oddly to the people getting it. The stock lines now point people to guild chat for groups instead, and saved lines that still contain `{classbit}` get nothing in its place.

## 1.0.0

First public release.

- Overview launchpad with stat tiles, needs-attention list, coming up, class and level bars, sharing status.
- To-do tab: trials, leaves, bans, orphaned alts, whispered requests, promotions due, returning members.
- Log, Members, Former members, Bans, Tools (inactive, promotions, retention, recruiters), Export, Settings.
- Member card with dates, characters, officer file (leave, trial votes, strikes), notes, actions, history.
- Join line in chat with level and inviter, like Guild Roster Manager's.
- Welcome whispers and guild chat shoutouts, opt-in, with editable lines.
- Chat hints that show a main's name after an alt's name.
- Raid attendance, bench and loot tracking while in a raid group.
- Backup and restore, housekeeping of old events.
- Sharing between officers with rank trust, lockdown-aware queue.
- Backgrounds: plain grey with a faint guild emblem (default), stone, class art, something different each session, guild tabard, world map, current zone, parchment. Cropped not stretched, with a vignette. Picker in the title bar and `/tabard art next`.
- Opens at login or reload (configurable).
- "Since your last visit": a chat line at login, the lines themselves on the Overview, a divider in the Log.
- Import from Guild Roster Manager.
- Mains and alts: a member picker instead of typing, a right-click menu in the Members list, your own characters grouped automatically (and told to other Tabard users), and likely alts suggested on the To-do tab from log-off/log-on handoffs, shared name stems and notes. "(main)" or "(alt of X)" after names on event lines, and alt groups kept in step with Guild Roster Manager while it is installed.
- Login report: who joined, left, was promoted or demoted and who was removed while you were away, as chat lines after the summary.
- Your own invites are named the moment the join lands; other officers' invites come from the game's event log a few seconds later.
- Play tab: guildies online within 4 or 8 levels of you (or everyone), grouped by zone with yours first, dungeons for your level on top. Click a row to whisper, right-click for the member menu. The minimap tooltip shows the count.
- New members' first week: minutes online and whether anyone has talked to them (spoke in guild chat, was named in guild chat, grouped with you, whispered you), shared between officers. "(new)" after their name in chat, a "New this week" filter in Members, a line on the Overview, and a To-do item with a buddy suggestion when someone has been online half an hour and nobody has said hello.
- Welcome whispers go only to people who join while you are online, never after the fact.
- Minimap button through LibDBIcon (draggable, hideable, in the addon compartment), showing your guild emblem; the chat prefix shows the emblem too, falling back to the Tabard logo.
- Uses the current chat and raid-warning APIs of the Forever client, so it works without deprecation fallbacks.
