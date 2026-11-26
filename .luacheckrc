std = "lua51"
max_line_length = false
-- unused arguments/loop vars and shadowed locals are style warnings, not bugs
ignore = { "212", "213", "421", "431", "432", "542" }
exclude_files = { ".release/" }
globals = { "BloodPactDB", "BloodPact_OnCompartmentClick", "SlashCmdList", "SLASH_BLOODPACT1", "SLASH_BLOODPACT2" }
read_globals = {
  "UnitClass", "time", "GetChannelList", "IsInInstance", "CharacterFrame", "PVPFrame", "PVPUIFrame", "IsControlKeyDown", "IsMetaKeyDown", "CreateColor", "ChatEdit_GetActiveWindow", "ChatFrame_OpenChat", "UnitChannelInfo", "InCombatLockdown", "UnitInRange", "NUM_TOTAL_EQUIPPED_BAG_SLOTS", "ATTACHMENTS_MAX_SEND", "GetSendMailItem", "GetSendMailPrice", "SendMailNameEditBox", "SendMailSubjectEditBox", "SendMailBodyEditBox", "MailEditBox", "ClickSendMailItemButton", "MailFrameTab_OnClick", "MailFrameTab2", "MailFrame", "ClearCursor", "RAID_CLASS_COLORS", "Auctionator", "UnitPVPRank", "C_MajorFactions", "UnitFactionGroup", "C_Item", "GetItemInfo", "ITEM_QUALITY_COLORS", "IsShiftKeyDown", "C_Spell", "GetSpellInfo", "GetProfessions", "GetProfessionInfo", "GetNumSkillLines", "GetSkillLineInfo", "C_TradeSkillUI", "GetTalentTabInfo", "GetNumTalentTabs", "GetRealZoneText", "UnitLevel", "IsInGroup", "UnitIsGroupAssistant", "C_PartyInfo", "InviteUnit", "ChatFrame_AddMessageEventFilter", "ERR_CHAT_PLAYER_NOT_FOUND_S", "CreateFont", "PixelUtil", "GetGuildRosterLastOnline", "ERR_GUILD_JOIN_S", "ERR_GUILD_LEAVE_S", "ERR_GUILD_REMOVE_SS", "ERR_GUILD_PROMOTE_SSS", "ERR_GUILD_DEMOTE_SSS", "C_Calendar", "C_DateAndTime", "Enum", "RaidNotice_AddMessage", "RaidWarningFrame", "ChatTypeInfo", "PlaySound", "SOUNDKIT", "SendChatMessage", "GetInventoryItemLink", "C_Container", "GetContainerNumSlots", "GetContainerItemLink", "BANK_CONTAINER", "NUM_BAG_SLOTS", "NUM_BANKBAGSLOTS", "Questie", "GameTooltip", "GameTooltip_Hide",
  "C_ChatInfo", "C_FriendList", "C_GuildInfo", "C_Timer", "ChatEdit_InsertLink", "ChatFontNormal",
  "ChatFrameUtil", "ChatFrame_SendTell", "CreateFrame", "GetGuildInfo", "GetGuildRosterInfo",
  "GetNormalizedRealmName", "GetNumGroupMembers", "GetNumGuildMembers", "GetServerTime", "GetTime",
  "GetZoneText", "IsInGuild", "IsInRaid", "UIParent", "UISpecialFrames", "UnitGUID", "UnitIsGroupLeader",
  "UnitName", "C_VoiceChat", "C_AuctionHouse", "GetMoney", "GetItemCount", "C_Item", "C_UnitAuras", "UnitBuff", "GetWeaponEnchantInfo", "issecretvalue", "InCombatLockdown", "IsInGroup", "date", "geterrorhandler", "hooksecurefunc", "tinsert", "wipe",
}
files["tests/"] = { std = "lua51" }
