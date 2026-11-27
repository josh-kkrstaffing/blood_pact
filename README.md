# Blood Pact

Made by **Kitch**, of the **Blood Pact** guild, US East PvP Horde, on WoW Forever. Looking for a guild or want to follow the addon? Join us on Discord: https://discord.gg/hfCKk6kED

Guild management for **World of Warcraft: Forever**: DKP and loot, raid sign-ups, roster, professions and crafting orders, BiS check, warlock summons, recruiting and tickets. Free, open source, and no website or account needed.

> Blood Pact is a fan-made addon. It is not made, endorsed, sponsored or supported by Blizzard Entertainment. World of Warcraft and Blizzard Entertainment are trademarks or registered trademarks of Blizzard Entertainment, Inc.

## What it does

- **Standings.** Every guild member's DKP balance, earned and spent, kept in sync across the guild.
- **Raid awards.** One click for the on-time and full-raid bonuses. Boss kills are awarded automatically when the raid leader is an Officer or above, with a "progression night" switch for the higher amount. Custom awards and deductions for named players.
- **Loot.** Fixed-price charging by tier (best-in-slot, major, minor, off spec). The raid list is sorted by DKP so the highest balance wins ties. Balances can't go below zero.
- **Decay.** The Guild Master runs a percentage decay on every positive balance.
- **Undo.** Officers can void their own last award or charge. Nothing is ever deleted; corrections are recorded.
- **Recruit tab** (Team Captain and above). Three shared recruiting messages (Social, Raiding, Crafting) and a /who scan that lists players without a guild: your own zone, one of your faction's starting zones, or every zone for a level range up to 60. Each click is one search; a level band with too many players for one search is split into smaller ones automatically. Click a name to whisper that player the picked message, one whisper per click; right-click opens a whisper to type your own. Nothing is searched or whispered without a click. When someone replies "inv", their name is listed exactly as the game spells it; a click puts `/ginvite` and the name in a copy box, and you copy it and paste it into chat yourself, so special letters never have to be typed. (The game blocks an invite whose chat line an addon wrote.)

## Roster

Roster > Statics holds the guild's fixed 10-player raid teams, one per Team Captain: the captain adds members and sets who tanks, heals and deals damage, and everyone can see the teams. The Roster tab lists every member with rank, class, level, zone, join date and when they were last online. Its Classes view draws the guild by class as a pie chart; click a class to list only its members, and a Team Captain or above can whisper the online members of that one class with a single click. The guild log records joins, leaves, kicks, promotions and demotions, and who made the change when the game reports it. Each member shows their alts and rank history. Officers link and unlink alts by name. Changes are written to the same synced log as DKP, so every officer sees the same history. Tracking starts the first time a Team Captain or above runs Blood Pact; join dates from before that aren't known.

Crafting orders stay inside the guild. Orders > New order lists every recipe the guild has shared, by profession, so you can order without finding a crafter first; Wanted orders show in To craft for every crafter who has shared that recipe. If you have the Auctionator addon, recipes and orders show an estimated material cost from its last auction scan (Blood Pact never scans or buys anything itself). Press Order on any recipe in a crafter's list to ask that crafter, or Post as Wanted to ask any guild crafter who has shared the recipe. The crafter accepts with a promised turnaround (2, 8, 24 or 48 hours), marks it ready, and the member who asked confirms delivery; everyone sees the status. Orders travel only on the guild's addon channel, the one whisper goes to a guild member from the player's own click, and the item is handed over by the players themselves. At a mailbox, Blood Pact lists the orders you have accepted and fills in the game's Send Mail form for one of them (the member who ordered, the item as the subject, a message, and the items from your bags); you check it and press Send, and the game takes the postage. Blood Pact never sends mail on its own. Once the full amount is mailed the order reads In transit for the whole guild, and it is complete when the member who ordered confirms they have it.

PvP rank shows on the Roster as the game's own rank badge to the left of each name; hover a row for the rank's number and title. The guild roster doesn't carry PvP rank, so each player's addon reads their own and shares it when it changes. `/bp pvp` does it on demand.

Loot history comes from the loot charges officers record in Raid & Loot. Select a member in the Roster and press Loot to see what they've received (linked alts count together), or open Raid & Loot > Loot history for the guild's loot night by night, visible to every member. Item names, icons and the stats tooltip are the game's own, looked up by item id; nothing is bundled or downloaded. Only loot charged through Blood Pact with the item attached is listed.

