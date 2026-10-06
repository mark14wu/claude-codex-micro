-- F19 archives the current Claude Code session through its own accessible menu.
-- M.archive(true) checks the live menu without selecting Archive.
local M = {busy=false, timer=nil, triggerTimer=nil, hotkey=nil, lastPress=0}
local BUNDLE = "com.anthropic.claudefordesktop"
local MENU_TIMEOUT = 4
local RETRY_AFTER = 1.5
local RESULT_TIMEOUT = 3
local log = hs.logger.new("ClaudeArchive", "info")
local function attr(e, key)
  local ok, value = pcall(function() return e:attributeValue(key) end)
  return ok and value or nil
end
local function hasAction(e, name)
  local ok, actions = pcall(function() return e:actionNames() end)
  if not ok then return false end
  for _, action in ipairs(actions or {}) do if action == name then return true end end
  return false
end
local function act(e, name)
  if not hasAction(e,name) then return false end
  local ok, result = pcall(function() return e:performAction(name) end)
  return ok and result ~= nil and result ~= false
end
local function find(root, predicate, limit)
  local matches, queue, seen, pos = {}, {root}, {}, 1
  while pos <= #queue and pos <= (limit or 1800) do
    local e=queue[pos]; pos=pos+1
    if e and not seen[e] then
      seen[e]=true
      if predicate(e) then matches[#matches+1]=e end
      local desc=attr(e,"AXDescription")
      if desc ~= "Chat messages" and attr(e,"AXRole") ~= "AXMenuBar" then
        for _,child in ipairs(attr(e,"AXChildren") or {}) do queue[#queue+1]=child end
      end
    end
  end
  return matches
end
local function url(e)
  local u=attr(e,"AXURL")
  return type(u)=="table" and u.url or (type(u)=="string" and u or nil)
end
local function frontmost()
  local a=hs.application.frontmostApplication()
  return a and a:bundleID()==BUNDLE and a or nil
end
local function current(app)
  local ax=hs.axuielement.applicationElement(app)
  local win=attr(ax,"AXFocusedWindow") or attr(ax,"AXMainWindow")
  if not win then return nil,"无法读取 Claude 当前窗口" end
  local webs=find(win,function(e)
    local u=url(e)
    return attr(e,"AXRole")=="AXWebArea" and u and u:match("^https://claude%.ai/epitaxy/[^/?#]+")
  end)
  if #webs~=1 then return nil,"请先打开一个 Claude Code 会话" end
  local web=webs[1]
  local title=(attr(web,"AXTitle") or ""):match("^(.*) %- Claude Code$")
  if not title or title=="" then return nil,"无法确认当前会话名称" end
  return {app=app,win=win,web=web,url=url(web),title=title}
end
local function finish(message)
  if M.timer then M.timer:stop(); M.timer=nil end
  M.busy=false
  if message then hs.alert.show(message,2); log.i(message) end
end
local function controls(ctx)
  local panes=find(ctx.web,function(e) return attr(e,"AXDescription")=="Primary pane" end)
  local secondary=find(ctx.web,function(e) return attr(e,"AXDescription")=="Secondary pane" end)
  if #panes~=1 or #secondary>0 then return nil,"请先使用单会话视图，再归档" end
  local buttons=find(panes[1],function(e)
    return attr(e,"AXRole")=="AXPopUpButton" and attr(e,"AXDescription")=="More options for "..ctx.title
  end)
  if #buttons~=1 then return nil,"未能唯一定位当前会话菜单，未归档" end
  return {pane=panes[1],button=buttons[1]}
end
local function menus(root)
  return find(root,function(e) return attr(e,"AXRole")=="AXMenu" end)
end
local function closeMenu(app)
  -- Electron can report AXCancel success without dismissing the menu.
  -- Send Escape only while the same app is still in the foreground.
  if frontmost()==app then hs.eventtap.keyStroke({},"escape",0,app) end
end
local function sameContext(a,b)
  return a and b and a.app==b.app and a.win==b.win and a.web==b.web
    and a.url==b.url and a.title==b.title
end
local function finite(n)
  return type(n)=="number" and n==n and n>-math.huge and n<math.huge
end
local function clickVerifiedElement(button,ctx,commit)
  -- Chromium may acknowledge AXPress without acting. Recheck the exact target
  -- at its live position, including occlusion and context, before clicking.
  if attr(button,"AXEnabled")~=true then return false end
  local pos,size=attr(button,"AXPosition"),attr(button,"AXSize")
  if not pos or not size or not finite(pos.x) or not finite(pos.y)
    or not finite(size.w) or not finite(size.h) or size.w<=0 or size.h<=0 then return false end
  local point={x=pos.x+size.w/2,y=pos.y+size.h/2}
  if not finite(point.x) or not finite(point.y) then return false end
  local ok,hit=pcall(hs.axuielement.systemElementAtPosition,point)
  if not ok then return false end
  for _=1,12 do
    if not hit then break end
    if hit==button then
      if frontmost()~=ctx.app or not sameContext(current(ctx.app),ctx) then return false end
      if attr(button,"AXEnabled")~=true then return false end
      if not commit then return true end
      return pcall(hs.eventtap.leftClick,point,50000)
    end
    hit=attr(hit,"AXParent")
  end
  return false
end
local function changedView(ctx)
  local ax=hs.axuielement.applicationElement(ctx.app)
  local win=attr(ax,"AXFocusedWindow") or attr(ax,"AXMainWindow")
  if win~=ctx.win then return nil end
  local webs=find(win,function(e)
    local u=url(e)
    return attr(e,"AXRole")=="AXWebArea" and u and u:match("^https://claude%.ai/")
  end)
  if #webs~=1 or #menus(webs[1])>0 then return nil end
  local nextURL=url(webs[1])
  if nextURL~=ctx.url then return nextURL end
end
local function confirmationRequired(ctx)
  local ax=hs.axuielement.applicationElement(ctx.app)
  local win=attr(ax,"AXFocusedWindow") or attr(ax,"AXMainWindow")
  if win~=ctx.win then return false end
  local confirm,cancel=false,false
  for _,e in ipairs(find(win,function(e) return attr(e,"AXRole")=="AXButton" end)) do
    local title,desc=attr(e,"AXTitle"),attr(e,"AXDescription")
    if title=="Archive anyway" or desc=="Archive anyway" then confirm=true end
    if title=="Cancel" or desc=="Cancel" then cancel=true end
  end
  return confirm and cancel
end
function M.archive(dryRun,expected)
  if M.busy or hs.timer.secondsSinceEpoch()-M.lastPress<1 then return end
  local app=frontmost()
  if not app then hs.alert.show("请先切到 Claude 再归档",1.5); return end
  M.lastPress=hs.timer.secondsSinceEpoch(); M.busy=true
  if dryRun then M.lastDryRun=nil end
  local ctx,err=current(app)
  if not ctx then finish(err); return end
  if expected and not sameContext(ctx,expected) then finish("已取消归档：当前会话发生变化"); return end
  if confirmationRequired(ctx) then finish("Claude 正在等待归档确认，请先处理确认框"); return end
  if #menus(ctx.web)>0 then finish("请先关闭已打开的菜单，再按归档键"); return end
  local initial,controlErr=controls(ctx)
  if not initial then finish(controlErr); return end
  if not act(initial.button,"AXPress") then finish("无法打开当前会话菜单，未归档"); return end
  local started=hs.timer.secondsSinceEpoch()
  local retried=false
  local clickedAt,stableURL,stableCount=nil,nil,0
  local focusRequestedFor=nil
  M.timer=hs.timer.doEvery(0.12,function()
    if frontmost()~=app then
      if clickedAt then
        M.lastAttempt.status="unconfirmed"
        finish("已选择 Archive，但前台应用发生变化，未确认归档结果")
      else finish("已取消归档：前台应用发生变化") end
      return
    end
    if clickedAt then
      if confirmationRequired(ctx) then
        M.lastAttempt.status="confirmation-required"
        finish("Claude 要求确认归档，请先检查未提交改动，再处理确认框")
        return
      end
      local nextURL=changedView(ctx)
      if nextURL and nextURL==stableURL then stableCount=stableCount+1
      else stableURL=nextURL; stableCount=nextURL and 1 or 0 end
      if stableCount>=2 then
        M.lastArchive={url=ctx.url,title=ctx.title,time=hs.timer.secondsSinceEpoch(),confirmation="view-changed"}
        M.lastAttempt.status="view-changed"
        finish("已选择 Archive，Claude 已切换会话视图")
      elseif hs.timer.secondsSinceEpoch()-clickedAt>=RESULT_TIMEOUT then
        M.lastAttempt.status="unconfirmed"
        finish("已选择 Archive，但未确认完成；未重复执行，请检查会话状态")
      end
      return
    end
    local now=current(app)
    if not sameContext(now,ctx) then finish("已取消归档：当前会话发生变化"); return end
    local active,activeErr=controls(now)
    if not active then finish(activeErr); return end
    local openMenus=menus(now.web)
    -- Never select an Archive item belonging to a sidebar row or another pane.
    local ownedMenus=menus(active.button)
    if #ownedMenus==0 then
      for _,menu in ipairs(menus(active.pane)) do
        if attr(menu,"AXDescription")=="More options for "..ctx.title
          or attr(menu,"AXTitle")=="More options for "..ctx.title then
          ownedMenus[#ownedMenus+1]=menu
        end
      end
    end
    if #openMenus>1 or (#openMenus>0 and #ownedMenus~=1) then
      finish("菜单不属于当前会话或目标不唯一，未归档"); return
    end
    local candidates={}
    for _,menu in ipairs(ownedMenus) do
      for _,e in ipairs(find(menu,function(item)
        return attr(item,"AXRole")=="AXMenuItem" and (attr(item,"AXTitle")=="Archive" or attr(item,"AXDescription")=="Archive")
      end,200)) do
        if attr(e,"AXEnabled")==true then candidates[#candidates+1]={item=e,menu=menu} end
      end
    end
    if #candidates==1 then
      local target=candidates[1]
      -- Claude's native menu overlays are absent from AX hit testing: it
      -- returns the chat underneath. AXPress also silently fails on entries.
      -- Focus the exact owned entry, then independently confirm keyboard focus.
      local focused=attr(hs.axuielement.applicationElement(app),"AXFocusedUIElement")
      if focused~=target.item then
        if not focusRequestedFor then
          local ok,result=pcall(function() return target.item:setAttributeValue("AXFocused",true) end)
          if not ok or not result then finish("无法聚焦当前会话的 Archive，未归档"); return end
          focusRequestedFor=target.item
        elseif hs.timer.secondsSinceEpoch()-started>=MENU_TIMEOUT then
          finish("Archive 未获得键盘焦点，未归档")
        end
        return
      end
      if dryRun then
        log.i("Dry run: Archive keyboard focus verified for "..ctx.title)
        closeMenu(app)
        M.lastDryRun={url=ctx.url,title=ctx.title,found=true,focusVerified=true,context=ctx,retried=retried,elapsed=hs.timer.secondsSinceEpoch()-started}
        finish("归档入口验证成功，未执行归档")
      else
        if not sameContext(current(app),ctx) or frontmost()~=app
          or attr(target.item,"AXEnabled")~=true
          or attr(hs.axuielement.applicationElement(app),"AXFocusedUIElement")~=target.item then
          finish("归档前会话或菜单焦点已变化，未执行"); return
        end
        M.lastArchive=nil
        M.lastAttempt={url=ctx.url,title=ctx.title,time=hs.timer.secondsSinceEpoch(),status="attempting"}
        if pcall(hs.eventtap.keyStroke,{},"return",50000,app) then
          clickedAt=hs.timer.secondsSinceEpoch()
          M.lastAttempt.status="activated"
          log.i("Archive Return sent to verified menu item for "..ctx.title.."; awaiting view change")
        else
          M.lastAttempt.status="unconfirmed"
          finish("Archive 按键结果未知；未重复执行，请检查会话状态")
        end
      end
    elseif #candidates>1 then closeMenu(app); finish("归档目标不唯一，未执行")
    else
      local elapsed=hs.timer.secondsSinceEpoch()-started
      if elapsed>=MENU_TIMEOUT then
        if #ownedMenus>0 then closeMenu(app) end
        finish(#openMenus==0 and "Claude 会话菜单未打开，请重试归档键"
          or "当前会话菜单中没有可用的 Archive，未归档")
      elseif #openMenus==0 and not retried and elapsed>=RETRY_AFTER then
        -- Repeating the same AXPress did not fix physical-key failures.
        retried=true
        log.i("会话菜单尚未打开，尝试点击已核对的菜单按钮")
        if not clickVerifiedElement(active.button,ctx,true) then
          finish("无法安全点击会话菜单：按钮被遮挡或位置不可用，未归档")
        end
      end
    end
  end)
end
function M.bind(dryRun)
  if M.hotkey then M.hotkey:delete() end
  if M.triggerTimer then M.triggerTimer:stop(); M.triggerTimer=nil end
  -- Leave the Carbon hotkey event before asking Electron to open its menu.
  M.hotkey=hs.hotkey.bind({},"f19",nil,function()
    if M.busy or M.triggerTimer then return end
    local app=frontmost()
    if not app then hs.alert.show("请先切到 Claude 再归档",1.5); return end
    local ctx,err=current(app)
    if not ctx then finish(err); return end
    M.triggerTimer=hs.timer.doAfter(0.08,function()
      M.triggerTimer=nil
      if frontmost()~=app then finish("已取消归档：前台应用发生变化"); return end
      M.archive(dryRun==true,ctx)
    end)
  end)
end
function M.stop()
  if M.hotkey then M.hotkey:delete(); M.hotkey=nil end
  if M.timer then M.timer:stop(); M.timer=nil end
  if M.triggerTimer then M.triggerTimer:stop(); M.triggerTimer=nil end
  M.busy=false
end
return M
