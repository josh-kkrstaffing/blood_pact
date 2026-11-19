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

Blood Pact sends **no data outside the game**. It has no website, server or database, and it collects no IP addresses, usage statistics or personal information. Guild DKP records are shared only with your guildmates over World of Warcraft's addon message channel, and saved on your computer in `WTF\Account\<account>\SavedVariables\BloodPact.lua`. Delete that file to remove the addon's data.

## Commands

- `/bp` opens the window (also in the addon compartment menu).
- `/bp whoami` shows your character ID and role.
- `/bp mock on` starts a solo test mode with 19 fake guildmates. Try `/bp mock boss`, `/bp mock award` and `/bp mock forge`, then `/bp mock off`. Mock data never leaves your client.
- `/bp status` shows sync details.

## Credits and licenses

All code is original to Blood Pact and released under the MIT License (see LICENSE). It bundles no third-party libraries, images, sounds or game files; window frames and icons are the game's own built-in UI textures, referenced by path.
