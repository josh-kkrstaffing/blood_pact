std = "lua51"
max_line_length = false
-- unused arguments/loop vars and shadowed locals are style warnings, not bugs
ignore = { "212", "213", "421", "431", "432", "542" }
exclude_files = { ".release/" }
globals = { "BloodPactDB", "BloodPact_OnCompartmentClick", "SlashCmdList", "SLASH_BLOODPACT1", "SLASH_BLOODPACT2" }
read_globals = {
  "UnitClass", "time", "RAID_CLASS_COLORS", "C_Item", "GetItemInfo", "ITEM_QUALITY_COLORS", "IsShiftKeyDown", "C_Spell", "GetSpellInfo", "GetProfessions", "GetProfessionInfo", "GetNumSkillLines", "GetSkillLineInfo", "C_TradeSkillUI", "GetTalentTabInfo", "GetNumTalentTabs", "GetRealZoneText", "UnitLevel", "IsInGroup", "UnitIsGroupAssistant", "C_PartyInfo", "InviteUnit", "ChatFrame_AddMessageEventFilter", "ERR_CHAT_PLAYER_NOT_FOUND_S", "CreateFont", "PixelUtil", "GetGuildRosterLastOnline", "ERR_GUILD_JOIN_S", "ERR_GUILD_LEAVE_S", "ERR_GUILD_REMOVE_SS", "ERR_GUILD_PROMOTE_SSS", "ERR_GUILD_DEMOTE_SSS", "C_Calendar", "C_DateAndTime", "Enum", "RaidNotice_AddMessage", "RaidWarningFrame", "ChatTypeInfo", "PlaySound", "SOUNDKIT", "SendChatMessage", "GetInventoryItemLink", "C_Container", "GetContainerNumSlots", "GetContainerItemLink", "BANK_CONTAINER", "NUM_BAG_SLOTS", "NUM_BANKBAGSLOTS", "Questie", "GameTooltip", "GameTooltip_Hide",
  "C_ChatInfo", "C_FriendList", "C_GuildInfo", "C_Timer", "ChatEdit_InsertLink", "ChatFontNormal",
  "ChatFrameUtil", "ChatFrame_SendTell", "CreateFrame", "GetGuildInfo", "GetGuildRosterInfo",
  "GetNormalizedRealmName", "GetNumGroupMembers", "GetNumGuildMembers", "GetServerTime", "GetTime",
  "GetZoneText", "IsInGuild", "IsInRaid", "UIParent", "UISpecialFrames", "UnitGUID", "UnitIsGroupLeader",
  "UnitName", "date", "geterrorhandler", "hooksecurefunc", "tinsert", "wipe",
}
files["tests/"] = { std = "lua51" }
