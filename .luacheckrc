std = "lua51"
max_line_length = false
exclude_files = { ".release/" }
globals = { "BloodPactDB", "BloodPact_OnCompartmentClick", "SlashCmdList", "SLASH_BLOODPACT1", "SLASH_BLOODPACT2" }
read_globals = {
  "C_ChatInfo", "C_FriendList", "C_GuildInfo", "C_Timer", "ChatEdit_InsertLink", "ChatFontNormal",
  "ChatFrameUtil", "ChatFrame_SendTell", "CreateFrame", "GetGuildInfo", "GetGuildRosterInfo",
  "GetNormalizedRealmName", "GetNumGroupMembers", "GetNumGuildMembers", "GetServerTime", "GetTime",
  "GetZoneText", "IsInGuild", "IsInRaid", "UIParent", "UISpecialFrames", "UnitGUID", "UnitIsGroupLeader",
  "UnitName", "date", "geterrorhandler", "hooksecurefunc", "tinsert", "wipe",
}
files["tests/"] = { std = "lua51" }
