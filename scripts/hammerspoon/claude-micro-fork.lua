-- Ctrl+F20 forks the current Claude Code session through its own menu.
-- M.fork(true) checks focus and closes the menu without creating a fork.
return require("claude-micro-session-menu").new({
  action="Fork", verb="Fork", method="fork", resultField="lastFork",
  logger="ClaudeFork", modifiers={"ctrl"}, key="f20", rejectModal=true,
  -- A fork should open another Code session; navigation home is not success.
  resultURLPattern="^https://claude%.ai/epitaxy/[^/?#]+",
  confirmationMessage="Claude 正在等待确认，请先处理确认框；未继续执行 Fork",
})
