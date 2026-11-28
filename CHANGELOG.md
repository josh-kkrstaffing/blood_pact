# Changelog

## 2.0.0

- The addon has a new name: Blind Tiger. It was called Blood Pact, which is still the name of the guild that makes it
- Your data carries over. The update installs two folders: BlindTiger, and a small "Blood Pact data carry-over" helper that hands your saved DKP, raids, settings and chips to Blind Tiger the first time you log in. After that the helper does nothing and can be switched off
- The command is now /tiger (or /blindtiger)
- New branding from the guild's own artwork: the gold one-eyed tiger. Its face marks the title bar, every pop-up window and the addon list; the full emblem is on the About page and sits faintly behind the games floor
- Guildmates still on Blood Pact 1.x keep syncing with Blind Tiger
- Blind Tiger is for guilds only, and now says so in About: it works inside one guild, shares only with its members, and its games use play chips among guildmates

- New: the games floor. Open it with "Play games" in the Chips window. You play your chips against the house, and the house is the guild
- Four games, each against the house:
- Roulette: the American wheel with 0 and 00. Bet a number, red or black, odd or even, high or low, a dozen or a column. House edge 5.26%
- Slots: three reels, six symbols, a 100-times jackpot for three Tigers. House edge 7.34%
- Blackjack: pays 6 to 5, the dealer hits a soft 17, and you can double (also after a split) and split a pair once. House edge 2.14% against perfect play
- Hold'em against the house: ante, see your cards and the flop, then call for twice the ante or fold. The dealer needs a pair of fours to qualify. House edge 2.16%
- The roulette and slots edges are counted over every possible result by the addon's own tests, and the blackjack edge was calculated exactly. The Hold'em figure is the published one for these rules. Nothing is rigged per hand
- Plays are added up and written to the guild's log a session at a time. Big wins show on every guildmate's floor
- Chips still never turn back into gold

## 1.13.0

- New: guild chips. At the guild bank, "Donate for chips" deposits your gold into the guild bank and gives you play chips one for one: 1 gold is 1 gold chip, 1 silver is 1 silver chip, 1 copper is 1 copper chip
- Chips start as pending and become real when an Officer's addon sees your deposit in the bank's money log. That happens by itself whenever an Officer opens the guild bank. Nobody can confirm their own chips
- Chips are one-way: they can't be turned back into gold. They are for the guild's games and the leaderboard
- Open it from the Chips button in the Party window. It shows your chips, what is pending, and the guild leaderboard
- Only donations made with the button earn chips; gold put in the bank the ordinary way is a plain donation

## 1.12.1

- Party: fixed the leader hearing each line spoken twice
- Party: the word of the night now works on its own. After a leader announces the word, anyone typing it in raid or party chat sets off the next line as a raid warning, with who said it ("Whyley said Wind. Take a shot!")
- It matches the whole word in any capitals, so "wind" does not trigger on "window"
- The ten-second cooldown still applies. Clear the word box and press Announce to stop listening
- It listens on the screen of the leader who announced the word, and cannot hear voice chat or read chat inside a raid instance

## 1.12.0

- New: Drink of the Night. A Team Captain or above gives a raid a drink, and it shows on the raid's header in the Raids tab with a Recipe button, so raiders see it when they sign up
- The menu leans on Nashville, Tennessee: the Bushwacker, a Smoked Maple Old Fashioned, Cade's Cove, Just to Satisfy You, Summer's End, the Tennessee Mule and Lynchburg Lemonade, plus two zero-proof drinks
- Leaders can type a drink of the guild's own, with its recipe
- Party window: "Announce the drink" sends tonight's drink to the raid
- Party sound board: added "Holler and swaller!", Nashville's toast

## 1.11.1

- Party button: works in a five-player party too. The party leader presses it, the line goes to party chat, and party members with the addon get the big on-screen text and the voice

## 1.11.0

