-- Offline accessibility fixture: no applications or keystrokes.
local function eq(a,b) assert(a==b,tostring(a)..' ~= '..tostring(b)) end
local function fixture()
  local f={now=0,timers={},presses=0,steps=0,bindings={}}
  local function element(attrs,actions)
    return {attributeValue=function(_,k)return attrs[k] end,actionNames=function()return actions or {} end,attrs=attrs}
  end
  f.slider=element({AXRole='AXSlider',AXDescription='Effort',AXValue=3,AXMinValue=1,AXMaxValue=5},{'AXIncrement','AXDecrement'})
  f.popup=element({AXRole='AXPopUpButton',AXDescription='Effort: High',AXEnabled=true,AXPosition={x=10,y=10},AXSize={w=20,h=20}},{'AXPress'})
  f.win=element({AXRole='AXWindow',AXChildren={f.popup}})
  f.ax=element({AXFocusedWindow=f.win}); f.app={}; f.front=f.app
  function f.popup:performAction(name)
    eq(name,'AXPress'); f.presses=f.presses+1
    if not f.noOpen then f.win.attrs.AXChildren={f.popup,f.slider} end
    return self
  end
  function f.slider:performAction(name)
    assert(name=='AXIncrement' or name=='AXDecrement');f.steps=f.steps+1
    if not f.noChange then self.attrs.AXValue=self.attrs.AXValue+(name=='AXIncrement' and 1 or -1) end
    return self
  end
  function f.slider:setAttributeValue(key,value) eq(key,'AXFocused');eq(value,true);if not f.noFocus then f.ax.attrs.AXFocusedUIElement=self end;return self end
  hs={axuielement={systemElementAtPosition=function()return f.obscured and {} or f.popup end},eventtap={leftClick=function()f.popup:performAction('AXPress')end,keyStroke=function(mod,key,delay,app)eq(#mod,0);eq(app,f.app);assert(key=='right' or key=='left');f.slider:performAction(key=='right' and 'AXIncrement' or 'AXDecrement')end},application={get=function()return f.app end,frontmostApplication=function()return f.front end},
    alert={show=function()end},timer={secondsSinceEpoch=function()return f.now end,doAfter=function(delay,cb)
      local t={at=f.now+delay,cb=cb};function t:stop()self.stopped=true end
      f.timers[#f.timers+1]=t;return t
    end},hotkey={bind=function(mod,key,_,cb)
      eq(mod[1],'ctrl');f.bindings[key]=cb;return {delete=function()end}
    end}}
  package.loaded['claude-micro-accessibility']={applicationElement=function()return f.ax end}
  f.m=dofile('scripts/hammerspoon/claude-micro-effort.lua')
  function f.run()
    for _=1,300 do
      local t=table.remove(f.timers,1);if not t then return end
      if not t.stopped then f.now=t.at;t.cb() end
    end
    error('timer did not finish')
  end
  return f
end
local f=fixture();f.m.bind();f.bindings.f18();f.run();eq(f.slider.attrs.AXValue,4);eq(f.m.lastStatus,'changed');eq(f.presses,1)
f.bindings.f19();f.run();eq(f.slider.attrs.AXValue,3);eq(f.presses,1)
f=fixture();f.m.step(1);f.m.step(1);f.m.step(-1);f.run();eq(f.slider.attrs.AXValue,4);eq(f.steps,3)
f=fixture();f.slider.attrs.AXValue=5;f.m.step(1);f.run();eq(f.steps,0);eq(f.m.lastStatus,'at-boundary')
f=fixture();f.front={};eq(f.m.step(1),false);eq(f.presses,0)
f=fixture();f.m.step(1);f.front={};f.run();eq(f.presses,0);eq(f.m.lastStatus,'cancelled')
f=fixture();f.win.attrs.AXChildren={f.popup,{attributeValue=function(_,k)if k=='AXRole' then return 'AXDialog' end end}};f.m.step(1);f.run();eq(f.presses,0)
f=fixture();f.win.attrs.AXChildren={f.popup,f.popup, {attributeValue=function(_,k)if k=='AXRole' then return 'AXPopUpButton' elseif k=='AXDescription' then return 'Effort: Low' end end}};f.m.step(1);f.run();eq(f.presses,0)
f=fixture();f.noOpen=true;f.m.step(1);f.run();eq(f.presses,1);eq(f.steps,0);eq(f.m.lastStatus,'unavailable')
f=fixture();f.noChange=true;f.m.step(1);f.run();eq(f.steps,1);eq(f.m.lastStatus,'unconfirmed')
f=fixture();f.m.step(1);f.m.cancel();f.run();eq(f.presses,0)
f=fixture();f.m.bind(function()return false end);eq(f.m.step(1),false)
print('PASS: effort directions, queue, boundaries, focus, dialogs, ambiguity, timeouts, cancellation and gating')

f=fixture();f.noFocus=true;f.m.step(1);f.run();eq(f.steps,0);eq(f.m.lastStatus,'unavailable')
f=fixture();f.obscured=true;f.m.step(1);f.run();eq(f.presses,0);eq(f.steps,0)
