# Blood Pact

Guild DKP, standings, loot charging and recruiting for **World of Warcraft: Forever**. Free, open source, and no website or account needed.

> Blood Pact is a fan-made addon. It is not made, endorsed, sponsored or supported by Blizzard Entertainment. World of Warcraft and Blizzard Entertainment are trademarks or registered trademarks of Blizzard Entertainment, Inc.

## What it does

- **Standings.** Every guild member's DKP balance, earned and spent, kept in sync across the guild.
- **Raid awards.** One click for the on-time and full-raid bonuses. Boss kills are awarded automatically when the raid leader is an Officer or above, with a "progression night" switch for the higher amount. Custom awards and deductions for named players.
- **Loot.** Fixed-price charging by tier (best-in-slot, major, minor, off spec). The raid list is sorted by DKP so the highest balance wins ties. Balances can't go below zero.
- **Decay.** The Guild Master runs a percentage decay on every positive balance.
- **Undo.** Officers can void their own last award or charge. Nothing is ever deleted; corrections are recorded.
- **Recruit tab** (Team Captain and above). Three shared recruiting messages, a copy box, and a one-click /who scan of your zone that lists players without a guild. Click a name to open a whisper; you paste and send it yourself.

## Roster

The Roster tab lists every member with rank, level, join date and when they were last online. The guild log records joins, leaves, kicks, promotions and demotions, and who made the change when the game reports it. Each member shows their alts and rank history. Officers link and unlink alts by name. Changes are written to the same synced log as DKP, so every officer sees the same history. Tracking starts the first time a Team Captain or above runs Blood Pact; join dates from before that aren't known.

The Professions view lists each member's two professions with their skill levels, plus First Aid, Cooking and Fishing. Only a player's own client can read their skills, so each player's addon reads them and shares them with the guild when they change. Click a column to sort; search by player or profession.

Activity counts per player: a main is active if any of their alts was online, or they signed up for or attended a raid. The Officer tasks view lists cleanup candidates, Initiates who meet the guild's promotion rule, alts whose rank doesn't match their main, and new members to check for alts. Officers claim tasks and mark them done for everyone. WoW Forever doesn't let addons change ranks or remove members, so each task copies the command for an officer to run by hand.

## Summons

WoW Forever has no summoning stones, so a warlock's Ritual of Summoning is the only summon, and it needs the warlock plus two more group members to click the portal. The Summon tab lists the guild's online warlocks with how many guildmates are in each one's zone. Anyone can ask for a summon; warlocks with the addon are alerted. The warlock picks the request and presses one button to invite the asker and up to two guildmates from their zone, or calls for clickers. Every invite and message is a click by a player; the ritual itself is cast by hand.

## Raids and attendance

Team Captains and above schedule raids in the Raids tab, with presets for Barrow Deeps (10) and Hyjal Summit (20). Everyone signs up as Tank, Healer or DPS, or answers Maybe or Can't. Attendance is taken on every boss kill while a Team Captain or above leads the raid, or with one click. Standings shows each player's attendance over the last 10 raid nights, with alts counted for their main. Raids are scheduled in a US time zone or your PC's time, and everyone sees them in their own PC's time. Each raid is marked progression or farm, which sets the boss-kill DKP that night. New raids go on the in-game calendar when your rank allows it. Everyone who signs up gets reminders on their own screen 30 and 15 minutes before, and leaders can whisper the sign-ups with one click. Sign-ups and attendance sync through the guild like DKP, with no website needed.

## BiS Check and readiness

Blood Pact ships its own ranked pre-raid best-in-slot list for all 28 specs. For each spec we read public guides (FrostyBoost and ForeverSpec for every spec, ConquestCapped where available; seven and six guides for Demonology and Destruction Warlock), give each guide's top pick 2 points and each alternative 1, and rank items by points. An item's score is its points divided by the BiS item's points; ties go to ForeverSpec's order. The lists use Horde versions of faction items and match the Alliance twins too. The raw guide data and the ranking script are in `tools/bis`.

The BiS Check tab picks your list from your talents, sorts your slots by the biggest upgrade, says where to get each item, and suggests a step-up item. It reads only your own equipped items, bags and bank (open your bank once so banked items count). Your readiness score is the share of the list you own. It is shared with the guild as your spec and two percentages, and shown on raid sign-ups and the roster so leaders can see who is prepared. The score is reported by each player's own addon, so it is a guide for leaders, not proof.

There are no raid lists yet: the raid loot tables aren't published. Item matching is by name, so English clients only for now.

## Default DKP values

The defaults follow a published example setup (Raidium, "How to Build a Fair DKP System"). Your Guild Master should set your own values in the Settings tab.

| Setting | Default |
| --- | --- |
| On-time bonus | 10 |
| Full-raid bonus | 10 |
| Boss kill (farm / progression) | 5 / 15 |
| Decay | 15% |
| Prices: best-in-slot / major / minor / off spec | 100 / 60 / 30 / 10 |

## Who can do what

| Role | In-game rank | Can |
| --- | --- | --- |
| Guild Master | Rank 1 (top) | Everything below, plus settings and decay |
| Officer | Rank 2 | Award, charge, undo, link alts, edit recruiting messages |
| Team Captain | Rank 3 | Use the Recruit tab |
| Veteran, Member, Initiate | Ranks 4-6 | View standings |

Every client checks every record against the guild roster before accepting it, so editing your own copy of the addon can't grant you anything in anyone else's game. The addon's developer has a support role, listed in `Core/RBAC.lua`.

## Fair play

Blood Pact never plays the game for you. It does not automate combat, movement, targeting or spells. Every /who search, whisper and guild invite starts from your own click: WoW Forever does not allow addons or macros to send guild invites at all, so you invite through Blizzard's own right-click menu.

## Privacy

Blood Pact sends **no data outside the game**. It has no website, server or database, and it collects no IP addresses, usage statistics or personal information. Guild records (DKP, raid sign-ups, roster history, summon requests, and each player's own readiness score and profession levels) are shared only with your guildmates over World of Warcraft's addon message channel, and saved on your computer in `WTF\Account\<account>\SavedVariables\BloodPact.lua`. Delete that file to remove the addon's data.

## Commands

- `/bp` opens the window (also in the addon compartment menu).
- `/bp whoami` shows your character ID and role.
- `/bp mock on` starts a solo test mode with 19 fake guildmates. Try `/bp mock boss`, `/bp mock award` and `/bp mock forge`, then `/bp mock off`. Mock data never leaves your client.
- `/bp status` shows sync details.

## Tests

`lua tests/run.lua` checks the rules (DKP math, permissions, sync safety). `lua tests/smoke.lua` loads the whole addon into a stand-in for the game client, runs three players in one guild, syncs them over a simulated addon channel, opens every tab and presses every button. Both run on every release.

## Credits and licenses

All code is original to Blood Pact and released under the MIT License (see LICENSE). It bundles no third-party libraries, images, sounds or game files; window frames and icons are the game's own built-in UI textures, referenced by path.
