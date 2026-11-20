# Changelog

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
