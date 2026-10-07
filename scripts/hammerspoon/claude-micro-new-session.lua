-- F20 opens Claude's native File > New Session command, including from another app.
-- A successful menu selection acknowledges the command, not a persisted session.
local M={busy=false,timer=nil,lastPress=-math.huge,generation=0}
local BUNDLE="com.anthropic.claudefordesktop"
local MENU={"File","New Session"}
local ACTIVATION_TIMEOUT=1.5
local log=hs.logger.new("ClaudeNew","info")

local function attr(element,key)
  local ok,value=pcall(function() return element:attributeValue(key) end)
  if ok then return value end
end
local function finish(message)
  if M.timer then M.timer:stop(); M.timer=nil end
  M.busy=false
  if message then log.i(message); hs.alert.show(message,1.5) end
end
local function allowed()
  if not M.canStart then return true end
  local ok,value=pcall(M.canStart)
  return ok and value==true
end
local function currentWindow(app)
  local ax=hs.axuielement.applicationElement(app)
  return attr(ax,"AXFocusedWindow") or attr(ax,"AXMainWindow")
end
local function unobstructed(win)
  if not win or attr(win,"AXRole")~="AXWindow" or attr(win,"AXModal")==true then return false end
  local sheets=attr(win,"AXSheets")
  return type(sheets)~="table" or #sheets==0
end

function M.startNew()
  if M.busy or hs.timer.secondsSinceEpoch()-M.lastPress<0.5 or not allowed() then return false end
  M.lastPress=hs.timer.secondsSinceEpoch()
  M.busy=true
  M.generation=M.generation+1
  local generation=M.generation
  M.lastAttempt={time=M.lastPress,status="pending"}
  if M.beforeStart then
    local ok,result=pcall(M.beforeStart)
    if not ok or result==false then
      M.lastAttempt.status="cancelled"
      finish("未能准备 Claude 新会话，已取消")
      return false
    end
  end
  local started=hs.timer.secondsSinceEpoch()
  local initialFront=hs.application.frontmostApplication()
  local activated=false
  local function tick()
    if generation~=M.generation or not M.busy then return end
    M.timer=nil
    local ok,err=pcall(function()
      if not allowed() then M.lastAttempt.status="cancelled"; finish(); return end
      local app=hs.application.get(BUNDLE)
      local front=hs.application.frontmostApplication()
      if not app or front~=app then
        if activated and front~=initialFront then
          M.lastAttempt.status="cancelled"
          finish("已取消新会话：前台应用发生变化")
          return
        end
        if hs.timer.secondsSinceEpoch()-started>=ACTIVATION_TIMEOUT then
          M.lastAttempt.status="activation-timeout"
          finish("Claude 未能切到前台，未新建会话")
          return
        end
        if not activated then
          activated=true
          if not hs.application.launchOrFocusByBundleID(BUNDLE) then
            M.lastAttempt.status="activation-failed"
            finish("无法打开 Claude，未新建会话")
            return
          end
        end
        M.timer=hs.timer.doAfter(0.05,tick)
        return
      end
      local win=currentWindow(app)
      if not unobstructed(win) then
        M.lastAttempt.status="blocked"
        finish("Claude 没有可用的会话窗口，或正在等待对话框处理")
        return
      end
      local item=app:findMenuItem(MENU)
      if type(item)~="table" or item.enabled~=true then
        M.lastAttempt.status="unavailable"
        finish("Claude 的 New Session 菜单当前不可用")
        return
      end
      if not allowed() or hs.application.frontmostApplication()~=app or currentWindow(app)~=win
        or not unobstructed(win) then
        M.lastAttempt.status="cancelled"
        finish("已取消新会话：应用或窗口发生变化")
        return
      end
      -- Select only this exact native menu path, once. Never fall back to a
      -- typed shortcut or Return, which could affect an editor or another app.
      M.lastAttempt.status="selecting"
      local selected=app:selectMenuItem(MENU)
      if selected==true then
        M.lastAttempt.status="native-menu-selected"
        log.i("已调用 Claude 的 File > New Session 菜单")
        finish()
      else
        M.lastAttempt.status="unconfirmed"
        finish("New Session 菜单未确认执行，未重复操作")
      end
    end)
    if not ok then
      M.lastAttempt.status="unconfirmed"
      log.i("New Session 操作出错："..tostring(err))
      finish("Claude 新会话操作未确认，未重复执行")
    end
  end
  -- Leave the Carbon hotkey callback before focusing the app or its menu.
  M.timer=hs.timer.doAfter(0.03,tick)
  return true
end

function M.cancel()
  M.generation=M.generation+1
  if M.busy and M.lastAttempt then M.lastAttempt.status="cancelled" end
  finish()
end
function M.stop()
  M.cancel()
  if M.hotkey then M.hotkey:delete(); M.hotkey=nil end
  M.canStart=nil; M.beforeStart=nil
end
-- canStart must return true; beforeStart can cancel a pending session switch.
-- Both hooks are optional. beforeStart runs once, only after accepting a press.
function M.bind(canStart,beforeStart)
  M.stop()
  M.canStart=canStart; M.beforeStart=beforeStart
  M.hotkey=hs.hotkey.bind({},"f20",nil,function() M.startNew() end)
  return M
end
return M
