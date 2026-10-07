-- Claude layer: F13-F18 select sessions; F19 archives; F20 creates; Ctrl+F20 forks.
local M={hotkeys={}}
local function pending(action)
  return action and (action.busy or action.triggerTimer) and true or false
end
local function prepareMenuAction()
  M.sessions.stop()
  if M.newSession then M.newSession.cancel() end
end
function M.stop()
  for _,key in ipairs(M.hotkeys) do key:delete() end
  M.hotkeys={}
  if M.sessions then M.sessions.stop() end
  if M.archive then M.archive.stop() end
  if M.fork then M.fork.stop() end
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
      if pending(M.archive) or pending(M.fork) then return end
      if M.newSession then M.newSession.cancel() end
      M.sessions.select(slot)
    end)
  end
  M.archive=require("claude-micro-archive")
  M.fork=require("claude-micro-fork")
  M.archive.bind(false,function() return not pending(M.fork) end,prepareMenuAction)
  M.fork.bind(false,function() return not pending(M.archive) end,prepareMenuAction)
  M.newSession=require("claude-micro-new-session")
  M.newSession.bind(function()
    return not pending(M.archive) and not pending(M.fork)
  end,function()
    M.sessions.stop()
  end)
  return M
end
return M
