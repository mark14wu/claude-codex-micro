-- Offline regression tests: these mocks never connect to Claude or press real keys.
-- Run from the repository root with: lua tests/claude-micro-archive.test.lua
local source = arg[1] or "scripts/hammerspoon/claude-micro-archive.lua"
local BUNDLE = "com.anthropic.claudefordesktop"
local passed = 0

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
        AXRole = item.role or "AXMenuItem", AXTitle = item.title or "Archive",
        AXDescription = item.description, AXEnabled = item.enabled ~= false,
        AXPosition = {x = 200, y = 200}, AXSize = {w = 160, h = 28},
      }, {AXPress = function() f[counter] = f[counter] + 1 end})
    end
    children(menu, entries)
    return menu
  end
  f.menu = makeMenu(options.items or {{title = "Archive"}}, "archivePresses")
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
      f.appElement.attributes.AXFocusedUIElement = element({AXRole = "AXMenuItem", AXTitle = "Archive", AXEnabled = true})
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
    f.sidebarMenu = makeMenu({{title = "Archive"}}, "sidebarArchivePresses")
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
    hotkey = {bind = function(_, key, pressed, released)
      f.boundKey, f.boundPressed, f.boundReleased = key, pressed, released
      return {delete = function() end}
    end},
  }
  f.module = assert(loadfile(source))()
  return f
end

local function test(name, run)
  local ok, err = pcall(run)
  if not ok then io.stderr:write("FAIL ", name, ": ", tostring(err), "\n"); os.exit(1) end
  passed = passed + 1
  print("PASS " .. name)
end

test("archives the unique enabled entry owned by the current popup", function()
  local f = fixture()
  f.module.archive(false); f.advance(0.5)
  expect(f.popupPresses == 0 and f.clicks == 1 and f.archiveReturns == 1)
  expect(not f.module.busy and f.module.lastArchive ~= nil)
  expect(f.module.lastArchive.confirmation == "view-changed" and f.module.lastAttempt.status == "view-changed")
end)

test("waits for a menu delayed two seconds", function()
  local f = fixture({openDelay = 2})
  f.module.archive(false); f.advance(1.4)
  expect(f.archiveReturns == 0)
  f.advance(1.1)
  expect(f.archiveReturns == 1 and not f.module.busy)
end)

test("opens immediately with one verified click instead of waiting for ineffective AXPress", function()
  local f = fixture({firstPressNoEffect = true})
  f.module.archive(false)
  expect(f.popupPresses == 0 and f.clicks == 1 and f.archiveReturns == 0)
  f.advance(0.5)
  expect(f.popupPresses == 0 and f.clicks == 1 and f.archiveReturns == 1 and not f.module.busy)
end)

