-- Offline AX/hotkey fixture shared by Archive and Fork regression tests.
return function(source, action)
  action = action or "Archive"
  local BUNDLE = "com.anthropic.claudefordesktop"

  local function expect(value, message)
    if not value then error(message or "expectation failed", 2) end
  end

  local function element(attributes, actions)
    local e = {attributes = attributes or {}, actions = actions or {}, reads = {}}
    e.attributes.AXChildren = e.attributes.AXChildren or {}
    function e:attributeValue(key)
      self.reads[key] = (self.reads[key] or 0) + 1
      return self.attributes[key]
    end
    function e:actionNames()
      local names = {}
      for name in pairs(self.actions) do names[#names + 1] = name end
      return names
    end
    function e:performAction(name)
      if not self.actions[name] then return nil end
      self.actions[name](self)
      return self
    end
    return e
  end

  local function children(parent, values)
    parent.attributes.AXChildren = values
    for _, child in ipairs(values) do child.attributes.AXParent = parent end
  end

  local function fixture(options)
    options = options or {}
    local f = {
      now = 100, timers = {}, messages = {}, logs = {},
      popupPresses = 0, archivePresses = 0, archiveClicks = 0, archiveReturns = 0, sidebarArchivePresses = 0,
      focusRequests = 0, focusReads = 0, confirmationClicks = 0,
      escapes = 0, cancelActions = 0, pendingOpen = false, clicks = 0, hitTests = 0,
    }
    local function schedule(delay, callback, repeating)
      local timer = {at = f.now + delay, callback = callback, interval = repeating and delay or nil, stopped = false}
      function timer:stop() self.stopped = true end
      function timer:start() self.stopped = false; self.at = f.now + delay; return self end
      f.timers[#f.timers + 1] = timer
      return timer
    end
    function f.advance(seconds)
      local deadline = f.now + seconds
      local iterations = 0
      while true do
        local nextTimer
        for _, timer in ipairs(f.timers) do
          if not timer.stopped and timer.at <= deadline and (not nextTimer or timer.at < nextTimer.at) then nextTimer = timer end
        end
        if not nextTimer then break end
        f.now = nextTimer.at
        if nextTimer.interval then nextTimer.at = nextTimer.at + nextTimer.interval else nextTimer.stopped = true end
        nextTimer.callback()
        iterations = iterations + 1
        expect(iterations < 10000, "timer loop did not terminate")
      end
      f.now = deadline
      expect(f.archivePresses == 0 and f.sidebarArchivePresses == 0, "Archive must never rely on AXPress")
      expect(f.archiveClicks == 0, "Archive must never use coordinate clicks")
      expect(f.confirmationClicks == 0, "a confirmation dialog must never be accepted automatically")
    end
    function f.after(delay, callback) return schedule(delay, callback, false) end

    f.app = {bundleID = function() return BUNDLE end}
    f.otherApp = {bundleID = function() return "example.other-app" end}
    f.frontmost = f.app
    f.window = element({AXRole = "AXWindow"})
    f.web = element({AXRole = "AXWebArea", AXURL = "https://claude.ai/epitaxy/session-current", AXTitle = "Current session - Claude Code"})
    f.primary = element({AXRole = "AXGroup", AXDescription = "Primary pane"})
    f.sidebar = element({AXRole = "AXGroup", AXDescription = "Sidebar"})
    f.appElement = element({AXFocusedWindow = f.window, AXMainWindow = f.window})
    f.editor = element({AXRole = "AXTextArea", AXDescription = "Message input"})
    f.appElement.attributes.AXFocusedUIElement = f.editor
    function f.appElement:attributeValue(key)
      if key == "AXFocusedUIElement" then
        f.focusReads = f.focusReads + 1
        if f.focusReads == 2 then
          if options.contextFinalChange then f.web.attributes.AXURL = "https://claude.ai/epitaxy/session-other" end
          if options.disabledFinalChange then f.archiveItem.attributes.AXEnabled = false end
        end
        if f.focusReads == 3 and options.focusFinalChange then self.attributes.AXFocusedUIElement = f.editor end
      end
      return self.attributes[key]
    end
    children(f.appElement, {f.window})
    children(f.window, {f.web})
    children(f.web, {f.primary, f.sidebar})

    local function makeMenu(items, counter)
      local menu = element({AXRole = "AXMenu"}, {
        AXCancel = function() f.cancelActions = f.cancelActions + 1 end,
      })
      local entries = {}
      for _, item in ipairs(items) do
        entries[#entries + 1] = element({
          AXRole = item.role or "AXMenuItem", AXTitle = item.title or action,
          AXDescription = item.description, AXEnabled = item.enabled ~= false,
          AXPosition = {x = 200, y = 200}, AXSize = {w = 160, h = 28},
        }, {AXPress = function() f[counter] = f[counter] + 1 end})
      end
      children(menu, entries)
      return menu
    end
    f.menu = makeMenu(options.items or {{title = action}}, "archivePresses")
    f.archiveItem = f.menu.attributes.AXChildren[1]
    function f.archiveItem:isAttributeSettable(key)
      return key == "AXFocused" and not options.focusCannotSet
    end
    function f.archiveItem:setAttributeValue(key, value)
      expect(key == "AXFocused" and value == true, "unexpected AX attribute mutation")
      f.focusRequests = f.focusRequests + 1
      if options.focusCannotSet then return nil, "attribute not settable" end
      if options.focusSetThrows then error("simulated focus failure") end
      if options.focusNoEffect then return self end
      if options.focusWrongArchive then
        f.appElement.attributes.AXFocusedUIElement = element({AXRole = "AXMenuItem", AXTitle = action, AXEnabled = true})
      elseif options.focusWrongEditor then f.appElement.attributes.AXFocusedUIElement = f.editor
      else f.appElement.attributes.AXFocusedUIElement = self end
      -- Real Claude exposes the focus via the app, while item.AXFocused stays nil.
      return self
    end
    f.popup = element({
      AXRole = "AXPopUpButton", AXDescription = "More options for Current session",
      AXPosition = {x = 100, y = 80}, AXSize = {w = 24, h = 24}, AXEnabled = true,
    }, {
      AXPress = function()
        f.popupPresses = f.popupPresses + 1
        if options.sidebarMenuOnPress then children(f.sidebarPopup, {f.sidebarMenu}); return end
        if options.noMenu or (options.firstPressNoEffect and f.popupPresses == 1) or f.pendingOpen then return end
        if options.openDelay then
          f.pendingOpen = true
          f.after(options.openDelay, function() children(f.popup, {f.menu}); f.pendingOpen = false end)
        else children(f.popup, {f.menu}) end
      end,
    })
    if options.position ~= nil then f.popup.attributes.AXPosition = options.position or nil end
    if options.size ~= nil then f.popup.attributes.AXSize = options.size or nil end
    if options.buttonEnabled ~= nil then f.popup.attributes.AXEnabled = options.buttonEnabled end
    f.hitTarget = f.popup
    if options.hitDescendant then
      f.hitTarget = element({AXRole = "AXImage", AXParent = f.popup})
    elseif options.obscured then
      f.hitTarget = element({AXRole = "AXButton", AXDescription = "Unrelated overlay"})
    end
    children(f.primary, {f.popup})
    if options.sidebarMenu or options.sidebarMenuOnPress then
      f.sidebarMenu = makeMenu({{title = action}}, "sidebarArchivePresses")
      f.sidebarPopup = element({AXRole = "AXPopUpButton", AXDescription = "More options for Current session"})
      if options.sidebarMenu then children(f.sidebarPopup, {f.sidebarMenu}) end
      children(f.sidebar, {f.sidebarPopup})
    end
    if options.secondaryPane then
      local secondary = element({AXRole = "AXGroup", AXDescription = "Secondary pane"})
      children(f.web, {f.primary, f.sidebar, secondary})
    end
    function f.completeArchive()
      children(f.popup, {})
      f.web.attributes.AXURL = options.nextURL or "https://claude.ai/epitaxy/session-next"
    end
    function f.showConfirmation()
      local accept = element({AXRole = "AXButton", AXTitle = "Archive anyway", AXEnabled = true}, {
        AXPress = function() f.confirmationClicks = f.confirmationClicks + 1 end,
      })
      local cancel = element({AXRole = "AXButton", AXTitle = "Cancel", AXEnabled = true}, {
        AXPress = function() f.confirmationClicks = f.confirmationClicks + 1 end,
      })
      f.confirmation = element({AXRole = "AXSheet", AXDescription = "Archive session with uncommitted changes?"})
      children(f.confirmation, {accept, cancel})
      children(f.window, {f.web, f.confirmation})
      children(f.popup, {})
    end

    _G.hs = {
      application = {frontmostApplication = function() return f.frontmost end},
      axuielement = {
        applicationElement = function(app) expect(app == f.app); return f.appElement end,
        systemElementAtPosition = function(point)
          f.hitTests = f.hitTests + 1
          expect(point.x == 112 and point.y == 92, "unexpected hit-test coordinates")
          if options.changeAppDuringHitTest then f.frontmost = f.otherApp end
          return f.hitTarget
        end,
      },
      timer = {
        secondsSinceEpoch = function() return f.now end,
        absoluteTime = function() return f.now * 1000000000 end,
        doEvery = function(interval, callback) return schedule(interval, callback, true) end,
        doAfter = function(delay, callback) return schedule(delay, callback, false) end,
      },
      logger = {new = function()
        local function record(message) f.logs[#f.logs + 1] = tostring(message) end
        return {i = record, w = record, e = record, d = record}
      end},
      alert = {show = function(message) f.messages[#f.messages + 1] = message end},
      eventtap = {
        keyStroke = function(modifiers, key, delay, app)
          expect(#modifiers == 0, "unexpected modifiers")
          expect(app == f.app, "synthetic key targeted another app")
          if key == "return" then
            f.archiveReturns = f.archiveReturns + 1
            expect(delay == 50000 and f.frontmost == f.app, "Return sent in the wrong context")
            expect(f.appElement.attributes.AXFocusedUIElement == f.archiveItem, "Return would activate an unverified element")
            if options.returnThrows then error("simulated partial key failure") end
            if options.confirmationAfterReturn then
              f.showConfirmation()
              if options.confirmationWithRoute then f.completeArchive() end
              return
            end
            if options.archiveNoEffect then return end
            if options.archiveCloseOnly then children(f.popup, {}); return end
            if options.archiveAXGap then
              children(f.popup, {}); f.web.attributes.AXURL = nil; return
            end
            if options.archiveOtherWindow then
              f.completeArchive()
              f.appElement.attributes.AXFocusedWindow = element({AXRole = "AXWindow"})
              return
            end
            if options.archiveDelay then f.after(options.archiveDelay, f.completeArchive)
            else f.completeArchive() end
            return
          end
          expect(key == "escape", "unexpected synthetic key")
          f.escapes = f.escapes + 1
          children(f.popup, {})
        end,
        leftClick = function(point, delay)
          expect(delay == 50000, "unexpected click timing")
          expect(f.frontmost == f.app, "clicked after focus changed")
          if point.x == 280 and point.y == 214 then f.archiveClicks = f.archiveClicks + 1; return end
          expect(point.x == 112 and point.y == 92, "unexpected click target")
          f.clicks = f.clicks + 1
          if options.sidebarMenuOnPress then children(f.sidebarPopup, {f.sidebarMenu}); return end
          if options.noMenu or f.pendingOpen then return end
          if options.openDelay then
            f.pendingOpen = true
            f.after(options.openDelay, function() children(f.popup, {f.menu}); f.pendingOpen = false end)
          else children(f.popup, {f.menu}) end
        end,
      },
      hotkey = {bind = function(modifiers, key, pressed, released)
        f.boundModifiers = modifiers
        f.boundKey, f.boundPressed, f.boundReleased = key, pressed, released
        return {delete = function() end}
      end},
    }
    f.module = assert(loadfile(source))()
    return f
  end

  return {fixture=fixture,expect=expect,element=element,children=children}
end
