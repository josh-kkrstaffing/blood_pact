# Changelog

## 0.14.0

- Roster: each member's PvP rank badge shows to the left of their name; hover the row for the rank number and title (Scout to High Warlord, or Private to Grand Marshal)
- Each player's addon reads their own rank and shares it with the guild when it changes
- The selected member's details show their PvP rank
- `/bp pvp` reads your rank now, shares it, and prints what the game reported
- The badge is the game's own icon; nothing is bundled

## 0.13.0

- About: an About button in the title bar (and `/bp about`) shows who makes Blood Pact, the Blood Pact guild on US East PvP Horde, with the Discord link ready to copy
- The first time the addon runs it says so once in chat; never again after that
- The addon list in game shows the same credit

## 0.12.0

- Loot history, built from the loot charges officers already record (who, which item, price, date); voided charges don't show
- Roster: select a member and press Loot to see everything they've received; linked alts count together
- Raid & Loot: a Loot history view, night by night, with search by player or item
- Every member can open Raid & Loot now, for the history; the award and charge controls still show only for Officers and above
- Item names, icons, quality colors and the full stats tooltip come from the game itself by item id; nothing is bundled or downloaded
- Shift-click an item in either list to link it in chat

## 0.11.0

- Roster: press Name, Rank, Lvl, Joined or Last on to sort by it; press again to flip the order (an arrow shows which way)
- Roster: "Online only" checkbox
- Linking an alt no longer cares about capitals ("binky bee" finds "Binky Bee")
- Members with no join date or no last-seen time stay at the bottom whichever way a column is sorted

## 0.10.0

- Recipes: open a profession window once and Blood Pact records the recipes you know and shares them with the guild; after that only newly learned recipes are sent
- Professions tab: click a crafter to see their recipes for that profession, with search and the game's tooltip on hover; Back returns to the list
- Each crafter row shows how many recipes they have shared
- `/bp recipes` (with a profession window open) records and shares now, and says what the game listed
- Someone else's linked profession window is never recorded as yours
- Only recipe ids are shared; names are looked up on each player's own game

## 0.9.0

- Professions is now its own tab, organized by profession: pick one on the left, see who has it on the right, best first
- Press Level to flip between highest first and lowest first
- Filters: search by player, online only, show or hide alts; members who haven't shared are left off the list
- Each profession shows the game's own icon; each crafter shows a skill bar against their current cap, a class-colored name and an online dot
- `/bp prof` reads your professions now, shares them, and prints what the game reported (use it if your own row is missing)
- A fourth way of reading professions, for clients that list them only by skill line
- The five-column grid in the Roster is gone; a member's professions still show in their Roster details

## 0.8.0

- Roster > Professions: every member's two professions with their skill levels, plus First Aid, Cooking and Fishing
- Levels are read from each player's own character by their addon and shared with the guild when they change (at most once an hour)
- Click a column to sort by it; search by player or profession name
- A member's professions also show in their details on the Members view
- Members who haven't run this version yet show "not shared yet"

## 0.7.0

- Pre-raid BiS lists for all 28 specs (every class; Feral has cat and bear lists), ranked from FrostyBoost and ForeverSpec for every spec, plus ConquestCapped where its guide could be read
- The BiS Check picks your list from your talents; you can pick another
- Readiness score: the share of your spec's list you own (bags and bank count) and the share you wear
- Raid sign-ups show each player's readiness score and sort by it, so leaders can see who is prepared; the Roster shows it too
- Your score is shared with the guild when you sign up and when your gear changes (your spec and two percentages, nothing else)
- Two-handers count for the off hand; Alliance versions of faction items are matched
- No raid BiS lists yet: Blizzard hasn't published the raid loot and no guide has raid lists
- New flat scrollbars; the Raid & Loot checkbox text no longer runs into the loot column
- About a quarter of the alternative items have no source in the guides and say so

## 0.6.0

New
- Summon tab: ask for a warlock summon; every guild warlock with the addon is alerted and sees how many guildmates are in their zone to click the portal
- Warlocks get one button that invites the asker and up to two guildmates from their zone, and another to call for clickers; nothing is sent or invited without a click
- Raid dates and times can be typed the easy way: 12/9 and 8pm, 8:30pm or 20:00
- The Raids tab shows your own answer, and past raids can't be signed up for
- Decay takes two clicks, and the Guild Master can undo the last decay; cancelling a raid takes two clicks
- A chat note when a guildmate runs a newer Blood Pact