test("disabled Archive is never pressed", function()
  local f = fixture({items = {{title = "Archive", enabled = false}}})
  f.module.archive(false); f.advance(4.5)
  expect(f.archiveReturns == 0 and not f.module.busy)
  expect(f.popupPresses == 0 and f.clicks == 1, "an already open menu must not be toggled by retry")
  expect(f.messages[#f.messages]:find("没有可用的 Archive", 1, true) ~= nil)
end)

test("duplicate Archive entries are refused", function()
  local f = fixture({items = {{title = "Archive"}, {title = "Archive"}}})
  f.module.archive(false); f.advance(4.5)
  expect(f.archiveReturns == 0 and not f.module.busy)
end)

test("same-title sidebar menu cannot supply the Archive target", function()
  local f = fixture({sidebarMenu = true, items = {{title = "Rename"}}})
  f.module.archive(false); f.advance(4.5)
  expect(f.archiveReturns == 0 and f.sidebarArchivePresses == 0 and not f.module.busy)
end)

test("a sidebar menu opened during the operation cannot supply Archive", function()
  local f = fixture({sidebarMenuOnPress = true})
  f.module.archive(false); f.advance(0.5)
  expect(f.popupPresses == 0 and f.clicks == 1 and f.archiveReturns == 0 and f.sidebarArchivePresses == 0)
  expect(not f.module.busy)
end)

test("changed session cancels before pressing Archive", function()
  local f = fixture()
  f.module.archive(false)
  f.web.attributes.AXURL = "https://claude.ai/epitaxy/session-other"
  f.advance(0.5)
  expect(f.archiveReturns == 0 and not f.module.busy)
end)

test("changed session title cancels before pressing Archive", function()
  local f = fixture()
  f.module.archive(false)
  f.web.attributes.AXTitle = "Other session - Claude Code"
  f.advance(0.5)
  expect(f.archiveReturns == 0 and not f.module.busy)
end)

test("a replaced web area cancels even with an identical URL and title", function()
  local f = fixture()
  f.module.archive(false)
  local replacement = element({AXRole = "AXWebArea", AXURL = f.web.attributes.AXURL, AXTitle = f.web.attributes.AXTitle})
  children(replacement, {f.primary, f.sidebar})
  children(f.window, {replacement})
  f.advance(0.5)
  expect(f.archiveReturns == 0 and not f.module.busy)
end)

test("changed focused window cancels before pressing Archive", function()
  local f = fixture()
  f.module.archive(false)
  f.appElement.attributes.AXFocusedWindow = element({AXRole = "AXWindow"})
  f.advance(0.5)
  expect(f.archiveReturns == 0 and not f.module.busy)
end)

test("changed foreground app cancels without sending Escape there", function()
  local f = fixture()
  f.module.archive(false); f.frontmost = f.otherApp; f.advance(0.5)
  expect(f.archiveReturns == 0 and not f.module.busy and f.escapes == 0)
end)

test("dry run uses Escape and never presses Archive", function()
  local f = fixture()
  f.module.archive(true); f.advance(0.5)
  expect(f.archiveReturns == 0 and f.escapes == 1 and f.cancelActions == 0)
  expect(#f.popup.attributes.AXChildren == 0 and f.module.lastDryRun.found == true)
  expect(not f.module.busy)
  expect(f.focusRequests == 1 and f.module.lastDryRun.focusVerified == true, "dry run did not verify keyboard focus")
end)

test("repeated releases schedule only one operation and cannot archive twice", function()
  local f = fixture()
  f.module.bind()
  expect(f.boundKey == "f19" and f.boundPressed == nil and type(f.boundReleased) == "function")
  f.boundReleased(); f.boundReleased(); f.advance(0.04)
  expect(f.popupPresses == 0 and f.archiveReturns == 0, "operation ran inside release callback")
  f.boundReleased(); f.advance(0.06); f.boundReleased(); f.advance(0.4); f.boundReleased()
  f.advance(0.2)
  expect(f.popupPresses == 0 and f.clicks == 1 and f.archiveReturns == 1)
end)

test("missing menu times out after only one verified click", function()
  local f = fixture({noMenu = true})
  f.module.archive(false); f.advance(4.5)
  expect(f.popupPresses == 0 and f.clicks == 1 and f.archiveReturns == 0 and not f.module.busy)
  expect(f.messages[#f.messages]:find("菜单未打开", 1, true) ~= nil)
end)

test("stopping a pending operation prevents later archive actions", function()
  local f = fixture({openDelay = 2})
  f.module.archive(false); f.advance(0.3); f.module.stop(); f.advance(4.5)
  expect(f.archiveReturns == 0 and not f.module.busy)
end)

test("split view is refused before opening any popup", function()
  local f = fixture({secondaryPane = true})
  f.module.archive(false); f.advance(0.5)
  expect(f.popupPresses == 0 and f.archiveReturns == 0 and not f.module.busy)
end)

test("a verified popup descendant is an acceptable click target", function()
  local f = fixture({firstPressNoEffect = true, hitDescendant = true})
  f.module.archive(false); f.advance(2.5)
  expect(f.hitTests == 1 and f.clicks == 1 and f.archiveReturns == 1)
end)

test("an obscuring element prevents opening the menu", function()
  local f = fixture({firstPressNoEffect = true, obscured = true})
  f.module.archive(false); f.advance(2.5)
  expect(f.hitTests == 1 and f.clicks == 0 and f.archiveReturns == 0 and not f.module.busy)
end)

test("an absent hit target prevents opening the menu", function()
  local f = fixture({firstPressNoEffect = true})
  f.hitTarget = nil
  f.module.archive(false); f.advance(2.5)
  expect(f.hitTests == 1 and f.clicks == 0 and f.archiveReturns == 0 and not f.module.busy)
end)

local invalidFrames = {
  {name = "missing position", position = false},
  {name = "missing size", size = false},
  {name = "non-numeric position", position = {x = "100", y = 80}},
  {name = "infinite position", position = {x = math.huge, y = 80}},
  {name = "NaN position", position = {x = 0 / 0, y = 80}},
  {name = "infinite width", size = {w = math.huge, h = 24}},
  {name = "NaN height", size = {w = 24, h = 0 / 0}},
  {name = "zero width", size = {w = 0, h = 24}},
  {name = "negative height", size = {w = 24, h = -1}},
}
for _, invalid in ipairs(invalidFrames) do
  test(invalid.name .. " refuses coordinate actions", function()
    local f = fixture({firstPressNoEffect = true, position = invalid.position, size = invalid.size})
    f.module.archive(false); f.advance(2.5)
    expect(f.hitTests == 0 and f.clicks == 0 and f.archiveReturns == 0 and not f.module.busy)
  end)
end

test("a disabled menu button cannot receive the opening click", function()
  local f = fixture({firstPressNoEffect = true, buttonEnabled = false})
  f.module.archive(false); f.advance(2.5)
  expect(f.clicks == 0 and f.archiveReturns == 0 and not f.module.busy)
end)

test("a foreground change during hit testing cancels before clicking", function()
  local f = fixture({firstPressNoEffect = true, changeAppDuringHitTest = true})
  f.module.archive(false); f.advance(2.5)
  expect(f.hitTests == 1 and f.clicks == 0 and f.archiveReturns == 0 and not f.module.busy)
end)

test("a session change between release and delayed execution cancels", function()
  local f = fixture()
  f.module.bind(); f.boundReleased()
  f.web.attributes.AXURL = "https://claude.ai/epitaxy/session-other"
  f.advance(0.5)
  expect(f.popupPresses == 0 and f.clicks == 0 and f.archiveReturns == 0 and not f.module.busy)
end)

test("a title change between release and delayed execution cancels", function()
  local f = fixture()
  f.module.bind(); f.boundReleased()
  f.web.attributes.AXTitle = "Other session - Claude Code"
  f.advance(0.5)
  expect(f.popupPresses == 0 and f.archiveReturns == 0 and not f.module.busy)
end)

test("a replaced same-title web area during release delay cancels", function()
  local f = fixture()
  f.module.bind(); f.boundReleased()
  local replacement = element({AXRole = "AXWebArea", AXURL = f.web.attributes.AXURL, AXTitle = f.web.attributes.AXTitle})
  children(replacement, {f.primary, f.sidebar})
  children(f.window, {replacement})
  f.advance(0.5)
  expect(f.popupPresses == 0 and f.archiveReturns == 0 and not f.module.busy)
end)

test("an app change during release delay cancels", function()
  local f = fixture()
  f.module.bind(); f.boundReleased(); f.frontmost = f.otherApp; f.advance(0.5)
  expect(f.popupPresses == 0 and f.clicks == 0 and f.archiveReturns == 0 and not f.module.busy)
end)

test("stopping cancels the delayed release callback", function()
  local f = fixture()
  f.module.bind(); f.boundReleased(); f.module.stop(); f.advance(0.5)
  expect(f.popupPresses == 0 and f.archiveReturns == 0 and f.module.triggerTimer == nil)
end)

test("a dry-run binding checks the real hotkey path without Archive", function()
  local f = fixture({firstPressNoEffect = true})
  f.module.bind(true); f.boundReleased(); f.advance(2.5)
  expect(f.popupPresses == 0 and f.clicks == 1 and f.archiveReturns == 0 and f.escapes == 1)
  expect(f.module.lastDryRun.found == true and not f.module.busy)
end)

test("success requires two consecutive observations after Return", function()
  local f = fixture()
  f.module.archive(false); f.advance(0.25)
  expect(f.archiveReturns == 1 and f.module.busy and f.module.lastArchive == nil)
  expect(f.module.lastAttempt.status == "activated")
  f.advance(0.12)
  expect(f.module.busy and f.module.lastArchive == nil, "one changed-view observation was accepted")
  f.advance(0.12)
  expect(not f.module.busy and f.module.lastArchive.confirmation == "view-changed")
end)

test("a Return with no effect times out without being repeated", function()
  local f = fixture({archiveNoEffect = true})
  f.module.archive(false); f.advance(4)
  expect(f.archiveReturns == 1 and f.module.lastArchive == nil and not f.module.busy)
  expect(f.module.lastAttempt.status == "unconfirmed")
end)

test("closing the menu alone does not confirm Archive", function()
  local f = fixture({archiveCloseOnly = true})
  f.module.archive(false); f.advance(4)
  expect(f.archiveReturns == 1 and f.module.lastArchive == nil and not f.module.busy)
  expect(f.module.lastAttempt.status == "unconfirmed")
end)

test("an empty AX URL after Return cannot confirm Archive", function()
  local f = fixture({archiveAXGap = true})
  f.module.archive(false); f.advance(4)
  expect(f.archiveReturns == 1 and f.module.lastArchive == nil and not f.module.busy)
  expect(f.module.lastAttempt.status == "unconfirmed")
end)

test("a different focused window cannot confirm Archive", function()
  local f = fixture({archiveOtherWindow = true})
  f.module.archive(false); f.advance(4)
  expect(f.archiveReturns == 1 and f.module.lastArchive == nil and not f.module.busy)
  expect(f.module.lastAttempt.status == "unconfirmed")
end)

test("a Claude home route is a valid changed view", function()
  local f = fixture({nextURL = "https://claude.ai/"})
  f.module.archive(false); f.advance(0.5)
  expect(f.archiveReturns == 1 and f.module.lastArchive.confirmation == "view-changed")
end)

test("a URL outside Claude is not a successful view change", function()
  local f = fixture({nextURL = "https://example.com/"})
  f.module.archive(false); f.advance(4)
  expect(f.archiveReturns == 1 and f.module.lastArchive == nil and f.module.lastAttempt.status == "unconfirmed")
end)

test("an AX gap resets the consecutive-view observation count", function()
  local f = fixture()
  f.module.archive(false); f.advance(0.37)
  expect(f.module.busy and f.module.lastArchive == nil)
  f.web.attributes.AXURL = nil; f.advance(0.12)
  f.web.attributes.AXURL = "https://claude.ai/epitaxy/session-next"; f.advance(0.12)
  expect(f.module.busy and f.module.lastArchive == nil)
  f.advance(0.12)
  expect(not f.module.busy and f.module.lastArchive.confirmation == "view-changed")
end)

test("a Return exception is not retried or treated as success", function()
  local f = fixture({returnThrows = true})
  f.module.archive(false); f.advance(4)
  expect(f.archiveReturns == 1 and f.module.lastArchive == nil and not f.module.busy)
  expect(f.module.lastAttempt.status == "unconfirmed")
end)

test("repeated releases stay blocked while Archive completion is pending", function()
  local f = fixture({archiveDelay = 2})
  f.module.bind(); f.boundReleased(); f.advance(0.35)
  expect(f.archiveReturns == 1 and f.module.busy)
  for _ = 1, 4 do f.boundReleased(); f.module.archive(false); f.advance(0.4) end
  expect(f.archiveReturns == 1 and f.module.busy)
  f.advance(0.7)
  expect(f.archiveReturns == 1 and not f.module.busy and f.module.lastArchive ~= nil)
end)

test("focus verification uses the app even when item AXFocused is absent", function()
  local f = fixture()
  f.archiveItem.attributes.AXPosition = nil
  f.archiveItem.attributes.AXSize = nil
  f.module.archive(false); f.advance(0.5)
  expect(f.archiveItem.attributes.AXFocused == nil)
  expect(f.focusRequests == 1 and f.archiveReturns == 1 and f.module.lastArchive ~= nil)
end)

test("a non-settable focus refuses Return", function()
  local f = fixture({focusCannotSet = true})
  f.module.archive(false); f.advance(0.5)
  expect(f.focusRequests == 1 and f.archiveReturns == 0 and not f.module.busy)
end)

test("an exception setting focus refuses Return", function()
  local f = fixture({focusSetThrows = true})
  f.module.archive(false); f.advance(0.5)
  expect(f.focusRequests == 1 and f.archiveReturns == 0 and not f.module.busy)
end)

test("a successful focus result without actual focus cannot send Return", function()
  local f = fixture({focusNoEffect = true})
  f.module.archive(false); f.advance(4.5)
  expect(f.focusRequests == 1 and f.archiveReturns == 0 and not f.module.busy)
  expect(f.module.lastArchive == nil)
end)

test("a different same-title Archive focus cannot receive Return", function()
  local f = fixture({focusWrongArchive = true})
  f.module.archive(false); f.advance(4.5)
  expect(f.focusRequests == 1 and f.archiveReturns == 0 and not f.module.busy)
end)

test("focus remaining in the editor never receives Return", function()
  local f = fixture({focusWrongEditor = true})
  f.module.archive(false); f.advance(4.5)
  expect(f.focusRequests == 1 and f.archiveReturns == 0 and not f.module.busy)
end)

test("the final focus recheck prevents Return after focus moves", function()
  local f = fixture({focusFinalChange = true})
  f.module.archive(false); f.advance(0.5)
  expect(f.focusReads == 3 and f.archiveReturns == 0 and not f.module.busy)
  expect(f.module.lastAttempt == nil)
end)

test("the final context recheck prevents Return after the session changes", function()
  local f = fixture({contextFinalChange = true})
  f.module.archive(false); f.advance(0.5)
  expect(f.archiveReturns == 0 and not f.module.busy and f.module.lastAttempt == nil)
end)

test("the final enabled recheck prevents Return on a disabled Archive", function()
  local f = fixture({disabledFinalChange = true})
  f.module.archive(false); f.advance(0.5)
  expect(f.archiveReturns == 0 and not f.module.busy and f.module.lastAttempt == nil)
end)

test("a dry run with focus failure neither sends Return nor claims success", function()
  local f = fixture({focusNoEffect = true})
  f.module.archive(true); f.advance(4.5)
  expect(f.focusRequests == 1 and f.archiveReturns == 0 and not f.module.busy)
  expect(f.module.lastDryRun == nil and f.module.lastArchive == nil)
end)

test("a verified dry run records context and sends only Escape", function()
  local f = fixture()
  f.module.archive(true); f.advance(0.5)
  expect(f.archiveReturns == 0 and f.escapes == 1 and f.focusRequests == 1)
  expect(f.module.lastDryRun.focusVerified == true and f.module.lastDryRun.context.web == f.web)
end)

test("pending focus verification blocks repeated releases and focus requests", function()
  local f = fixture({focusNoEffect = true})
  f.module.bind(); f.boundReleased(); f.advance(0.35)
  for _ = 1, 4 do f.boundReleased(); f.module.archive(false); f.advance(0.4) end
  expect(f.focusRequests == 1 and f.archiveReturns == 0 and f.module.busy)
  f.advance(3)
  expect(not f.module.busy and f.archiveReturns == 0)
end)

test("losing the foreground after Return records uncertainty, not cancellation", function()
  local f = fixture({archiveNoEffect = true})
  f.module.archive(false); f.advance(0.25)
  expect(f.archiveReturns == 1 and f.module.lastAttempt.status == "activated")
  f.frontmost = f.otherApp; f.advance(0.12)
  expect(f.archiveReturns == 1 and f.module.lastAttempt.status == "unconfirmed" and not f.module.busy)
  expect(f.messages[#f.messages]:find("未确认归档结果", 1, true) ~= nil)
end)

test("an existing destructive confirmation stops before opening the menu", function()
  local f = fixture()
  f.showConfirmation()
  f.module.archive(false); f.advance(0.5)
  expect(f.popupPresses == 0 and f.archiveReturns == 0 and not f.module.busy)
  expect(f.module.lastArchive == nil)
end)

test("a confirmation after Return requires human action and is never accepted", function()
  local f = fixture({confirmationAfterReturn = true})
  f.module.bind(); f.boundReleased(); f.advance(0.7)
  expect(f.archiveReturns == 1 and not f.module.busy and f.module.lastArchive == nil)
  expect(f.module.lastAttempt.status == "confirmation-required")
  f.advance(1); f.boundReleased(); f.advance(0.5)
  expect(f.archiveReturns == 1 and f.popupPresses == 0 and f.clicks == 1 and f.confirmationClicks == 0)
end)

test("confirmation takes precedence over a changed route", function()
  local f = fixture({confirmationAfterReturn = true, confirmationWithRoute = true})
  f.module.archive(false); f.advance(0.6)
  expect(f.archiveReturns == 1 and f.module.lastArchive == nil and not f.module.busy)
  expect(f.module.lastAttempt.status == "confirmation-required")
end)

test("confirmation takes precedence over the result timeout", function()
  local f = fixture({archiveNoEffect = true})
  f.module.archive(false); f.advance(3.2)
  expect(f.module.busy and f.archiveReturns == 1)
  f.showConfirmation(); f.advance(0.3)
  expect(not f.module.busy and f.module.lastArchive == nil)
  expect(f.module.lastAttempt.status == "confirmation-required")
end)

test("context capture stays shallow and each poll reads the sidebar at most once", function()
  local f = fixture()
  f.module.bind(true); f.boundReleased()
  expect(f.primary.reads.AXChildren == nil and f.sidebar.reads.AXChildren == nil,
    "capturing the release context walked the session content")
  f.advance(0.5)
  expect(f.module.lastDryRun and f.module.lastDryRun.focusVerified)
  expect((f.sidebar.reads.AXChildren or 0) <= 3,
    "initial validation and two menu polls should not repeatedly rescan the sidebar")
  expect(f.popupPresses == 0 and f.clicks == 1 and f.archiveReturns == 0)
end)

test("a long conversation is skipped during all archive observations", function()
  local f = fixture()
  local messages = element({AXRole = "AXGroup", AXDescription = "Chat messages"})
  local text = element({AXRole = "AXStaticText", AXTitle = "Conversation contents"})
  local nodes = {}
  for _ = 1, 1900 do nodes[#nodes + 1] = text end
  children(messages, nodes)
  children(f.primary, {f.popup, messages})
  f.module.archive(true); f.advance(0.5)
  expect(f.module.lastDryRun and f.module.lastDryRun.focusVerified)
  expect(messages.reads.AXChildren == nil and text.reads.AXRole == nil,
    "archive should not read conversation history")
end)

test("an incomplete oversized tree cannot authorize Archive", function()
  local f = fixture()
  local nodes = {}
  for _ = 1, 1800 do nodes[#nodes + 1] = element({AXRole = "AXGroup"}) end
  children(f.sidebar, nodes)
  f.module.archive(false); f.advance(0.5)
  expect(f.clicks == 0 and f.archiveReturns == 0 and not f.module.busy)
  expect(f.messages[#f.messages]:find("无法完整核对", 1, true) ~= nil)
end)

test("a confirmation appearing while the menu opens blocks Archive", function()
  local f = fixture({openDelay = 0.2})
  f.module.archive(false)
  f.showConfirmation()
  f.advance(0.5)
  expect(f.archiveReturns == 0 and f.confirmationClicks == 0 and not f.module.busy)
end)

print(string.format("%d offline archive tests passed", passed))