- New Party button in the title bar, on every tab. The raid leader or an assist presses it and the raid gets a raid warning such as "Take a drink!", the same as /rw, so everyone sees it with or without the addon
- Raiders with Blood Pact also hear the line spoken. "Play party sounds" turns that off for you
- A sound board of lines: Next plays them in order, Random picks one, or click a line. Team Captains and above can add lines and switch them off, and the list syncs to the guild
- Word of the night: type the word and announce it to the raid
- A ten-second cooldown, and only the raid leader and assists can press it
- Inside a raid instance the game blocks addon chat, so the button puts the /rw line in your chat box for you to send

## 1.10.0

- Upgrades for sale: the "Usable gear" scan now runs on the Pawn addon. Pawn compares each item's real stats with what you are wearing, using its stat weights for your spec, and only what Pawn calls an upgrade is listed, with Pawn's percentage
- This replaces the item-level rule from 1.9.0, which listed gear that was not an upgrade: off-hand items while holding a two-hander, and greens with the wrong stats
- Without Pawn the usable scan says it needs Pawn and lists nothing. The BiS list scan works without it
- Usable gear is read cheapest first, so a most-gold limit makes the scan much faster
- Up to 40 upgrades are priced per scan, biggest first

## 1.9.1

- Upgrades for sale: two boxes now choose what is scanned, "BiS list" and "Usable gear". Tick one or both
- Usable gear alone skips the list lookups, so it is the quicker scan

## 1.9.0

- Upgrades for sale: new "Usable gear too" box. Ticked, the scan also looks through greens and other gear you can equip that isn't on your BiS list
- Two tiers: Ideal is your BiS list. Affordable is any green with an ending your class and spec wants: "of Shadow Wrath" for an Affliction Warlock or Shadow Priest, "of Healing" for healers, "of the Tiger" for Fury, and so on for all 28 specs. Greens with another ending are left out
- An affordable green is listed when it is a higher item level than what you wear, or when what you wear in that slot is neither on your list nor has one of those endings
- Gear with no such ending is judged by the Pawn addon's stat weights if Pawn is installed, otherwise by item level in your class's armor type. Item level ignores stats, so check the tooltip first
- Every column heading sorts the list: Slot, Item, List score, You have, Upgrade and Cost. Click again to reverse
- Click a row to show that item in the game's auction window
- New Upgrade column says why a row is listed: Ideal with its step up on the list, the wanted ending, Pawn's percentage, or the item levels

## 1.8.0

- BiS Check: new "Find upgrades for sale" button opens an auction house scan for your spec. It works for every class and spec, from the same pre-raid lists as the BiS Check tab
- It looks up every item on your list that ranks above what you own, and shows the ones for sale with the cheapest buyout for each, biggest upgrade first
- Set the least and the most gold you will pay for one item. Changing the range re-filters the results without a new scan
- One Buy click buys one item at the price on the button. The game needs your own click for every purchase, so nothing is bought for you, and Blood Pact never bids
- Random-enchantment items ("of Shadow Wrath", "of Magic") are matched by their full name, so another enchantment of the same item is not offered
- Quest rewards and Tier 0.5 pieces are skipped because they can't be sold
- "How does this work?" in the window explains the steps

## 1.7.0

