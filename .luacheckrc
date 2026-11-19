std = "lua51"
max_line_length = false
-- unused arguments/loop vars and shadowed locals are style warnings, not bugs
ignore = { "212", "213", "421", "431", "432", "542" }
exclude_files = { ".release/" }
globals = { "BloodPactDB", "BloodPact_OnCompartmentClick", "SlashCmdList", "SLASH_BLOODPACT1", "SLASH_BLOODPACT2" }
read_globals = {
  "UnitClass", "GetInventoryItemLink", "C_Container", "GetContainerNumSlots", "GetContainerItemLink", "BANK_CONTAINER", "NUM_BAG_SLOTS", "NUM_BANKBAGSLOTS", "Questie", "GameTooltip", "GameTooltip_Hide",
  "C_ChatInfo", "C_FriendList", "C_GuildInfo", "C_Timer", "ChatEdit_InsertLink", "ChatFontNormal",
  "ChatFrameUtil", "ChatFrame_SendTell", "CreateFrame", "GetGuildInfo", "GetGuildRosterInfo",
  "GetNormalizedRealmName", "GetNumGroupMembers", "GetNumGuildMembers", "GetServerTime", "GetTime",
  "GetZoneText", "IsInGuild", "IsInRaid", "UIParent", "UISpecialFrames", "UnitGUID", "UnitIsGroupLeader",
  "UnitName", "date", "geterrorhandler", "hooksecurefunc", "tinsert", "wipe",
}
files["tests/"] = { std = "lua51" }