Fixed
- The first /bp could create the window and hide it again
- Boss kills in 5-player dungeons no longer pay raid DKP or count as attendance
- A member could send a fake event that blocked an Officer's next real award
- An Officer playing on two computers could lose awards made before the second computer caught up
- History written by someone who later left the guild or changed rank was refused by new members
- Players on an older version stalled when a newer version added a feature; unknown events are now kept and passed on
- On-time and full-raid bonuses could be awarded to yourself while not in a group
- Two raid nights on back-to-back days could be merged into one; awards from Officers in different time zones could count twice
- The roster no longer logs members as "left" when the game sends a partial roster
- Names show without the realm suffix
- Test mode can no longer whisper real players or add real calendar events
- Whispers to a player who logged off no longer fill chat with "No player named..." lines

Faster
- A late login catches up in under a minute instead of up to 15
- Lists draw only the rows on screen, so a 1,000-member guild is as light as a small one
- The window redraws once per burst of changes instead of once per change, and balances are no longer recomputed on every roster update

## 0.5.0

- New look: flat dark window, 1-pixel borders, a blood-red accent and cleaner game fonts
- The window resizes from the bottom-right corner and remembers its size and position
- Tabs sit on a strip with an underline for the open tab; main actions are highlighted in red
- Long lists (Standings, BiS Check, Roster, Guild log, Officer tasks, Recruit) grow with the window

## 0.4.0

- New Roster tab: every member with rank, level, join date and last online; search by name
- Guild log: joins, leaves, kicks, promotions and demotions, with who did it when the game says so
- Rank history and alts for each member; Officers link and unlink alts by name
- Changes are recorded live from the game's guild messages, and caught up after the fact by comparing the roster; history starts the first time a Team Captain or above runs Blood Pact
- Window is a little wider to fit the new tab
- Activity per player: a main counts as active if any alt was online, or if they signed up or raided; Last on is colored Active, Watch, Inactive or Cleanup
- Inactivity days start at ForeverGuildManager's published 30/60/90 and the Guild Master can change them in Settings
- Officer tasks (Team Captain and above): review cleanup candidates, promote Initiates who meet the guild's rule (off until the Guild Master sets it), match an alt's rank to its main, check new members for alts
- Tasks sync to every officer: claim one so others see it's yours, mark it done for everyone; promotions and removals close their task on their own once the guild log sees them
- Each task copies the slash command to paste, because WoW Forever only lets officers change ranks and remove members by hand
- Officers see a chat line at login when tasks are waiting
- Schedule in Eastern, Central, Mountain, Arizona, Pacific or your PC's time; everyone sees the raid in their own PC's time, with the scheduled zone beside it
- Progression or farm checkbox per raid; boss kills that night pay the matching DKP
- New raids are added to the in-game calendar as a guild sign-up event when your rank allows it, and your Blood Pact sign-up is copied to the calendar
- Reminders on your own screen 30 and 15 minutes before raids you signed up for
- Whisper sign-ups button for Team Captains and above (one click, never automatic)
- Login message confirms the addon loaded; /bp explains if the window can't open
- Mock mode: /bp mock roster

## 0.3.0

- New Raids tab: Team Captains and above schedule raids (Barrow Deeps and Hyjal Summit presets) and cancel them
- Everyone signs up as Tank, Healer or DPS, or answers Maybe or Can't; the latest answer counts
- Attendance: taken on each boss kill while a Team Captain or above leads, or with one click
- Standings shows attendance over the last 10 raid nights; alts count for their main
- Past raids show who signed up and was there
- Mock mode: /bp mock signups and /bp mock attend

## 0.2.1

- Release pipeline fix (lint warning in the BiS module)

## 0.2.0

- New BiS Check tab (everyone): compares your equipped gear, bags and bank with Blood Pact's ranked pre-raid list
- Ranks your biggest upgrades first, shows where to get each item, and suggests a step-up item when BiS is far off
- First list: Demonology Warlock. More specs coming
- Questie is detected if installed (optional); its public API has no item lookups yet
- Item matching is by name, so the BiS check works on English clients only for now

## 0.1.3

- Release pipeline fix (lint warning in tests)

## 0.1.2

- First release through the automated pipeline (lint, tests, CurseForge upload)
- Loot buttons and award labels fit the window

## 0.1.1

- Developer support role added

## 0.1.0 (first release)

- DKP standings, raid awards (on-time, full raid, automatic boss kills), custom awards and deductions
- Fixed-price loot charging by tier, decay, undo
- Role-based permissions from guild rank; every client validates every record
- Guild-wide sync over the addon channel, with throttling and WoW Forever lockdown handling
- Recruit tab for Team Captains and above
- Solo mock mode (`/bp mock on`)
