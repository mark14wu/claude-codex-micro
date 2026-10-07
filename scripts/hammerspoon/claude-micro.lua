-- Claude layer: F13-F18 select sidebar sessions; F19 archives; F20 opens a new session.
local M={hotkeys={}}
function M.stop()
  for _,key in ipairs(M.hotkeys) do key:delete() end
  M.hotkeys={}
  if M.sessions then M.sessions.stop() end
  if M.archive then M.archive.stop() end
  if M.newSession then M.newSession.stop() end
end
function M.start()
  if _G.claudeMicro and _G.claudeMicro.stop then _G.claudeMicro.stop() end
  if _G.microTest and _G.microTest.stop then _G.microTest.stop() end
  if _G.claudeArchive and _G.claudeArchive.stop then _G.claudeArchive.stop() end
  M.sessions=require("claude-micro-sidebar")
  for i=1,6 do
    local slot=i
    M.hotkeys[#M.hotkeys+1]=hs.hotkey.bind({},"f"..(slot+12),nil,function()
      if M.archive and M.archive.busy then return end
      if M.newSession then M.newSession.cancel() end
      M.sessions.select(slot)
    end)
  end
  M.archive=require("claude-micro-archive")
  M.archive.bind(false)
  M.newSession=require("claude-micro-new-session")
  M.newSession.bind(function()
    return not M.archive.busy and not M.archive.triggerTimer
  end,function()
    M.sessions.stop()
  end)
  return M
end
return M