The Professions tab lists the guild by profession: pick one on the left and see who has it on the right, with their skill level and a bar against their current cap. Only a player's own client can read their skills, so each player's addon reads them (two professions plus First Aid, Cooking and Fishing) and shares them with the guild when they change. Press Level to flip the order; filter by player name, online only, or alts. The profession icons are the game's own; none are bundled. If your own professions don't show, type `/bp prof`.

Click a crafter to see the recipes they know. The game shows a character's recipes only to that character, and only while the profession window is open, so each player opens each profession once and Blood Pact records and shares the list (recipe ids only; names come from each viewer's own game). Newly learned recipes are added the next time the window is open. `/bp recipes` does it on demand.

Activity counts per player: a main is active if any of their alts was online, or they signed up for or attended a raid. The Officer tasks view lists cleanup candidates, Initiates who meet the guild's promotion rule, alts whose rank doesn't match their main, and new members to check for alts. Officers claim tasks and mark them done for everyone. WoW Forever doesn't let addons change ranks or remove members, so each task copies the command for an officer to run by hand.

## Summons

WoW Forever has no summoning stones, so a warlock's Ritual of Summoning is the only summon, and it needs the warlock plus two more group members to click the portal. The Summon tab lists the guild's online warlocks with how many guildmates are in each one's zone. Anyone can ask for a summon; warlocks with the addon are alerted. The warlock picks the request and presses one button to invite the asker and up to two guildmates from their zone, or calls for clickers. Every invite and message is a click by a player. A warlock who is in a group they don't lead can't invite, so the same click asks the group's leader to do it, with one whisper.

Warlocks also get a summon queue. Anyone types `123` in raid, party or guild chat, or whispers it to the warlock, and their name joins a small list on the warlock's screen. Clicking a name casts Ritual of Summoning on that player through the game's own secure button (one click, one cast); right-click targets them. Only guild members and people already in the warlock's group are listed. The warlock can change the keyword, and `/bp summon` opens the list. Blood Pact reads the keyword from chat the player already sees; it sends nothing in reply.

Warlocks of Team Captain rank and above also get two summon messages, sent only while they cast their own Ritual of Summoning: a whisper to the player being summoned, and, if the portal is still short of clickers a few seconds after it appears, one line in raid or party chat naming the group members standing nearby who aren't clicking. Both texts can be edited and each has an off switch (Messages, at the top of the summon queue).

## Raids and attendance

Team Captains and above schedule raids in the Raids tab, with presets for Barrow Deeps (10) and Hyjal Summit (20). Everyone signs up as Tank, Healer or DPS, or answers Maybe or Can't. Signing up asks for a spot: a Team Captain or above selects who gets one by clicking names in the sign-up list, up to the raid's size. Attendance is taken on every boss kill while a Team Captain or above leads the raid, or with one click. Standings shows each player's attendance over the last 10 raid nights, with alts counted for their main. Raids are scheduled in a US time zone or your PC's time, and everyone sees them in their own PC's time. Each raid is marked progression or farm, which sets the boss-kill DKP that night. New raids go on the in-game calendar when your rank allows it. Everyone who signs up gets reminders on their own screen 30 and 15 minutes before, and leaders can whisper the sign-ups with one click. Sign-ups and attendance sync through the guild like DKP, with no website needed.

## BiS Check and readiness

**Raid Caller.** The Call-outs tab holds a plan of call-outs for each boss, built by Team Captains and above from a list of common calls or their own words. Timed call-outs are spoken by each player's own text-to-speech voice, counted from the pull. WoW Forever hides boss health, stacks and casts from addons and blocks addon messages inside instances, so health, stack and phase call-outs are an on-screen checklist that a click reads aloud, and plans have to sync before the raid zones in. Each player can switch the voice and the overlay off.

**Buy materials.** The Mats button on a recipe opens a window that works out the materials for 1 to 20 crafts, less what is already in your bags and bank. At the auction house each material takes two clicks: Get price, then Buy at the total the auction house quoted. Blood Pact never buys more than one material per click and never buys on its own. The "How does this work?" button in the window lists the steps.

**Upgrades for sale.** On the BiS Check tab, "Find upgrades for sale" scans the auction house for the items on your spec's pre-raid list that rank above what you own. It works for every class and spec. You set a gold range per item, and the window lists what is for sale with the cheapest buyout for each. One Buy click buys one item at the price on the button; Blood Pact never bids and never buys on its own. Two boxes choose what is scanned, "BiS list" and "Usable gear". Usable gear covers what isn't on the list and needs the Pawn addon: Pawn's stat weights decide what is an upgrade. Column headings sort the list, and clicking a row shows the item in the auction window.

