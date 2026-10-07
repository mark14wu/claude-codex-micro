-- Verified actions on the current Claude Code session's own menu.
-- Each instance has independent timers, hotkeys, and result records.
local Factory = {}
function Factory.new(options)
  assert(options and options.action and options.method and options.resultField)
  local M = {busy=false, timer=nil, triggerTimer=nil, hotkey=nil, lastPress=0}
  local BUNDLE = "com.anthropic.claudefordesktop"
  local MENU_TIMEOUT = 4
  local RESULT_TIMEOUT = 3
  local action, verb = options.action, options.verb
  local log = hs.logger.new(options.logger, "info")
  local function message(text)
    -- Message templates use semantic placeholders, independent of the action.
    return (text:gsub("{action}", action):gsub("{verb}", verb))
  end
  local function attr(e, key)
    local ok, value = pcall(function() return e:attributeValue(key) end)
    return ok and value or nil
  end
  local function url(e)
    local u=attr(e,"AXURL")
    return type(u)=="table" and u.url or (type(u)=="string" and u or nil)
  end
  local function frontmost()
    local a=hs.application.frontmostApplication()
    return a and a:bundleID()==BUNDLE and a or nil
  end
  -- Read each node once per observation. AX reads cross a process boundary; the
  -- old separate context/pane/menu/confirmation searches revisited the same tree
  -- many times per timer tick. Records only live for this one observation.
  local function observe(app,details)
    local ax=hs.axuielement.applicationElement(app)
    local win=attr(ax,"AXFocusedWindow") or attr(ax,"AXMainWindow")
    if not win then return nil,"无法读取 Claude 当前窗口" end
    local state={win=win,nodes={},webs={},confirm=false,cancel=false,modal=false}
    local queue,seen,pos={{element=win}},{},1
    while pos<=#queue and pos<=1800 do
      local node=queue[pos]; pos=pos+1
      local e=node.element
      if e and not seen[e] then
        seen[e]=true
        node.role=attr(e,"AXRole")
        if details and options.rejectModal and (node.role=="AXSheet" or node.role=="AXDialog"
          or attr(e,"AXModal")==true) then state.modal=true end
        node.desc=details and attr(e,"AXDescription") or nil
        if node.role=="AXWebArea" then
          node.url=url(e); node.title=attr(e,"AXTitle")
          state.webs[#state.webs+1]=node
        elseif details and (node.role=="AXButton" or node.role=="AXMenu" or node.role=="AXMenuItem") then
          node.title=attr(e,"AXTitle")
          if node.role=="AXButton" then
            if node.title=="Archive anyway" or node.desc=="Archive anyway" then state.confirm=true end
            if node.title=="Cancel" or node.desc=="Cancel" then state.cancel=true end
          end
        end
        state.nodes[#state.nodes+1]=node
        if node.role~="AXMenuBar" and node.desc~="Chat messages"
          and (details or node.role~="AXWebArea") then
          for _,child in ipairs(attr(e,"AXChildren") or {}) do
            queue[#queue+1]={element=child,parent=node}
          end
        end
      end
    end
    if pos<=#queue then return nil,message("Claude 界面结构过大，无法完整核对{verb}目标") end
    return state
  end
  local function context(app,state)
    if not state then return nil,"无法读取 Claude 当前窗口" end
    local webs={}
    for _,node in ipairs(state.webs) do
      if node.url and node.url:match("^https://claude%.ai/epitaxy/[^/?#]+") then webs[#webs+1]=node end
    end
    if #webs~=1 then return nil,"请先打开一个 Claude Code 会话" end
    local web=webs[1]
    local title=(web.title or ""):match("^(.*) %- Claude Code$")
    if not title or title=="" then return nil,"无法确认当前会话名称" end
    return {app=app,win=state.win,web=web.element,url=web.url,title=title}
  end
  local function current(app)
    local state,err=observe(app,false)
    if not state then return nil,err end
    return context(app,state)
  end
  local function within(node,root)
    while node do
      if node.element==root then return true end
      node=node.parent
    end
    return false
  end
  local function find(state,root,predicate)
    local matches={}
    for _,node in ipairs(state.nodes) do
      if within(node,root) and predicate(node) then matches[#matches+1]=node.element end
    end
    return matches
  end
  local function finish(message)
    if M.timer then M.timer:stop(); M.timer=nil end
    M.busy=false
    if message then hs.alert.show(message,2); log.i(message) end
  end
  local function controls(ctx,state)
    local panes=find(state,ctx.web,function(node) return node.desc=="Primary pane" end)
    local secondary=find(state,ctx.web,function(node) return node.desc=="Secondary pane" end)
    if #panes~=1 or #secondary>0 then return nil,message("请先使用单会话视图，再{verb}") end
    local buttons=find(state,panes[1],function(node)
      return node.role=="AXPopUpButton" and node.desc=="More options for "..ctx.title
    end)
    if #buttons~=1 then return nil,message("未能唯一定位当前会话菜单，未{verb}") end
    return {pane=panes[1],button=buttons[1]}
  end
  local function menus(root,state)
    return find(state,root,function(node) return node.role=="AXMenu" end)
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
  local function changedView(ctx,state)
    if not state or state.win~=ctx.win then return nil end
    local webs={}
    for _,node in ipairs(state.webs) do
      if node.url and node.url:match("^https://claude%.ai/") then webs[#webs+1]=node end
    end
    if #webs~=1 or #menus(webs[1].element,state)>0 then return nil end
    local nextURL=webs[1].url
    if options.resultURLPattern and not nextURL:match(options.resultURLPattern) then return nil end
    if nextURL~=ctx.url then return nextURL end
  end
  local function confirmationRequired(ctx,state)
    return state and state.win==ctx.win and ((state.confirm and state.cancel) or state.modal)
  end
  M[options.method]=function(dryRun,expected,prepared)
    if M.canStart and not M.canStart() then return end
    if M.busy or hs.timer.secondsSinceEpoch()-M.lastPress<1 then return end
    if not prepared and M.beforeStart then M.beforeStart() end
    local app=frontmost()
    if not app then hs.alert.show(message("请先切到 Claude 再{verb}"),1.5); return end
    M.lastPress=hs.timer.secondsSinceEpoch(); M.busy=true
    if dryRun then M.lastDryRun=nil end
    local initialState,observeErr=observe(app,true)
    if not initialState then finish(observeErr); return end
    local ctx,err=context(app,initialState)
    if not ctx then finish(err); return end
    if expected and not sameContext(ctx,expected) then finish(message("已取消{verb}：当前会话发生变化")); return end
    if confirmationRequired(ctx,initialState) then finish("Claude 正在等待确认，请先处理确认框"); return end
    if #menus(ctx.web,initialState)>0 then finish(message("请先关闭已打开的菜单，再按{verb}键")); return end
    local initial,controlErr=controls(ctx,initialState)
    if not initial then finish(controlErr); return end
    -- AXPress acknowledges this popup without opening it on current Claude.
    -- Use its verified live hit target immediately; never toggle it a second time.
    if not clickVerifiedElement(initial.button,ctx,true) then
      finish(message("无法安全点击会话菜单：按钮被遮挡或位置不可用，未{verb}")); return
    end
    local started=hs.timer.secondsSinceEpoch()
    local clickedAt,stableURL,stableCount=nil,nil,0
    local focusRequestedFor=nil
    M.timer=hs.timer.doEvery(0.12,function()
      if frontmost()~=app then
        if clickedAt then
          M.lastAttempt.status="unconfirmed"
          finish(message("已选择 {action}，但前台应用发生变化，未确认{verb}结果"))
        else finish(message("已取消{verb}：前台应用发生变化")) end
        return
      end
      local state,stateErr=observe(app,true)
      if clickedAt then
        if confirmationRequired(ctx,state) then
          M.lastAttempt.status="confirmation-required"
          finish(options.confirmationMessage)
          return
        end
        local nextURL=changedView(ctx,state)
        if nextURL and nextURL==stableURL then stableCount=stableCount+1
        else stableURL=nextURL; stableCount=nextURL and 1 or 0 end
        if stableCount>=2 then
          M[options.resultField]={url=ctx.url,nextURL=stableURL,title=ctx.title,
            time=hs.timer.secondsSinceEpoch(),confirmation="view-changed"}
          M.lastAttempt.status="view-changed"
          finish(message("已选择 {action}，Claude 已切换会话视图"))
        elseif hs.timer.secondsSinceEpoch()-clickedAt>=RESULT_TIMEOUT then
          M.lastAttempt.status="unconfirmed"
          finish(message("已选择 {action}，但未确认完成；未重复执行，请检查会话状态"))
        end
        return
      end
      if not state then finish(stateErr); return end
      local now=context(app,state)
      if not sameContext(now,ctx) then finish(message("已取消{verb}：当前会话发生变化")); return end
      if confirmationRequired(ctx,state) then finish("Claude 正在等待确认，请先处理确认框"); return end
      local active,activeErr=controls(now,state)
      if not active then finish(activeErr); return end
      local openMenus=menus(now.web,state)
      -- Never select an item belonging to a sidebar row or another pane.
      local ownedMenus=menus(active.button,state)
      if #ownedMenus==0 then
        for _,menu in ipairs(menus(active.pane,state)) do
          if attr(menu,"AXDescription")=="More options for "..ctx.title
            or attr(menu,"AXTitle")=="More options for "..ctx.title then
            ownedMenus[#ownedMenus+1]=menu
          end
        end
      end
      if #openMenus>1 or (#openMenus>0 and #ownedMenus~=1) then
        finish(message("菜单不属于当前会话或目标不唯一，未{verb}")); return
      end
      local candidates={}
      for _,menu in ipairs(ownedMenus) do
        for _,e in ipairs(find(state,menu,function(item)
          return item.role=="AXMenuItem" and (item.title==action or item.desc==action)
        end)) do
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
            if not ok or not result then finish(message("无法聚焦当前会话的 {action}，未{verb}")); return end
            focusRequestedFor=target.item
          elseif hs.timer.secondsSinceEpoch()-started>=MENU_TIMEOUT then
            finish(message("{action} 未获得键盘焦点，未{verb}"))
          end
          return
        end
        if dryRun then
          log.i(message("Dry run: {action} keyboard focus verified for ")..ctx.title)
          closeMenu(app)
          M.lastDryRun={url=ctx.url,title=ctx.title,found=true,focusVerified=true,context=ctx,retried=false,elapsed=hs.timer.secondsSinceEpoch()-started}
          finish(message("{verb}入口验证成功，未执行{verb}"))
        else
          if not sameContext(current(app),ctx) or frontmost()~=app
            or attr(target.item,"AXEnabled")~=true
            or attr(hs.axuielement.applicationElement(app),"AXFocusedUIElement")~=target.item then
            finish(message("{verb}前会话或菜单焦点已变化，未执行")); return
          end
          M[options.resultField]=nil
          M.lastAttempt={url=ctx.url,title=ctx.title,time=hs.timer.secondsSinceEpoch(),status="attempting"}
          if pcall(hs.eventtap.keyStroke,{},"return",50000,app) then
            clickedAt=hs.timer.secondsSinceEpoch()
            M.lastAttempt.status="activated"
            log.i(message("{action} Return sent to verified menu item for ")..ctx.title.."; awaiting view change")
          else
            M.lastAttempt.status="unconfirmed"
            finish(message("{action} 按键结果未知；未重复执行，请检查会话状态"))
          end
        end
      elseif #candidates>1 then closeMenu(app); finish(message("{verb}目标不唯一，未执行"))
      else
        local elapsed=hs.timer.secondsSinceEpoch()-started
        if elapsed>=MENU_TIMEOUT then
          if #ownedMenus>0 then closeMenu(app) end
          finish(#openMenus==0 and message("Claude 会话菜单未打开，请重试{verb}键")
            or message("当前会话菜单中没有可用的 {action}，未{verb}"))
        end
      end
    end)
  end
  function M.bind(dryRun,canStart,beforeStart)
    M.canStart,M.beforeStart=canStart,beforeStart
    if M.hotkey then M.hotkey:delete() end
    if M.triggerTimer then M.triggerTimer:stop(); M.triggerTimer=nil end
    -- Leave the Carbon hotkey event before asking Electron to open its menu.
    M.hotkey=hs.hotkey.bind(options.modifiers,options.key,nil,function()
      if M.busy or M.triggerTimer or (M.canStart and not M.canStart()) then return end
      if M.beforeStart then M.beforeStart() end
      local app=frontmost()
      if not app then hs.alert.show(message("请先切到 Claude 再{verb}"),1.5); return end
      local ctx,err=current(app)
      if not ctx then finish(err); return end
      M.triggerTimer=hs.timer.doAfter(0.08,function()
        M.triggerTimer=nil
        if frontmost()~=app then finish(message("已取消{verb}：前台应用发生变化")); return end
        M[options.method](dryRun==true,ctx,true)
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
end
return Factory
