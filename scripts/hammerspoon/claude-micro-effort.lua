-- The wheel uses accessibility actions, never Escape (which can open Rewind).
local M={hotkeys={},queue={},busy=false}
local accessibility=require("claude-micro-accessibility")
local BUNDLE="com.anthropic.claudefordesktop"
local function attr(e,key)
  local ok,value=pcall(function() return e:attributeValue(key) end)
  if ok then return value end
end
local function label(e)
  return attr(e,"AXDescription") or attr(e,"AXTitle") or ""
end
local function controls(win)
  local buttons,sliders,seen={},{},{}
  local count,blocked=0,false
  local function visit(e,depth)
    if not e or seen[e] then return end
    if depth>40 or count>=2400 then blocked=true; return end
    seen[e]=true; count=count+1
    local role,name=attr(e,"AXRole"),label(e)
    if role=="AXSheet" or role=="AXDialog" or role=="AXMenu" then blocked=true; return end
    if role=="AXPopUpButton" and name:match("^Effort:") then buttons[#buttons+1]=e end
    if role=="AXSlider" and name=="Effort" then sliders[#sliders+1]=e end
    if name=="Chat messages" or name=="Sidebar" or role=="AXMenuBar" then return end
    for _,child in ipairs(attr(e,"AXChildren") or {}) do visit(child,depth+1) end
  end
  visit(win,0)
  return buttons,sliders,blocked
end
local function finite(n) return type(n)=="number" and n==n and math.abs(n)<math.huge end
local function clickPopup(button,app,ax,win)
  local pos,size=attr(button,"AXPosition"),attr(button,"AXSize")
  if attr(button,"AXEnabled")~=true or not pos or not size or not finite(pos.x) or not finite(pos.y)
    or not finite(size.w) or not finite(size.h) or size.w<=0 or size.h<=0 then return false end
  local point={x=pos.x+size.w/2,y=pos.y+size.h/2}
  local hit=hs.axuielement.systemElementAtPosition(point)
  for _=1,12 do
    if hit==button then
      if hs.application.frontmostApplication()~=app or
        (attr(ax,"AXFocusedWindow") or attr(ax,"AXMainWindow"))~=win then return false end
      hs.eventtap.leftClick(point,50000)
      return true
    end
    hit=attr(hit,"AXParent")
    if not hit then break end
  end
  return false
end
function M.cancel()
  if M.timer then M.timer:stop(); M.timer=nil end
  M.queue={}; M.busy=false
end
local function finish(status)
  M.lastStatus=status
  M.cancel()
  if status=="unavailable" or status=="unconfirmed" then
    hs.alert.show("Claude 推理强度未能调整，请检查强度菜单",1.5)
  end
end
function M.step(direction)
  if direction~=1 and direction~=-1 then return false end
  local app=hs.application.get(BUNDLE)
  if not app or hs.application.frontmostApplication()~=app or (M.canStart and not M.canStart()) then return false end
  if #M.queue>=20 then return false end
  M.queue[#M.queue+1]=direction
  if M.busy then return true end
  M.busy=true
  local ax=accessibility.applicationElement(app)
  local win=attr(ax,"AXFocusedWindow") or attr(ax,"AXMainWindow")
  local popup,opened,waiting,focusRequested
  local deadline=hs.timer.secondsSinceEpoch()+2.5
  local function tick()
    M.timer=nil
    local ok=pcall(function()
      if not M.busy then return end
      if hs.application.frontmostApplication()~=app or (M.canStart and not M.canStart())
        or (attr(ax,"AXFocusedWindow") or attr(ax,"AXMainWindow"))~=win then finish("cancelled"); return end
      if not win or attr(win,"AXModal")==true then finish("unavailable"); return end
      local buttons,sliders,blocked=controls(win)
      if blocked or #buttons>1 or #sliders>1 then finish("unavailable"); return end
      if popup and (#buttons~=1 or buttons[1]~=popup) then finish("cancelled"); return end
      if #buttons==1 then popup=buttons[1] end
      local now=hs.timer.secondsSinceEpoch()
      if #sliders==1 and popup then
        local slider=sliders[1]
        local value=tonumber(attr(slider,"AXValue"))
        if not value then finish("unavailable"); return end
        if waiting then
          if (value-waiting.value)*waiting.direction>0 then
            waiting=nil; table.remove(M.queue,1); M.lastStatus="changed"
          elseif now>=deadline then finish("unconfirmed"); return end
        elseif #M.queue>0 then
          local dir=M.queue[1]
          local bound=tonumber(attr(slider,dir==1 and "AXMaxValue" or "AXMinValue"))
          if bound and ((dir==1 and value>=bound) or (dir==-1 and value<=bound)) then
            table.remove(M.queue,1); M.lastStatus="at-boundary"
          else
            -- Chromium can acknowledge AXIncrement without changing its slider.
            -- Only send an arrow after independently verifying exact focus.
            if attr(ax,"AXFocusedUIElement")~=slider then
              if focusRequested~=slider then
                focusRequested=slider; deadline=now+0.8
                if not slider:setAttributeValue("AXFocused",true) then finish("unavailable"); return end
              elseif now>=deadline then finish("unavailable"); return end
            else
              if hs.application.frontmostApplication()~=app then finish("cancelled"); return end
              waiting={value=value,direction=dir}; deadline=now+0.8
              hs.eventtap.keyStroke({},dir==1 and "right" or "left",50000,app)
            end
          end
        end
        if #M.queue==0 then M.busy=false; return end
      elseif popup and not opened then
        opened=true
        if not clickPopup(popup,app,ax,win) then finish("unavailable"); return end
      elseif now>=deadline then finish("unavailable"); return end
      M.timer=hs.timer.doAfter(0.04,tick)
    end)
    if not ok then finish("unconfirmed") end
  end
  M.timer=hs.timer.doAfter(0.03,tick)
  return true
end
function M.stop()
  M.cancel()
  for _,key in ipairs(M.hotkeys) do key:delete() end
  M.hotkeys={}; M.canStart=nil
end
function M.bind(canStart)
  M.stop(); M.canStart=canStart
  for _,entry in ipairs({{"f18",1},{"f19",-1}}) do
    local key,direction=entry[1],entry[2]
    M.hotkeys[#M.hotkeys+1]=hs.hotkey.bind({"ctrl"},key,nil,function() M.step(direction) end)
  end
  return M
end
return M
