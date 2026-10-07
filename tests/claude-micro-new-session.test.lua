-- Offline tests: never launches an application or sends input to a real device.
local source=arg[1] or "scripts/hammerspoon/claude-micro-new-session.lua"
local BUNDLE="com.anthropic.claudefordesktop"
local passed=0
local function expect(value,message) if not value then error(message or "expectation failed",2) end end
local function eq(actual,expected,message)
  expect(actual==expected,(message or "values differ")..": "..tostring(actual).." ~= "..tostring(expected))
end
local function element(attributes)
  return {attributes=attributes,attributeValue=function(self,key)
    expect(key~="AXChildren","must not traverse the chat tree")
    return self.attributes[key]
  end}
end
local function fixture()
  local f={now=100,timers={},bindings={},alerts={},logs={},launches=0,finds=0,selections=0,autoActivate=true}
  f.window=element({AXRole="AXWindow"})
  f.ax=element({AXFocusedWindow=f.window})
  f.app={}; f.other={}; f.third={}; f.front=f.app; f.available=true; f.menu={enabled=true}; f.selectResult=true
  local function path(value)
    eq(type(value),"table"); eq(#value,2); eq(value[1],"File"); eq(value[2],"New Session")
  end
  function f.app:findMenuItem(value)
    path(value); f.finds=f.finds+1
    if f.findHook then f.findHook() end
    return f.menu
  end
  function f.app:selectMenuItem(value)
    path(value); f.selections=f.selections+1
    if f.selectHook then f.selectHook() end
    return f.selectResult
  end
  local function after(delay,callback)
    local t={at=f.now+delay,callback=callback,stopped=false}
    function t:stop() self.stopped=true end
    f.timers[#f.timers+1]=t
    return t
  end
  function f.advance(seconds)
    local deadline=f.now+seconds
    for _=1,1000 do
      local nextTimer
      for _,t in ipairs(f.timers) do
        if not t.stopped and t.at<=deadline and (not nextTimer or t.at<nextTimer.at) then nextTimer=t end
      end
      if not nextTimer then f.now=deadline; return end
      f.now=nextTimer.at; nextTimer.stopped=true; nextTimer.callback()
    end
    error("timer loop did not terminate")
  end
  hs={
    logger={new=function() return {i=function(msg) f.logs[#f.logs+1]=msg end} end},
    alert={show=function(msg) f.alerts[#f.alerts+1]=msg end},
    timer={secondsSinceEpoch=function() return f.now end,doAfter=after},
    application={
      get=function(bundle) eq(bundle,BUNDLE); if f.available then return f.app end end,
      frontmostApplication=function() return f.front end,
      launchOrFocusByBundleID=function(bundle)
        eq(bundle,BUNDLE); f.launches=f.launches+1
        if f.launchFails then return false end
        if f.autoActivate then f.available=true; f.front=f.app end
        return true
      end,
    },
    axuielement={applicationElement=function(app) eq(app,f.app); return f.ax end},
    hotkey={bind=function(mods,key,pressed,released)
      local binding={mods=mods,key=key,pressed=pressed,released=released}
      function binding:delete() self.deleted=true end
      f.bindings[#f.bindings+1]=binding
      return binding
    end},
    eventtap=setmetatable({},{__index=function() error("must never type keys or click coordinates") end}),
  }
  f.module=dofile(source)
  return f
end
local function test(name,callback)
  local ok,err=pcall(callback)
  if not ok then io.stderr:write("FAIL "..name.."\n"..tostring(err).."\n"); os.exit(1) end
  passed=passed+1; print("PASS "..name)
end

test("F20 acts only on release and defers the native menu",function()
  local f=fixture(); f.module.bind(); local key=f.bindings[1]
  eq(key.key,"f20"); eq(#key.mods,0); eq(key.pressed,nil)
  key.released(); eq(f.selections,0); expect(f.module.busy)
  f.advance(0.04); eq(f.finds,1); eq(f.selections,1); eq(f.launches,0)
  eq(f.module.lastAttempt.status,"native-menu-selected"); expect(not f.module.busy); eq(f.module.timer,nil)
end)
test("another app activates Claude once before selecting the exact menu",function()
  local f=fixture(); f.front=f.other; f.module.startNew(); f.advance(0.2)
  eq(f.launches,1); eq(f.selections,1); eq(f.front,f.app)
end)
test("closed Claude can launch before choosing its menu",function()
  local f=fixture(); f.available=false; f.front=f.other; f.module.startNew(); f.advance(0.2)
  eq(f.launches,1); eq(f.selections,1)
end)
test("activation failure never selects a menu",function()
  local f=fixture(); f.front=f.other; f.launchFails=true; f.module.startNew(); f.advance(2)
  eq(f.launches,1); eq(f.finds,0); eq(f.selections,0); expect(not f.module.busy)
  eq(f.module.lastAttempt.status,"activation-failed")
end)
test("delayed activation polls without launching again",function()
  local f=fixture(); f.front=f.other; f.autoActivate=false; f.module.startNew(); f.advance(0.3)
  eq(f.launches,1); eq(f.selections,0); f.front=f.app; f.advance(0.1)
  eq(f.launches,1); eq(f.selections,1)
end)
test("activation timeout is bounded",function()
  local f=fixture(); f.front=f.other; f.autoActivate=false; f.module.startNew(); f.advance(3)
  eq(f.launches,1); eq(f.selections,0); eq(f.module.lastAttempt.status,"activation-timeout")
  expect(not f.module.busy); eq(f.module.timer,nil)
end)
test("user switching to a third app cancels activation",function()
  local f=fixture(); f.front=f.other; f.autoActivate=false; f.module.startNew(); f.advance(0.04)
  f.front=f.third; f.advance(0.1); eq(f.selections,0); eq(f.module.lastAttempt.status,"cancelled")
end)
test("stop cancels deferred activation and removes the hotkey",function()
  local f=fixture(); f.module.bind(); f.front=f.other; f.bindings[1].released()
  local stale=f.module.timer.callback; f.module.stop(); f.advance(1); stale()
  eq(f.launches,0); eq(f.selections,0); expect(f.bindings[1].deleted); expect(not f.module.busy)
end)
test("cancel stops pending work while keeping the hotkey",function()
  local f=fixture(); f.module.bind(); f.bindings[1].released(); f.module.cancel(); f.advance(1)
  eq(f.selections,0); expect(not f.bindings[1].deleted); expect(not f.module.busy)
  f.bindings[1].released(); f.advance(0.1); eq(f.selections,1)
end)
test("busy presses cannot queue duplicate sessions",function()
  local f=fixture(); expect(f.module.startNew()); expect(not f.module.startNew()); f.advance(0.1)
  eq(f.selections,1)
end)
test("debounce suppresses a rapid second completed press",function()
  local f=fixture(); f.module.startNew(); f.advance(0.1); expect(not f.module.startNew())
  f.advance(0.5); expect(f.module.startNew()); f.advance(0.1); eq(f.selections,2)
end)
test("canStart false blocks without activation or cancelling other work",function()
  local f=fixture(); local before=0; f.front=f.other
  f.module.bind(function() return false end,function() before=before+1 end)
  expect(not f.module.startNew()); f.advance(1); eq(f.launches,0); eq(before,0); eq(f.selections,0)
end)
test("canStart errors fail closed",function()
  local f=fixture(); f.module.bind(function() error("guard failed") end)
  expect(not f.module.startNew()); eq(f.module.busy,false)
end)
test("beforeStart cancels pending navigation once per accepted press",function()
  local f=fixture(); local before=0
  f.module.bind(function() return true end,function() before=before+1 end)
  f.module.startNew(); f.module.startNew(); f.advance(0.1); eq(before,1); eq(f.selections,1)
end)
test("beforeStart failure prevents activation",function()
  local f=fixture(); f.front=f.other; f.module.bind(nil,function() error("cannot prepare") end)
  expect(not f.module.startNew()); f.advance(0.1); eq(f.launches,0); eq(f.selections,0); expect(not f.module.busy)
end)
test("guard changing during activation cancels pending selection",function()
  local f=fixture(); local allow=true
  f.front=f.other; f.autoActivate=false; f.module.bind(function() return allow end)
  f.module.startNew(); f.advance(0.1); allow=false; f.front=f.app; f.advance(0.1)
  eq(f.selections,0); eq(f.module.lastAttempt.status,"cancelled")
end)
test("missing or disabled native menu is never selected",function()
  for _,menu in ipairs({false,{}, {enabled=false}, {enabled=1}}) do
    local f=fixture(); f.menu=menu; f.module.startNew(); f.advance(2)
    eq(f.selections,0); eq(f.finds,1); eq(f.module.lastAttempt.status,"unavailable")
  end
end)
test("window change while reading the menu cancels selection",function()
  local f=fixture(); f.findHook=function() f.ax.attributes.AXFocusedWindow=element({AXRole="AXWindow"}) end
  f.module.startNew(); f.advance(1); eq(f.selections,0); eq(f.module.lastAttempt.status,"cancelled")
end)
test("foreground change while reading the menu cancels selection",function()
  local f=fixture(); f.findHook=function() f.front=f.other end
  f.module.startNew(); f.advance(1); eq(f.selections,0)
end)
test("guard is rechecked immediately before selecting",function()
  local f=fixture(); local allow=true; f.module.bind(function() return allow end)
  f.findHook=function() allow=false end
  f.module.startNew(); f.advance(1); eq(f.selections,0)
end)
test("missing window and modal dialogs block without reading the chat tree",function()
  for _,attributes in ipairs({{}, {AXRole="AXSheet"}, {AXRole="AXWindow",AXModal=true}, {AXRole="AXWindow",AXSheets={element({})}}}) do
    local f=fixture(); f.window.attributes=attributes; f.module.startNew(); f.advance(0.1)
    eq(f.finds,0); eq(f.selections,0); eq(f.module.lastAttempt.status,"blocked")
  end
end)
test("a sheet appearing after the menu check prevents selection",function()
  local f=fixture(); f.findHook=function() f.window.attributes.AXSheets={element({})} end
  f.module.startNew(); f.advance(1); eq(f.selections,0)
end)
test("failed native action is never retried or replaced by a typed shortcut",function()
  local f=fixture(); f.selectResult=false; f.module.startNew(); f.advance(4)
  eq(f.selections,1); eq(f.module.lastAttempt.status,"unconfirmed"); expect(not f.module.busy)
end)
test("exception from native selection is not retried",function()
  local f=fixture(); f.selectHook=function() error("simulated native error") end
  f.module.startNew(); f.advance(4); eq(f.selections,1); eq(f.module.lastAttempt.status,"unconfirmed")
  expect(not f.module.busy); eq(f.module.timer,nil)
end)
test("exception from menu inspection clears busy state",function()
  local f=fixture(); f.findHook=function() error("simulated inspection error") end
  f.module.startNew(); f.advance(1); eq(f.selections,0); expect(not f.module.busy)
end)
test("rebinding cancels old work and uses only the new hooks",function()
  local f=fixture(); local oldBefore,newBefore=0,0
  f.module.bind(nil,function() oldBefore=oldBefore+1 end); f.module.startNew()
  f.module.bind(nil,function() newBefore=newBefore+1 end); f.advance(1)
  eq(f.selections,0); expect(f.bindings[1].deleted); f.bindings[2].released(); f.advance(0.1)
  eq(oldBefore,1); eq(newBefore,1); eq(f.selections,1)
end)

print(string.format("%d tests passed",passed))
