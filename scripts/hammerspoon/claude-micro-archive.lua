-- F19 archives the current Claude Code session through its own accessible menu.
-- M.archive(true) checks the live menu without selecting Archive.
return require("claude-micro-session-menu").new({
  action="Archive", verb="归档", method="archive", resultField="lastArchive",
  logger="ClaudeArchive", modifiers={}, key="f19",
  confirmationMessage="Claude 要求确认归档，请先检查未提交改动，再处理确认框",
})
