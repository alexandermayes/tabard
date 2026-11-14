# Changelog

## 1.3.0

- This is the Never Lucky fork of alexandermayes/tabard (by Zev), installed from https://github.com/Never-Lucky-Group/tabard rather than CurseForge. Update notices and the Usage copy point there too.
- Bans and leaves save again. "Add a ban" asks for the reason, and the member card's Leave "Set" saves. Prompts chained from another prompt no longer close the new one straight away.
- The Log follows the game's guild log. Joins, invites, leaves, removals and former members from the game's log are recorded for everyone, including people who have already left. A leave or removal is recorded the moment the game prints its leave or removal line in chat, not after two roster reads, and a roster read that still lists the leaver right after that line no longer logs a false rejoin.
- Joins and leaves that happened while nobody was online get the game log's time when the log still has them, not the time of the next roster read, and the member's join date is the game's too. A removal seen that way is recorded as a removal, with who removed them.
- Duplicates from the game's log no longer pile up. The same game-log entry is no longer added again as time passes, a join is not added twice when two officers invited the same person, and a game-log join merges with the roster read's event for it.
- The Log is in time order, so "since your last visit" and the to-do "back" items see everything, not just the newest part of the list.
- Ledgers saved by earlier versions are repaired once, on the first roster read after the update: duplicates are removed (real repeats stay apart, such as a leave and a rejoin, or two promotions to different ranks), events are sorted, and joins, invites and former members the game's log knew about are filled in. Tabard backs the ledger up first, and prints one line saying what changed. If the backup fails, the repair is skipped.
- The Log shows where its history starts: "Recording since <date>, keeping <N> days" at the bottom, also on an empty Log.
- The Log's filter resets to the Settings defaults each time you open it. Settings has a new "Hidden on the Log by default" list (it starts with Leveled, or with whatever your old saved filter hid). Changes made from the Log's Filter menu last only for that visit.
- Tooltips, the newcomer "grouped with a guildie" flag and raid rosters find other players by their full name ("First Last"), which before never found other players on Forever.
- Guild notes are read-only in the member card, with an "Edit in roster" button that opens the game's guild window. The game does not let addons write notes, so the Save buttons and the "write the join date into notes" option are gone.
- The Tools page's "Remove all" and "Promote all" buttons are gone, because the game refuses them from an addon. The Macro buttons stay.
- A shared ban lifted by another officer keeps who lifted it, and a login burst no longer makes Tabard invent character switches for the alt suggestions.
- Chat announcements come back after a failed read of the game's log. Before, one error there silenced them for the rest of the session.
- The member card waits for the end of combat the first time it opens, instead of setting off the game's "blocked" popup. Tabard says so in chat and opens it when combat ends.
- The README's install steps and the update notice are for the fork.
- For contributors: tests/run.sh runs an offline test harness with a WoW API stub, and tests/repair_report.lua prints what the ledger repair would change in a saved file without writing anything.

## 1.2.11

- Pick the trial rank by name (asked for on CurseForge). Settings has two new dropdowns, "Trial rank" and "Newcomer rank", listing your guild's ranks; before, the trial rank was a "rank index" number box at the bottom of the thresholds, and the newcomer rank (the one promotions are suggested out of) could not be set at all. Both default to the newest rank, as before. The number box is gone.

## 1.2.10

- Level-ups in the chat frame are a cheer now, not a record line. A gold star, "DING!", the level in white and a short tail ("Zev (main) hit level 22! onward!"), in a pink nothing else in Tabard uses, so a ding no longer looks like the teal "is online" line above it. Milestones get their own tails (10 "talents unlocked!", 40 "MOUNT TIME!", 60 "MAX LEVEL!"), other levels draw from a small pool. The history and the Overview keep the plain "reached level 22" wording.

- The stock shoutout and ding lines no longer name dungeons or make claims about where people are in the levelling curve ("SM time", "BRD time", "halfway in levels, not in xp"). Not every guild dungeon-grinds. The 20 line is now "GZ OLAND 20!! keep it rolling", 30 is "LETS GOOO OLAND 30!! big number", 50 is "HELL YEAH OLAND 50!! so close". Lines you wrote yourself are untouched. The Play tab's dungeons-by-level list stays; that is a finder, not a claim.

## 1.2.9

- An Invite button that works on WoW Forever. Typing `/ginvite` in chat is refused by the client whenever a chat addon such as Prat is loaded, and an addon may not invite by itself. Tabard now keeps one secure "Invite Name" button, like the card's Promote button: your click on it runs `/ginvite` as your own command. It comes up in a small bar near the top of the screen (drag it where you like) when someone who is not in the guild whispers you (off with the "Offer an Invite button..." checkbox in Settings), from `/tabard invite Name`, and from "Invite to guild" in the right-click menu on a player, a party member, a friend or a chat name. A key binding, "Invite the last whisperer to the guild" under Tabard in the game's key bindings, clicks it without the mouse. The bar hides itself after a minute or on the X; in combat the name waits until combat ends. A whisper from someone on the ban list says so on the bar.

## 1.2.8

- The login-mode dropdown in Settings no longer runs past the window: its choices read "Show the login card", "Open the window", "Open it if the to-do list has items", "Stay closed".
- Remove and Ban on the member card no longer overlap after Promote and Demote became rank lists.

## 1.2.7

