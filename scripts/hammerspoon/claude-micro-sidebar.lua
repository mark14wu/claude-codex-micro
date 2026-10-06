-- Resolve F13-F18 from the first six visible sessions across Claude projects.
-- Project and session order follow the sidebar, never URLs saved at setup time.
local M = {timer=nil}
local BUNDLE = "com.anthropic.claudefordesktop"
local log = hs.logger.new("ClaudeSlots","info")
local function attr(e,key)
  local ok,value=pcall(function() return e:attributeValue(key) end)
  if ok then return value end
end
local function label(e)
  local desc=attr(e,"AXDescription")
  if type(desc)=="string" and desc~="" then return desc end
  local title=attr(e,"AXTitle")
  return type(title)=="string" and title or ""
end
local function walk(root,predicate)
  local found,seen,count={}, {},0
  local function visit(e,depth)
    if not e or seen[e] or depth>40 or count>=2400 then return end
    seen[e]=true; count=count+1
    if predicate(e) then found[#found+1]=e end
    if label(e)=="Chat messages" or attr(e,"AXRole")=="AXMenuBar" then return end
    for _,child in ipairs(attr(e,"AXChildren") or {}) do visit(child,depth+1) end
  end
  visit(root,0)
  return found
end
local function act(e,action)
  local ok,result=pcall(function()
    for _,name in ipairs(e:actionNames() or {}) do
      if name==action then return e:performAction(action) end
    end
  end)
  return ok and result~=nil and result~=false
end
local function window(app)
  local ax=hs.axuielement.applicationElement(app)
  return attr(ax,"AXFocusedWindow") or attr(ax,"AXMainWindow")
end
local function frontmost(app)
  return hs.application.frontmostApplication()==app
end
local function obstructed(win)
  return #walk(win,function(e)
    local role=attr(e,"AXRole")
    return role=="AXSheet" or role=="AXDialog" or role=="AXMenu"
      or (role=="AXButton" and label(e)=="Archive anyway")
  end)>0
