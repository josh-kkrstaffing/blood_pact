# BiS research for all specs (started 2026-11-19, for Blood Pact 0.7.0)
User ask: pre-raid + raid BiS for all specs from multiple sites, per-player score, score shown on raid sign-ups.
Method (decided earlier, don't re-ask): each guide's top pick = 2 pts, each alternative = 1; BiS = most points;
ties -> ForeverSpec order; score = points / BiS points. Guild is Horde: use Horde versions.
Specs: classic 27 + Feral split (cat/bear) = 28. Skip "Shockadin".
Sources used for every spec (3): FrostyBoost all-spec page (fb), ForeverSpec per spec (fs), ConquestCapped per spec (cc).
Raw data: raw/<class>.txt, lines verbatim from fetches under headers "@site|Class|Spec".
Raid BiS: Blizzard hasn't published raid loot tables (timesaver.gg, ~Nov 4); raids open Dec 9. Wowhead has raid BiS
pages (from beta files) but WebFetch can't read item names (JS). ConquestCapped raid sections are near-empty.
URL patterns that fetch: foreverspec.com/pre-raid-bis/<class>/<spec>/ ; conquestcapped.com/guides/wow-forever/wow-forever-<spec>-<class>-bis/
FrostyBoost: https://frostyboost.com/blog/guides/wow-forever-bis-list (153k chars; offset 100000 for the tail)
Progress: see raw/ files present.
Findings so far: Wowhead raid BiS pages are EMPTY placeholders ("will be filled in once more items are discovered at max level").
=> No raid BiS published anywhere readable. Ship raid lists empty + say so.
ConquestCapped: only URLs from search results fetch (fury-warrior done; hunter overview, discipline-priest, holy-paladin, subtlety-rogue known).
  mythicsim / wowtbc guessed URLs are blocked. So every spec gets fb + fs; cc where a URL is known.
Done raw: warrior (fb x3, fs x3, cc fury), paladin (fb x3, fs x3), hunter (fb x3, fs x3).
Done raw also: rogue (fb,fs x3), priest (fb,fs x3), shaman (fb x3), mage arcane (fb).
Done raw also: mage (fb,fs x3), shaman fs x3, warlock affliction fb, druid fb x4.
RAW COMPLETE for all 28 specs (fb + fs; cc for fury warrior, disc priest, holy paladin, sub rogue, hunters). ForeverSpec has no bear list (Feral Bear = fb only).
Horde twins: Theramore <shoulder> = Darkspear <shoulder>; Theramore Gloves/Gauntlets = Raider Gloves/Gauntlets; Sentinel's = Outrider's; Highlander's = Defiler's; Cloak of the Honor Guard = Deathguard's Cloak; Stormpike Insignia = Frostwolf Insignia. Items marked (A) with no Horde twin are dropped.
NEXT: write rank.py -> BiSData.lua + sheet; then addon score + Raids column; fix screenshot layout (prog checkbox label overflow, scrollbar look).
Warlock Demonology + Destruction: keep the earlier 6-7 guide rankings (work/demo.py DATA; Destro = sheet tab "Ranked: Destro Lock").
Note: fs sources were edited to Horde (Darkspear Raiders / Warsong / Frostwolf / Defilers) where the page gave the Alliance faction.