- New tab, Call-outs: a Raid Caller that speaks boss call-outs with your computer's own text-to-speech voice
- Team Captains and above build a plan per boss: when (seconds after the pull, boss health %, stacks, phase, or on the leader's call), what (a list of common call-outs by type, or your own words), who it is for, and a marker colour
- Timed call-outs are spoken by themselves on every raider's own addon, counted from the pull
- Health, stack and phase call-outs go on an on-screen checklist, because the game hides those numbers from addons. Click the overlay to hear the next one
- Call-outs for tanks or healers are only spoken to them
- Two boxes turn the voice and the overlay on or off. "Test voice" and "Hear it" let you check the sound; "How does this work?" explains it
- Plans sync with the guild records before you enter the raid. Inside a raid the game doesn't let addons talk to each other

## 1.6.0

- Professions: new Mats button on each recipe opens a "Buy materials" window
- Type how many you want to craft, 1 to 20. The window lists each material: needed, in your bags and bank, and still to buy, with an estimated total from Auctionator's last scan
- At the auction house each material is bought with two clicks: Get price asks what that quantity costs at the lowest prices right now, then the button shows that total and a second click pays it
- One material at a time. The game needs your own click for every purchase, so nothing is bought for you
- What you just bought counts as held while it is in your mailbox, so it is not bought twice
- "How does this work?" in the window explains the steps
- Away from the auction house the window is a shopping list

## 1.5.1

- Raids: Onyxia's Lair (40) is now a preset next to Barrow Deeps (10) and Hyjal Summit (20)
- Raids screen laid out in the order you use it: pick a raid, your answer, then the roster, each under its own heading
- Both lists have column headings (When, Raid, Spots; Name, Answer, Pre-raid BiS, Kit, Attended)
- Leader tools are split into "New raid" and "Selected raid", and the second names the raid it acts on

## 1.5.0

- New tab, Raid Kit: the consumables each raider is expected to bring, by role, built from the guild leader's rules
- My kit: counts your bags and bank against the list and shows what you are short. A flask, elixirs, food and a weapon buff are counted to last the raid (3 hours unless changed)
- Short of something a guildmate can craft? The Order button puts it on the Wanted board with the cost to craft beside it
- Sign-ups show each raider's kit count to Team Captains and above, next to the BiS score
- At a ready check each addon tells its own player what is missing and reports their flask, food, weapon buff and elixirs. The raid leader sees the list; it is not posted in raid chat. Reports are shown for 90 days
- Officers and above can press "Charge 30 DKP" on a player with no flask or food. It lands once per player per night
- Team Captains and above can change the raid hours, the DKP charge, the list for each role, how many potions and runes to carry, and extra items for one raid (fire protection for Onyxia, for example)
- Progression nights double the potions and runes to carry
- The game hides buffs in combat and gives addons no combat log, so a ready check in combat reports nothing and no potion use is logged

## 1.4.3

- Professions: new Vendor column on the recipe lists, showing what a vendor pays for the finished item. It sorts like the other columns
- Vendor is blank when the recipe makes no item or vendors won't buy it. It can take a moment to fill in the first time the game loads an item
- The window is a little wider at its smallest on the Professions tab so the five columns fit

## 1.4.2

- Professions: new Net Profit column on the recipe lists. It is Buy It Now minus Cost to Craft, green when you would make money and red when you would lose it
- Net Profit stays blank when the item has no auction price or a material has no price (a cost marked "+"), because the number would be wrong. The auction house's cut is not taken off
- The recipe name column now has a "Craft" header, and all four headers sort: click once to sort, click again to flip the order. Recipes with no number for that column go to the bottom

## 1.4.1

- Professions: recipe lists now show two price columns with headers, "Cost to Craft" and "Buy It Now"
- Buy It Now is Auctionator's last scanned auction price for the finished item, next to the material cost that was already there
- A recipe that makes no item (an enchant put straight on gear), or an item nobody has listed, leaves Buy It Now blank

## 1.4.0

- BiS Check: the pre-raid lists for 24 specs are rebuilt from the WoW Forever class guides on Wowhead, each written by a named guide author. The old lists came from sites that rank items automatically
- The tab now says whose guide the list is from and when that guide was last updated
- Example: Affliction Warlock now leads with shadow damage pieces (Dark Advisor's Pendant, Felcloth Gloves, "of Shadow Wrath" world drops) instead of Intellect pieces
- Scores follow the guide's own labels: BiS 100%, Great 75%, Good 50%, Option 25%
- World drops with a random suffix count under any suffix the guide accepts, for example "of Magic" or "of Shadow Wrath" for Demonology
- Fury Warrior, Retribution Paladin, Assassination Rogue and Discipline Priest keep their earlier lists for now, marked "older auto-ranked list", because no guide list could be read for them yet
- Your readiness score will change, because the lists changed

## 1.3.0

- Professions: advertise your crafting in Trade chat. Open your own recipe list, press Link on up to four recipes, and "Post in Trade chat" sends a line such as "[Enchanting] 225/300 LFW in Undercity. Tips appreciated." with those recipes as clickable links
- The city is filled in from where you are standing, and you can change the words after it
- One post per click and no more than one a minute; Blood Pact never repeats it by itself. It needs the Trade channel, so it works in a city
- Recipe links are long, so four of them go out as two chat lines

## 1.2.0

- Roster > Statics: the guild's fixed 10-player raid teams, one for each Team Captain. Everyone in the guild can see them
- Each team shows its captain, how full it is, its tanks, healers and DPS, who is online, and where each member is
- A Team Captain builds their own team: type a name, pick a role, press "Add to team". Click a member to change their role, right-click to take them off. Officers and above can edit any team
- A team is the captain and up to nine more, and a member can be on one team at a time
- A captain can name their team, and "Invite online members" invites the team to your group in one click

## 1.1.0

- Recruit: search every zone for unguilded players in a level range, from 1 up to 60. Type the two levels next to "All zones" and press "Scan these levels"
- It works through the range one search per click, five levels at a time. The button shows what the next click searches and how many searches are left
- The game lists about 50 players per search, guilded ones included. When a list is cut short, that band is split in half, down to a single level, and a single level that is still too busy is searched class by class. Bands that came back whole are not searched again
- Results build up in one list, highest level first, each name once, and the line above says when the range is finished

## 1.0.7

- Roster: pick a member and press the invite button at the bottom to invite them to your party or raid. The button says what the click will do
- If your party is full and you lead it, it becomes a raid first and then the invite goes out
- In a group you don't lead, the button reads "Ask leader to invite" and sends the leader one whisper
- Offline members and yourself can't be invited

## 1.0.6

- If a player's saved guild records are lost or reset, their professions and gear score are now shared again. Before, the addon remembered "already shared" and skipped them, so the player stayed missing from the Professions tab
- `/bp prof` says when the share is waiting because the game is holding addon messages (inside an instance or battleground)
- `/bp status` prints two more lines for troubleshooting: version, role, which saved guild data is in use and how many records each holds, where you are, and why the last message was held

## 1.0.5

- Settings > "5. Wipe data and start fresh" now also has "Wipe tickets" and "Wipe all of the above", which wipes DKP, loot history, attendance, crafting orders, the Wanted board and tickets in one go
- A ticket wipe removes every ticket made before it: the staff queue on every Team Captain's game and each member's "My tickets". Old tickets offered by a game that hasn't caught up are refused

## 1.0.4

- Settings > "5. Wipe data and start fresh" (Guild Master and above): two buttons, each needing two clicks
  - "Wipe DKP, loot and attendance" clears every balance, the loot history, decays and raid attendance
  - "Wipe crafting orders and Wanted board" clears every order, open or finished
- The wipe reaches every guild member's game through the normal sync. Anything recorded after it counts as normal
- Raids, sign-ups, the roster, alts, professions, recipes, settings and tickets are not touched
- The old records stay in the log and simply stop counting, so a wipe by mistake can be undone in a later version if ever needed

## 1.0.3

- Roster: a "How do I share my PvP rank?" button at the bottom right. Hover it for the steps: open Character > Player vs. Player, and Blood Pact shares the rank a moment later (or type /bp pvp)
- Opening the character sheet or its Player vs. Player tab now reads your PvP rank and shares it a few seconds later
- A member's details say "not shared yet (see the button below)" when their rank hasn't come in

## 1.0.2

- Roster: a Zone column showing where each member is. For someone offline it shows where the game last saw them, greyed out. Press the heading to sort by zone
- The Roster's smallest width is now 910 so the new column fits; the Classes, Details and Loot pane moves right with it

## 1.0.1

- Professions: a "How do I share my recipes?" button at the bottom of the Crafters view. Hover it for the steps: open Character > Professions, click the link bubble on each profession, and Blood Pact records the recipes and shares them with the guild
- The footer says when your own recipes aren't shared yet, and an empty recipe list gives the same steps

## 1.0.0

Blood Pact is out of beta. This is the first full release.

- "Made by Kitch" now shows in the corner of the window, on the About page, in `/bp about` and in the game's addon list
- Recruit stays Team Captain and above only: the zone scan checks the player's rank itself, on top of the tab being hidden
- Everything from the 0.x betas is included: DKP and loot, raid sign-ups with selection, the Roster with its class chart, professions and crafting orders with mail, BiS Check, the warlock summon queue, recruiting, tickets, and the glass look with folding sections

## 0.26.3

- Recruit stays Team Captain and above only: the zone scan now checks the player's rank itself, on top of the tab being hidden, and tests cover every rank

## 0.26.2

- Recruit: the game blocks a guild invite whose chat line an addon wrote ("blocked from an action only available to the Blizzard UI"), so Blood Pact no longer writes anything into the chat box for an invite
- Click a name under "They replied" and the full invite, `/ginvite` plus the name spelled exactly, appears in a copy box, already selected. Press Ctrl+C, then in chat press Enter, Ctrl+V, Enter
- After Ctrl+C the copy box lets go of the keyboard, so the next Enter opens chat, and the name is marked "copied"

## 0.26.1

- Tickets: the queue now stretches with the window, and the kind of problem is shown in full when there is room ("Language or harassment") and as a short name when there isn't ("Language"). It is no longer cut off mid-word
- The ticket's details and buttons keep to the right edge of the window

## 0.26.0

- Tickets: a new tab where any guild member can report a problem with a player: language or harassment, cheating or botting, ninja looting or a loot dispute, breaking guild rules, breaking the game's rules, a scam or the guild bank, or something else. Three steps: what kind, who, what happened
- Team Captains and above get a queue: Open, Assigned to me and Resolved. Working a ticket is three steps too: take it, add notes, resolve it with an outcome (no action needed, spoke with the player, warning given, loot corrected, removed from the guild, reported to Blizzard). A resolved ticket can be reopened
- The reporter sees where their ticket stands under "My tickets" and gets a chat line when it changes. They see the status and outcome, never the staff notes
- Tickets are private to staff. They are whispered addon to addon only to Team Captains and above and are never put in the guild's shared log, so other members' games hold no copy. A ticket about a Team Captain or above is never sent to that person
- Staff games keep each other's copies in step, so a Team Captain who was offline catches up from a colleague. If no staff are online, a new ticket waits and goes out when one logs in
- Limits: 5 open tickets per member, one every 30 seconds, 300 letters each. Resolved tickets are dropped after 90 days
- New permission "tickets" (Team Captain and above). The tab strip is a little tighter so ten tabs fit

## 0.25.1

- The window can now be dragged much smaller. Its smallest size follows the tab you are on and which sections are folded: with everything folded, most tabs go well under the old 800 x 500
- Opening a section, or switching to a tab that needs more room, grows the window just enough to show it. Folding a section never moves the window by itself
- The smallest width is back to 760 on every tab except Roster, which keeps the 800 its columns need. Professions keeps the old smallest height for now

## 0.25.0

- Raid & Loot now follows a raid night: "1. Start of the raid" (on-time bonus, progression and auto-award switches), "2. Loot: charge the winner", "3. End of the raid" (full-raid bonus, undo). "Custom award or deduction" folds away, and the winner list fills the height of the window
- Summon is laid out for what you do there. A warlock sees the summon requests first, then the buttons to act on them; "Need a summon yourself? Ask another warlock" folds away at the bottom. Everyone else still gets the warlock list and the ask buttons at the top
- Settings are grouped in the order the rules apply: 1. Earning DKP, 2. Loot prices, 3. Decay (with the decay buttons), 4. Inactivity and Initiate promotion. Opening one group closes the others, so the tab always fits
- Standings, Professions and BiS Check already lead with their list and are unchanged

## 0.24.0

- A new look: every Blood Pact window is a pane of dark glass that lets a little of the game world show through, with a pale haze that is brightest at the top, hairline edges and tinted buttons and fields
- A button in the title bar switches between Frosted (the default), Clear (more see-through) and Solid (as before). The game doesn't let addons blur what is behind a window, so this is translucent glass, not a true blur
- Tabs now run in the order a guild does things: Recruit, Roster, Professions, BiS Check, Raids, Summon, Raid & Loot, Standings, Settings. The window reopens on the tab you used last
- Sections that are only needed now and then fold away, and the lists around them take the room. A click on the section's bar opens it, and each character remembers which are open
- Raids: "Schedule a raid and leader tools" folds at the bottom; the raid list and sign-up list now fill the height of the window
- Roster: "Link or unlink an alt" folds under the member's details
- Recruit: "Read or edit the message" folds under the three message buttons, so the scan list sits higher

## 0.23.0

- Roster: a Class column, in each class's colour. Press the Class heading to sort by it
- Roster > Classes: a pie chart of the guild by class with a legend showing each class's count and share. "Online only" switches the chart to who is on right now
- Click a class in the legend to list only its members; click it again to show everyone
- Team Captains and above can message one class: pick the class, type the message, and one click whispers each online member of it (40 at most). It only works with a class picked, so it can't go to the whole guild
- The window's smallest width is a little wider (800) so the new column fits

## 0.22.2

- Inside battlegrounds and instances WoW Forever refuses chat sent by addons. Blood Pact now notices the refusal instead of reporting the message as sent
- Recruit: when a whisper is refused, the name is not marked "whispered"; a whisper to that player opens with your message already typed, and you press Enter to send it
- While the game is refusing, Blood Pact stops trying (no more red "Interface action failed" errors) and tries again after you change zone
- The same check covers the other chat buttons: order and summon whispers, "Post in guild chat", "Whisper sign-ups" and the summon messages each say when the game refused them

## 0.22.1

- Summon messages: the window now sits above the main Blood Pact window, so the main window's buttons and text no longer show through it; a little more room between the two messages

## 0.22.0

- Recruit: when someone outside the guild whispers "inv" or "invite", their name is listed under step 3, spelled exactly as the game sends it, and you get a chat line
- Click the name and `/ginvite` with that name is written into your chat box; press Enter to send the invite. Accented and special letters never have to be typed
- If you have already typed `/ginvite ` yourself, the click adds just the name where the cursor is
- The name leaves the list when the player joins the guild; right-click removes it
- Blood Pact still doesn't send guild invites itself: WoW Forever doesn't allow addons to

## 0.21.0

- Summon messages, for warlocks of Team Captain rank and above, sent only while they cast their own Ritual of Summoning
- The player being summoned is whispered when the ritual starts. A long whisper is sent as two, each cut at the end of a sentence so it fits the chat box
- If the portal is still short of clickers 4 seconds after it appears, one line goes to raid (or party) chat naming up to three group members who are standing next to you and not clicking. Once per ritual; nothing is said when two people are already clicking
- Both messages can be edited and each has its own off switch: press Messages at the top of the summon queue. `{names}` in the callout becomes the idle players' names

## 0.20.0

- Raids: signing up now asks for a spot; it doesn't hold one. A Team Captain or above clicks a name in the sign-up list to select that player, and clicks again to take the spot back
- The raid shows "Selected 3/10" with the selected tanks, healers and damage dealers, and how many are still waiting. Selected players sort to the top and show "Selected" in green
- A raid can't be over-filled: once every spot is taken, someone has to be unselected first. Answering "Can't" gives a spot back
- Players get a line on screen when they are selected, and a chat line if the spot is taken back
- Once a raid has been selected, the 30 and 15 minute reminders and "Whisper sign-ups" go only to the selected players
- Summon: if you invite someone while in a group you don't lead, the leader is asked to invite them instead, with one whisper from your click. "Invite for summon" does the same in one whisper for everyone it would have invited

## 0.19.0

- Recruit: search your faction's starting zones without travelling there. Horde gets Durotar and Mulgore (Kalimdor), Tirisfal Glades (Eastern Kingdoms) and Zephras Isle (Skyborne); Alliance gets its own four
- Each click on a zone searches a few levels at a time (1-4, then 5-8, then 9-12) and adds the unguilded players it finds to the list, because the game lists only about 50 players per search. The result line says when the game cut a list short
- Recruit: click a name and that player is whispered the picked message (Social, Raiding or Crafting), one whisper per click. Right-click opens a whisper to type your own
- A name you've whispered is marked "whispered" until you log out, and a second click doesn't send again; Shift-click sends it again on purpose
- The picked message is marked, and an edit you make in the box stays there and is what gets sent
- Blood Pact still never whispers or searches on its own: every search and every whisper is one click

## 0.18.0

- Summon queue for warlocks: anyone types "123" in raid, party or guild chat, or whispers it to the warlock, and their name joins a small list on the warlock's screen
- Click a name to cast Ritual of Summoning on that player; right-click targets them. The click is the game's own secure button, so every summon is the warlock's own click
- Each asker is listed once, in the order they asked. Names leave the list when the player arrives, when you press x, or after 30 minutes
- Requests made from the Summon tab join the same list. A guildmate who isn't in your group yet shows an Invite button
- Only guild members and people already in your group are listed, so strangers' whispers can't fill it
- The warlock can change the keyword at the bottom of the list. `/bp summon`, or "Open summon queue" on the Summon tab, opens it
- The game locks the list during combat; it catches up when combat ends

## 0.17.1

- Orders now move To craft > In transit > Delivered. Once the full amount is mailed, the order reads "In transit, mailed <date>" for the whole guild, in gold, until the member who ordered presses "I received it"
- An order in transit stays listed under To craft but no longer counts in the "To craft (n)" number or as late
- The member who ordered gets one chat line when their order is mailed, telling them to collect it and confirm
- Part-mailed orders show how many have gone ("2 of 3 mailed")
- What has been mailed is now kept in the guild's log, not on the crafter's own character. An order mailed with 0.17.0 switches to In transit by itself after the update

## 0.17.0

- Mailing a crafting order: open a mailbox and Blood Pact lists the orders you've accepted, with how many of the item are in your bags
- Press "Fill in the mail" and the game's Send Mail form is filled in for you: the guild member who ordered, the item as the subject, a short message, and the items attached from your bags
- You check it and press Send yourself; the game takes the postage then. Blood Pact never sends mail on its own
- When the full amount has been mailed, the order is marked ready with the note "In your mailbox", and the member who ordered confirms when they have it
- Only whole stacks are attached and never more than is owed; a stack that is too big is left for you to split by hand. Bound items are skipped. One mail carries up to 12 stacks, so a bigger order takes a second mail
- `/bp mail` opens the list at a mailbox

## 0.16.2

- Raids: the sign-up counts stay on one line and no longer overlap "You haven't answered yet"; the note about the readiness % moved to a heading above the sign-up list

## 0.16.1

- Summon: "Ask selected" now whispers the chosen warlock, so they see it even without Blood Pact (before, it only reached warlocks running the addon)
- Summon: the status line says who was whispered, and that "Ask any warlock" reaches only warlocks running Blood Pact

## 0.16.0

- Orders > New order: pick a profession, see every recipe the guild has shared with how many crafters know it (and how many are online), and place an order without finding a crafter first
- Ask "Any guild crafter" (the Wanted board) or cycle to one crafter by name
- Wanted orders are matched to crafters: they show in To craft for everyone who has shared that recipe, and those crafters get a chat line
- Estimated material cost on recipes and orders, from the Auctionator addon's last auction scan when you have it installed; reagents with no price are flagged
- Orders opens on New order when nothing is waiting for you

## 0.15.0

- Crafting orders, inside the guild only
- Every recipe in a crafter's list has an Order button: set a quantity, who supplies the materials (you, the crafter or the guild bank) and a note, then order from that crafter
- If the crafter is online, the same click whispers them the recipe; if not, the order is waiting at their next login
- Post as Wanted: put a request on the Wanted board for any guild crafter who has shared that recipe
- The crafter accepts with a promised turnaround of 2, 8, 24 or 48 hours; the order shows the time left and turns red when late
- Steps everyone sees: open, accepted, ready, delivered. A crafter can decline or hand an order back; the member who asked can cancel
- Only the member who asked can confirm delivery, so the history stays honest
- Professions > Orders: To craft, My requests, Wanted board and History, with a count of orders needing you
- Chat lines for your own orders (new order, accepted, ready, delivered) and a login reminder
- Officers can cancel an order to keep the board tidy
- A member can have up to 20 orders open at once
- Recipe and loot tooltips now stay on screen

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
