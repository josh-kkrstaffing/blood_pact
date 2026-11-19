# Changelog

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
