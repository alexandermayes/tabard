# Tabard

A dated record of your guild for World of Warcraft Forever, built on the stock UI.

Tabard watches the roster while you play and keeps a ledger: who joined and when, who left or was
removed, promotions, level-ups, name changes, note changes, and more. It fills the gaps a guild officer
usually keeps in their head, and it shares that knowledge between officers automatically.

## What it does

- **Overview**: five big numbers, what changed since your last login, what happened in the last 30 days, a "needs attention" list, upcoming
  anniversaries and birthdays, class and level breakdowns (click a class to see its levels and who leads it), and sharing status. Every number is a button.
- **To-do**: trial reviews due, leaves of absence that ended, banned characters in the guild, alts whose
  main left, promotions due, members back from a break, and requests members whisper you (`!main`,
  `!bday`, `!loa`). Mark an item handled and it is handled for every officer running the addon.
- **Log**: every event with a coloured badge, searchable and filterable. Everything since your last login sits above a divider, and a leave shows when they joined and the rank they held.
- **Play**: guildies online near your level, grouped by zone with yours first, and the dungeons that fit
  your level. Click a row to whisper them. AFK, busy and app users are left out.
- **Members** and **Former members**: sortable tables with class icons, join dates, main/alt links,
  last online, raid attendance and notes. Click a row for the member card.
- **Member card**: join date, time in rank, birthday, main and alts, leave of absence, trial votes,
  strikes, all three notes, actions (promote, demote, remove, ban) and the member's full history. Right-click a
  guild member in the game's guild roster, on a unit frame or in chat and choose "Open in Tabard".
- **Mains and alts**: right-click a member to link them from a searchable list, your own characters are grouped
  automatically, and likely alts show up on the To-do tab with Link and Not alts. Event lines show "(main)" or
  "(alt of X)" after a name, and guild chat shows the main's name after an alt's name.
- **Nicknames**: give a member a nickname on their card (or `/tabard nick NAME = NICKNAME`) and it shows after
  their name, and their alts' names, in guild chat and on tooltips.
- **Login lines**: "X (main) is online (level 48 Mage, last on 2 days ago)." when a guild member logs in; off
  with one checkbox.
- **Ding lines**: a star, "DING! X (main) hit level 22! onward!" in its own pink when a guild member levels, with
  milestone tails at 10, 20, 30, 40, 50 and 60.
- **New members' first week**: how long they have been online and whether anyone has talked to them. A
  newcomer who has been online half an hour with no hello becomes a To-do item, with a guildie near their
  level suggested as a buddy. Only flags and minutes are kept, never message text.
- **Login report**: who joined, left and changed rank while you were away, as chat lines at login.
- **Bans**: a ban list with reasons that warns you when a banned character, or an alt of one, joins.
- **Tools**: inactive members to consider removing, promotions due, retention by join week and who
  recruits people who stay. One-click mass actions or a generated macro.
- **Export**: comma-separated text for members, former members, the log, bans, raid attendance and the
  last raid.
- **Settings**: chat announcements, login report, welcome whispers, guild chat shoutouts, sharing, trial and newcomer ranks, thresholds, themes,
  backups and a Guild Roster Manager import. Every option is in the window.

### Optional extras (off until you turn them on)

- **Welcome whispers**: new members get a personal whisper from you, rotating through your lines.
- **Guild chat shoutouts**: a short line when a member hits a milestone level, with one real fact from the
  ledger added.

### Sharing between officers

Officers who run Tabard exchange join dates, promotion dates, alts, bans, notes, nicknames, birthdays, votes,
strikes and handled items through addon messages. Only members at or above the rank you choose are
trusted. Nothing is announced on their behalf. The hello also carries the version, so when a guildie runs a
newer Tabard you get one chat line saying it is time to update in the CurseForge app.

After the hello comes a line of usage counts: how often the window was opened, which pages, member cards and
slash commands, and which features are on. No names, notes or chat. `/tabard users` shows what the other
Tabard users in the guild use, `/tabard usage` shows your own line (ready to copy), and one checkbox in
Settings stops sending it.

## Slash commands

`/tabard` opens the window. `/tabard scan`, `/tabard sync`, `/tabard status`, `/tabard import`,
`/tabard todo`, `/tabard raid`, `/tabard backup`, `/tabard restore`, `/tabard welcome`, `/tabard nick`,
`/tabard users` and `/tabard usage` do what they say; the window has the same controls.

## Coming from Guild Roster Manager

Settings has an Import button that reads Guild Roster Manager's saved join and promotion dates for your
guild. Dates from the game's own event log and dates you type in still take priority.

## Notes for this client

World of Warcraft Forever forbids addons from sending chat on a timer, so welcome whispers and
shoutouts go out on your next click or chat line. Tabard never sends anything you did not enable.