**Raid Kit.** The Raid Kit tab lists the consumables each role is expected to bring and counts your bags and bank against it. A flask, elixirs, food and a weapon buff are counted to last the raid; potions and runes use the number your Team Captains set, doubled on progression nights. Anything a guildmate can craft can be ordered onto the Wanted board from the same row. Your kit count shows on raid sign-ups to Team Captains and above. At a ready check each player's addon reports its own flask, food, weapon buff and elixirs for the raid leader, and an Officer can charge DKP for a missing flask or food. Team Captains and above edit the rules and the lists. The game hides buffs in combat and gives addons no combat log, so nothing records each potion used.

Blood Pact ships a pre-raid best-in-slot list for all 28 specs. For 24 specs the list is taken from that spec's WoW Forever class guide on Wowhead, written by a named guide author; the BiS Check tab shows the author and the date their guide was last updated. A guide's BiS picks score 100%, Great 75%, Good 50% and Option 25%, relative to the best pick in the slot (that scale is Blood Pact's own; the guides give labels, not numbers). Fury Warrior, Retribution Paladin, Assassination Rogue and Discipline Priest had no readable guide list on November 23, 2026, so they keep the earlier auto-ranked list and the tab says so. The lists use Horde names for faction items and match the Alliance names too, and where a guide accepts more than one random suffix ("of Magic" or "of Shadow Wrath") either one counts. The rows copied from the guides and the build script are in `tools/bis`.

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
| Team Captain | Rank 3 | Use the Recruit tab, schedule raids and select sign-ups, read and work tickets |
| Veteran, Member, Initiate | Ranks 4-6 | View standings, sign up for raids, send tickets and see their own |

Every client checks every record against the guild roster before accepting it, so editing your own copy of the addon can't grant you anything in anyone else's game. The addon's developer has a support role, listed in `Core/RBAC.lua`.

## Fair play

Blood Pact never plays the game for you. It does not automate combat, movement, targeting or spells. Every /who search, whisper and guild invite starts from your own click (the one exception is the summon messages, below, which follow a warlock's own Ritual of Summoning cast and can be switched off): WoW Forever does not allow addons or macros to send guild invites at all, so you invite through Blizzard's own right-click menu.

## Tickets

Any member can report a problem with a player from the Tickets tab: what kind of problem, who it is about, and what happened. Team Captains and above work the reports from a queue: take it, add notes, resolve it with an outcome. The reporter sees the status of their own tickets, never the staff notes.

Tickets are not part of the guild's shared log. They are sent by addon whisper only to Team Captains and above, who keep each other's copies in step the same way, so no other member's game holds a copy. A ticket about a Team Captain or above is never sent to that person. Tickets stay in the saved data of the staff members' own game clients and go nowhere else. They are the guild's own follow-up and don't replace reporting a player to Blizzard.

## Privacy

Blood Pact sends **no data outside the game**. It has no website, server or database, and it collects no IP addresses, usage statistics or personal information. Guild records (DKP, raid sign-ups, roster history, summon requests, and each player's own readiness score, profession levels, known recipes and PvP rank) are shared only with your guildmates over World of Warcraft's addon message channel, and saved on your computer in `WTF\Account\<account>\SavedVariables\BloodPact.lua`. Delete that file to remove the addon's data.

## Commands

- `/bp` opens the window (also in the addon compartment menu).
- `/bp whoami` shows your character ID and role.
- `/bp mock on` starts a solo test mode with 19 fake guildmates. Try `/bp mock boss`, `/bp mock award` and `/bp mock forge`, then `/bp mock off`. Mock data never leaves your client.
- `/bp status` shows sync details.

## Tests

`lua tests/run.lua` checks the rules (DKP math, permissions, sync safety). `lua tests/smoke.lua` loads the whole addon into a stand-in for the game client, runs three players in one guild, syncs them over a simulated addon channel, opens every tab and presses every button. Both run on every release.

## Credits and licenses

Made by Kitch. All code is original to Blood Pact and released under the MIT License (see LICENSE). It bundles no third-party libraries, images, sounds or game files; window frames and icons are the game's own built-in UI textures, referenced by path.