- Smarter alt suggestions. A handoff (one character logs off, another logs on) now counts by how quick it was (a real character switch is under 45 seconds) and is shared out when several people logged on in the same window, so "four alts of the same person in one hour" stops happening. One handoff is never enough by itself; two are, and both directions add more. Two characters ever seen online at the same time are never suggested as alts (they are two players), and each character gets at most one suggestion at a time. Names count when the first name or the surname is the same, or the first five letters match; a four-letter match only adds to other evidence. The To-do says "Likely" or "Possibly" and shows the strongest six.
- A line at login: "Tabard 1.2.7 loaded. /tabard opens the window.", or "updated to 1.2.7 (from 1.2.6): ..." the first time after the CurseForge app updates it, like other addons print.
- The "since you were last here" line prints after a /reload too, and says "nothing has changed" when nothing has; the long report still only prints at a real login.
- The login card is back to normal size (1.2.6 made it 15% bigger); it keeps the extra width and eight lines.

## 1.2.6

- The login card is bigger: wider (560 instead of 400) so the lines stop being cut short, eight lines instead of six, and the whole card drawn 15% larger than the window.

## 1.2.5

- Promote, Demote and Remove on the member card work on WoW Forever. The game refused them before ("Tabard tried to call the protected function"): on this client an addon may not change ranks or membership by itself. Now Promote and Demote are lists of ranks, nearest first, and Remove is a button; picking one puts a single "Promote Zev Zev to Raider" button in their place, and that click, being your own, goes through. Cancel or opening another member clears it. A rank two away is two steps in the one click. Never to guild leader.

## 1.2.4

- A small login card instead of the whole window. A few seconds after you log in, a card the size of a tooltip lists what changed while you were away (the same lines as the Overview, each a link), how many to-do items are open, and an "Open Tabard" button. It only shows when there is something on it, and the whole window replaces it. It is the new default for "When I log in or reload" in Settings; "Open the window" is still there if you prefer it.
- Working down a list from the member card. When the Members list is filtered to "No main or alt set" and you sort someone from their card ("Make main", "Set...", "Add alt..."), the card moves on to the next person in the list, so the whole list can be done from the card.
- "Make all mains" on the Members page when "No main or alt set" is showing: everyone listed becomes a main of their own group in one go, after a confirmation. For when the list is long and most of them really are one-character members; the real alts can still be linked from their cards afterwards.
- Your own birthday, asked once. About twenty seconds after your first login with this version, Tabard asks when your birthday is (optional; leave it empty to skip, and it never asks again). It goes on your character and is shared with the other Tabard users in the guild like a birthday set on a card, so they know when it is. Their Tabard takes it only when your rank is one they trust.

## 1.2.3

- Overview tiles: the detail after the big number ("in Big Yikes", "186 of 198") stops short of the tile icon and is cut with "..." if it has to, instead of running underneath the icon.
- Member card: the second line ("Level 21 Hunter, Yiker") is centred under the name, as the name is, instead of starting at the portrait and sitting off to the left.

## 1.2.2

- The Members table has a Nickname column, next to the name, so nicknames show outside guild chat too. Click the header to sort by it; a member's alts show the main's nickname.

## 1.2.1

- Note changes get their own lines in "Since your last visit" on the Overview and in the login report ("Check Myspeed's note is now "alt of Zev""), instead of being counted among "other changes". The chat summary at login counts them too ("3 note changes").
- "Make main" on the member card works for a character that is not in any group yet: it starts a group with them as the main, so "not sorted into main or alt" stops counting them. Before, the button was greyed out with "not in a group".
- "Add alt..." on the card's Alts row (and "Add an alt..." in the right-click menu) picks one of the person's other characters from the member list and links it as their alt. Before, the only way was to open the alt's card and answer "Who is X's main?".
- The member card's second line ("Level 21 Hunter, Yiker") no longer hides behind the portrait circle.
- The help sentence in the Bans, Play, Export and To-do toolbars no longer gets cut off with "..." when the window is at its normal size. Each now shows a short line that fits, and hovering it shows the full explanation.

## 1.2.0

- Update notice. When a guildie running a newer Tabard says hello, you get one chat line ("Tabard 1.2.1 is available (you have 1.2.0; Jane runs the new one). Update it in the CurseForge app.") and the Overview's sharing block shows it until you update. Addons cannot update themselves on this client, so the line points at the CurseForge app. Earlier versions told each other they were "1.0.0" whatever the toc said; the version now comes from the toc.
- Login lines. "Jeefy Shock (main) is online (level 48 Mage, last on 2 days ago)." in your chat frame when a guild member logs in, in the same style as the level-up lines. Never for your own characters, and not for everyone already online when you log in. Settings > "Announce in chat when someone..." > "comes online" turns it off. When the "returns after a break" line applies, it takes over.
- Nicknames (asked for on CurseForge). The member card has a Nickname field, and `/tabard nick Check Myspeed = Checky` does the same (`= ` with nothing after it clears it). The nickname shows in guild chat after the person's name and after every alt of theirs, in place of the main's name: "[Ooh Woo (Checky)]: hi". It is also on tooltips, the login line and the Members search, is kept on their main, and is shared with the other officers like notes are.
- Right-click menus. Right-clicking a guild member in the game's guild roster, on their unit frame, in the friends list or on a chat name now has a Tabard section: "Open in Tabard" opens their member card, "Nickname..." sets the nickname. The entries only show for people in the ledger.
- Usage counts, so Tabard can grow toward what people actually use. Tabard counts how often you open the window (by hand or at login), which pages, how many member cards and which slash commands, and notes which features are on. Only counts and switches, never names, notes or chat. They go with the sharing hello to other Tabard users in your guild, nowhere else (an addon cannot reach the internet). `/tabard users` lists each one's version and what they use; `/tabard usage` shows your own line in a box to copy, for the Tabard thread on Discord or a CurseForge comment. Settings > Sharing and tooltips > "Share which Tabard pages I open..." turns the sharing off.

## 1.1.4

- The in-game logo (chat prefix, minimap button, window portrait, addon list) is the new gold Tabard mark, matching CurseForge.

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