end
local function projectRows(anchor,limit)
  local project=label(anchor):match("^New session in (.+)$")
  local group=attr(anchor,"AXParent")
  local headers={}
  for _,e in ipairs(attr(group,"AXChildren") or {}) do
    if attr(e,"AXRole")=="AXButton" and label(e)==project then headers[#headers+1]=e end
  end
  if #headers~=1 then return nil,"无法确认 project 的边界" end
  local rows,seenRows={},{}
  for _,menu in ipairs(walk(group,function(e)
    return attr(e,"AXRole")=="AXPopUpButton" and label(e):match("^More options for .+")
  end)) do
    local row=attr(menu,"AXParent")
    local buttons={}
    -- The popup lives inside an extra AXGroup in the real Electron tree;
    -- macOS's rendered accessibility outline hides that wrapper.
    for _=1,6 do
      if not row or row==group then break end
      buttons=walk(row,function(e) return attr(e,"AXRole")=="AXButton" end)
      if #buttons>0 then break end
      row=attr(row,"AXParent")
    end
    if not row or row==group or #buttons~=1 then return nil,"侧栏会话行无法唯一识别，未切换" end
    local rowMenus=walk(row,function(e)
      return attr(e,"AXRole")=="AXPopUpButton" and label(e):match("^More options for .+")
    end)
    if #rowMenus~=1 or rowMenus[1]~=menu then return nil,"侧栏会话行边界不明确，未切换" end
    if not seenRows[row] then
      seenRows[row]=true
      local title=label(menu):match("^More options for (.+)$")
      rows[#rows+1]={row=row,button=buttons[1],menu=menu,title=title,project=project,group=group}
      if #rows>=limit then break end
    end
  end
  return {group=group,header=headers[1],project=project,rows=rows}
end
function M.readSidebar(sidebar)
  local anchors=walk(sidebar,function(e)
    return attr(e,"AXRole")=="AXButton" and label(e):match("^New session in .+")
  end)
  if #anchors==0 then return nil,"未找到 Claude 侧栏的 project，请先打开 Code 视图" end
  local result={sidebar=sidebar,projects={},rows={}}
  local seenGroups={}
  for _,anchor in ipairs(anchors) do
    local group=attr(anchor,"AXParent")
    if not seenGroups[group] then
      local project,err=projectRows(anchor,6-#result.rows)
      if not project then return nil,err end
      seenGroups[group]=true
      result.projects[#result.projects+1]=project
      for _,row in ipairs(project.rows) do result.rows[#result.rows+1]=row end
      if #result.rows>=6 then break end
    end
  end
  return result
end
function M.snapshot(app)
  app=app or hs.application.get(BUNDLE)
  if not app then return nil,"Claude 尚未启动" end
  local win=window(app)
  if not win then return nil,"正在等待 Claude 窗口" end
  if obstructed(win) then return nil,"请先关闭 Claude 的菜单或确认框，再切换会话" end
  local sidebars=walk(win,function(e) return label(e)=="Sidebar" end)
  if #sidebars~=1 then return nil,"请先展开 Claude 侧栏" end
  local snapshot,err=M.readSidebar(sidebars[1])
  if not snapshot then return nil,err end
  snapshot.app=app; snapshot.window=win
  return snapshot
end
local function finish(message)
  if M.timer then M.timer:stop(); M.timer=nil end
  if message then hs.alert.show(message,2); log.i(message) end
end
local function finite(n)
  return type(n)=="number" and n==n and n>-math.huge and n<math.huge
end
local function clickRow(ctx,target)
  if not frontmost(ctx.app) or window(ctx.app)~=ctx.window or obstructed(ctx.window) then return false end
  if attr(target.button,"AXEnabled")~=true then return false end
  local pos,size=attr(target.button,"AXPosition"),attr(target.button,"AXSize")
  if not pos or not size or not finite(pos.x) or not finite(pos.y)
    or not finite(size.w) or not finite(size.h) or size.w<=0 or size.h<=0 then return false end
  local point={x=pos.x+size.w/2,y=pos.y+size.h/2}
  if not finite(point.x) or not finite(point.y) then return false end
  local ok,hit=pcall(hs.axuielement.systemElementAtPosition,point)
  if not ok then return false end
  for _=1,12 do
    if not hit then break end
    if hit==target.button then
      if not frontmost(ctx.app) or window(ctx.app)~=ctx.window then return false end
      -- Confirm that this exact row is still in the captured project; never
      -- resolve the slot again after an action may have reordered the list.
      local present=walk(target.group,function(e) return e==target.button end)
      local projectPresent=walk(ctx.sidebar,function(e) return e==target.group end)
      if #present~=1 or #projectPresent~=1 or label(target.menu)~="More options for "..target.title then return false end
      return pcall(hs.eventtap.leftClick,point,50000)
    end
    hit=attr(hit,"AXParent")
  end
  return false
end
local function currentTitle(win)
  local webs=walk(win,function(e)
    return attr(e,"AXRole")=="AXWebArea" and type(attr(e,"AXTitle"))=="string"
      and attr(e,"AXTitle"):match(" %- Claude Code$")
  end)
  if #webs~=1 then return nil end
  return attr(webs[1],"AXTitle"):match("^(.*) %- Claude Code$")
end
function M.select(slot)
  if type(slot)~="number" or slot%1~=0 or slot<1 or slot>6 then return end
  finish()
  M.lastSelection=nil
  hs.application.launchOrFocusByBundleID(BUNDLE)
  local start=hs.timer.secondsSinceEpoch()
  local ctx,target,clickedAt=nil,nil,nil
  M.timer=hs.timer.doEvery(0.12,function()
    local app=hs.application.get(BUNDLE)
    if not app or not frontmost(app) then
      if ctx or hs.timer.secondsSinceEpoch()-start>2 then finish("未切换会话：Claude 不在前台") end
      return
    end
    if not ctx then
      local err
      ctx,err=M.snapshot(app)
      if not ctx then
        if hs.timer.secondsSinceEpoch()-start>2 then finish(err) end
        return
      end
      target=ctx.rows[slot]
      if not target then finish("侧栏各 project 当前合计没有第 "..slot.." 个会话；请检查项目是否展开"); return end
      if not clickRow(ctx,target) then
        -- Off-screen rows may expose AXScrollToVisible. Do not click a point
        -- occupied by another control, or re-resolve a different session.
        if act(target.button,"AXScrollToVisible") then return end
        finish("无法点击第 "..slot.." 个会话，请确保对应 project 的会话列表可见"); return
      end
      clickedAt=hs.timer.secondsSinceEpoch()
      M.lastSelection={slot=slot,project=target.project,title=target.title,status="clicked"}
      return
    end
    if window(app)~=ctx.window then finish("Claude 窗口已变化，停止切换"); return end
    if not clickedAt then
      if not clickRow(ctx,target) then finish("会话行不可见或被遮挡，未切换"); return end
      clickedAt=hs.timer.secondsSinceEpoch()
      M.lastSelection={slot=slot,project=target.project,title=target.title,status="clicked"}
      return
    end
    if currentTitle(ctx.window)==target.title then
      M.lastSelection.status="view-matched"
      log.i("Slot "..slot.." → "..target.project.." / "..target.title)
      finish()
    elseif hs.timer.secondsSinceEpoch()-clickedAt>2 then
      M.lastSelection.status="unconfirmed"
      finish("已点击会话，但尚未确认页面切换，请检查 Claude")
    end
  end)
end
function M.stop() finish() end
return M
