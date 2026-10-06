-- Claude layer: first six sidebar sessions across projects on F13-F18; archive on F19.
local M={hotkeys={}}
function M.stop()
  for _,key in ipairs(M.hotkeys) do key:delete() end
  M.hotkeys={}
  if M.sessions then M.sessions.stop() end
  if M.archive then M.archive.stop() end
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
      M.sessions.select(slot)
    end)
  end
  M.archive=require("claude-micro-archive")
  M.archive.bind(false)
  return M
end
return M
