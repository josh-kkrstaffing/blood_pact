-- Blood Pact: ranked pre-raid BiS lists. Generated from the Blood Pact BiS sheet.
-- Ranking: each guide's top pick = 2 points, each alternative = 1; score = points / BiS points.
local _, ns = ...
ns.BiSData = ns.BiSData or {}

ns.BiSData.WARLOCK = {
    Demonology = {
        label = "Demonology Warlock",
        updated = "2026-11-18",
        slots = {
            { slot = "Head", inv = { 1 }, items = {
                { name = "Spellweaver's Turban", how = "Upper Blackrock Spire: General Drakkisath", score = 1 },
                { name = "Deathmist Mask", how = "Quest: Saving the Best for Last", score = 0.3, note = "One guide marks it Alliance-only; confirm for Horde" },
                { name = "Crimson Felt Hat", how = "Stratholme: Magistrate Barthilas", score = 0.2 },
            } },
            { slot = "Neck", inv = { 2 }, items = {
                { name = "Nacreous Shell Necklace", how = "Stratholme: Cannon Master Willey", score = 1 },
                { name = "Orb of the Darkmoon", how = "Darkmoon Faire quest (1200 tickets)", score = 0.6 },
                { name = "Dark Advisor's Pendant", how = "Scholomance: Vectus", score = 0.1 },
            } },
            { slot = "Shoulder", inv = { 3 }, items = {
                { name = "Rugged Mantle of the Timbermaw", how = "Vendor: Meilosh, Felwood (Timbermaw Hold)", score = 1, note = "Needs Tailoring 290 to wear" },
                { name = "Mantle of the Timbermaw", how = "Crafted: Tailoring 290", score = 0.83, note = "Best pick for non-tailors" },
                { name = "Argent Shoulders", how = "Crafted: Tailoring 300", score = 0.33 },
            } },
            { slot = "Back", inv = { 15 }, items = {
                { name = "Arcanoweave Cloak", how = "Vendor: Pix Xizzix (Undermine Trader), Stranglethorn Vale", score = 1 },
                { name = "Fel Cape", how = "Crafted: Tailoring 300", score = 0.5 },
                { name = "Hide of the Wild", how = "Crafted: Leatherworking 300", score = 0.38 },
            } },
            { slot = "Chest", inv = { 5 }, items = {
                { name = "Robe of the Void", how = "Crafted: Tailoring 295", score = 1 },
                { name = "Robe of Winter Night", how = "Crafted: Tailoring 245", score = 0.17, note = "Tied with Robes of Dark Summons; the stat-scored guide ranks it higher" },
                { name = "Robes of Dark Summons", how = "Crafted: Tailoring", score = 0.17 },
            } },
            { slot = "Wrist", inv = { 9 }, items = {
                { name = "Dryad's Wrist Bindings", how = "Warsong Outriders, Exalted (vendor Kelm Hargunth)", score = 1 },
                { name = "Sublime Wristguards", how = "Dire Maul (one guide says Stratholme)", score = 0.86, note = "Confirm source in game" },
                { name = "Rockfury Bracers", how = "Quest: Stalwart's Battlegear", score = 0.29 },
            } },
            { slot = "Hands", inv = { 10 }, items = {
                { name = "Gloves of Spell Mastery", how = "Crafted: Tailoring 295", score = 1 },
                { name = "Deathmist Wraps", how = "Quest: Just Compensation", score = 0.83 },
                { name = "Hands of Power", how = "Blackrock Spire: Quartermaster Zigris", score = 0.5 },
            } },
            { slot = "Waist", inv = { 6 }, items = {
                { name = "Belt of the Archmage", how = "Crafted: Tailoring 295", score = 1 },
                { name = "Knowledge of the Timbermaw", how = "Vendor: Meilosh, Felwood (Timbermaw Hold)", score = 0.75, note = "Needs Tailoring 290 to wear" },
                { name = "Ban'thok Sash", how = "Blackrock Depths: Ok'thor the Breaker", score = 0.5 },
            } },
            { slot = "Legs", inv = { 7 }, items = {
                { name = "Outrider's Silk Leggings", how = "Warsong Outriders, Exalted (vendor Kelm Hargunth)", score = 1, note = "Horde version of Sentinel's Silk Leggings" },
                { name = "Skyshroud Leggings", how = "Lower Blackrock Spire: Highlord Omokk", score = 0.8 },
                { name = "Leggings of Torment", how = "Upper Blackrock Spire: Lord Valthalak", score = 0.4 },
            } },
            { slot = "Feet", inv = { 8 }, items = {
                { name = "Omnicast Boots", how = "Blackrock Depths: Golem Lord Argelmach", score = 1 },
                { name = "Maleki's Footwraps", how = "Stratholme: Maleki the Pallid", score = 0.4 },
                { name = "Sorcerer's Boots", how = "Quest: Anthion's Parting Words", score = 0.2 },
            } },
            { slot = "Ring 1", inv = { 11, 12 }, items = {
                { name = "Rune Band of Wizardry", how = "Upper Blackrock Spire: Lord Valthalak", score = 1 },
                { name = "Warden's Signet of Brilliance", how = "The Watchers, Exalted", score = 0.5 },
            } },
            { slot = "Ring 2", inv = { 11, 12 }, items = {
                { name = "Channeler's Ring", how = "Vendor: Pix Xizzix (Undermine Trader), Stranglethorn Vale", score = 1 },
                { name = "Mindtear Band", how = "World drop (BoE)", score = 0.5 },
            } },
            { slot = "Trinket 1", inv = { 13, 14 }, items = {
                { name = "Eye of the Beast", how = "Quest: For The Horde!", score = 1 },
                { name = "Royal Seal of Eldre'Thalas", how = "Quest: Harnessing Shadows (Dire Maul)", score = 0.67 },
            } },
            { slot = "Trinket 2", inv = { 13, 14 }, items = {
                { name = "Briarwood Reed", how = "Upper Blackrock Spire: Jed Runewatcher", score = 1, note = "The stat-scored guide doesn't score on-use or proc effects" },
                { name = "Draconic Infused Emblem", how = "Upper Blackrock Spire: General Drakkisath", score = 1 },
                { name = "Weakness Analyzer", how = "Vendor: Pix Xizzix (Undermine Trader), Stranglethorn Vale", score = 1 },
            } },
            { slot = "Main hand", inv = { 16 }, items = {
                { name = "Sageblade", how = "Crafted: Blacksmithing 300", score = 1 },
                { name = "Blade of the New Moon", how = "Dire Maul: Immol'thar", score = 0.4 },
                { name = "Witchblade", how = "Scholomance: Darkmaster Gandling", score = 0.2 },
            } },
            { slot = "Off hand", inv = { 17 }, items = {
                { name = "Therazane's Touch", how = "Frostwolf Clan, Exalted", score = 1, note = "Tied with Tome of the Lost; the stat-scored guide ranks it higher" },
                { name = "Tome of the Lost", how = "Upper Blackrock Spire: General Drakkisath", score = 1 },
                { name = "Tome of Shadow Force", how = "Frostwolf Clan, Exalted", score = 0.67 },
            } },
            { slot = "Ranged / Relic", inv = { 18 }, items = {
                { name = "Bonecreeper Stylus", how = "Scholomance: Darkmaster Gandling", score = 1 },
                { name = "Skul's Ghastly Touch", how = "Stratholme: Skul", score = 0.67 },
                { name = "Ritssyn's Wand of Bad Mojo", how = "Stratholme: Baron Rivendare", score = 0.67 },
            } },
        },
        twoHand = { name = "Lord Valthalak's Staff of Command", how = "Upper Blackrock Spire: Lord Valthalak", note = "Two-hander option; one guide rates a two-hander above main hand + off hand" },
    },
}
