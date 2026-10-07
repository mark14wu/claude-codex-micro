-- Offline tests only: no app is launched and no real input is sent.
-- Run from the repository root: lua tests/claude-micro-sidebar.test.lua
local source = arg[1] or "scripts/hammerspoon/claude-micro-sidebar.lua"
local mainSource = arg[2] or "scripts/hammerspoon/claude-micro.lua"
local BUNDLE = "com.anthropic.claudefordesktop"
local passed = 0
local attributeReads = 0

local function expect(value, message)
  if not value then error(message or "expectation failed", 2) end
end
local function eq(actual, expected, message)
  expect(actual == expected, (message or "values differ") .. ": " .. tostring(actual) .. " ~= " .. tostring(expected))
end
local function element(attributes, actions)
  local e = {attributes = attributes or {}, actions = actions or {}}
  e.attributes.AXChildren = e.attributes.AXChildren or {}
  function e:attributeValue(key)
    attributeReads = attributeReads + 1
    return self.attributes[key]
  end
  function e:actionNames()
    local result = {}
    for name in pairs(self.actions) do result[#result + 1] = name end
    return result
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
  return parent
end
local function group(values)
  return children(element({AXRole = "AXGroup"}), values or {})
end

local function fixture()
  local f = {now = 100, timers = {}, clicks = {}, alerts = {}, logs = {}, launches = 0, hitTests = 0, buttons = {}, bindings = {}}
  function f.schedule(delay, callback, repeating)
    local timer = {at = f.now + delay, callback = callback, interval = repeating and delay or nil, stopped = false}
    function timer:stop() self.stopped = true end
    f.timers[#f.timers + 1] = timer
    return timer
  end
  function f.advance(seconds)
    local deadline = f.now + seconds
    local count = 0
    while true do
      local nextTimer
      for _, timer in ipairs(f.timers) do
        if not timer.stopped and timer.at <= deadline and (not nextTimer or timer.at < nextTimer.at) then nextTimer = timer end
      end
      if not nextTimer then break end
      f.now = nextTimer.at
      if nextTimer.interval then nextTimer.at = nextTimer.at + nextTimer.interval else nextTimer.stopped = true end
      nextTimer.callback()
      count = count + 1
      expect(count < 1000, "timer did not terminate")
    end
    f.now = deadline
  end
  f.app = {bundleID = function() return BUNDLE end}
  f.otherApp = {bundleID = function() return "test.other" end}
  f.frontmost = f.app
  f.autoActivate = true
  f.window = element({AXRole = "AXWindow"})
  f.web = element({AXRole = "AXWebArea", AXTitle = "Before - Claude Code", AXURL = "https://claude.ai/epitaxy/before"})
  f.sidebar = element({AXRole = "AXGroup", AXDescription = "Sidebar"})
  children(f.window, {f.web})
  children(f.web, {f.sidebar})
  f.appElement = element({AXFocusedWindow = f.window, AXMainWindow = f.window})
  function f.row(title, prefix)
    local n = #f.buttons + 1
    local button = element({
      AXRole = "AXButton", AXDescription = (prefix or "Idle ") .. title,
      AXEnabled = true, AXPosition = {x = 20, y = 30 * n}, AXSize = {w = 180, h = 24},
    }, {AXPress = function() error("session navigation must not rely on AXPress") end})
    local text = element({AXRole = "AXStaticText", AXValue = title})
    children(button, {text})
    local menu = element({AXRole = "AXPopUpButton", AXDescription = "More options for " .. title})
    -- The rendered accessibility outline hides the menu's intermediate group.
    -- Keep the real Electron shape in every fixture, including unnamed buttons.
    local row = group({button, group({menu})})
    row.button, row.menu, row.text, row.title = button, menu, text, title
    button.row = row
    f.buttons[#f.buttons + 1] = button
    return row
  end
  function f.project(name, titles)
    local header = element({AXRole = "AXButton", AXDescription = name})
    local anchor = element({AXRole = "AXButton", AXDescription = "New session in " .. name})
    local filter = element({AXRole = "AXPopUpButton", AXDescription = "Filter"})
    local values, rows = {header, anchor, filter}, {}
    for _, title in ipairs(titles or {}) do
      local row = f.row(title)
      rows[#rows + 1], values[#values + 1] = row, row
    end
    local project = group(values)
    project.header, project.anchor, project.rows = header, anchor, rows
    return project
  end
  function f.setProjects(values) children(f.sidebar, values) end
  function f.pointHit(point)
    for _, button in ipairs(f.buttons) do
      local p, s = button.attributes.AXPosition, button.attributes.AXSize
      if not button.hidden and p and s and point.x == p.x + s.w / 2 and point.y == p.y + s.h / 2 then return button end
    end
    return f.web
  end
  hs = {
    logger = {new = function() return {i = function(message) f.logs[#f.logs + 1] = message end} end},
    alert = {show = function(message) f.alerts[#f.alerts + 1] = message end},
    timer = {secondsSinceEpoch = function() return f.now end, doEvery = function(delay, callback) return f.schedule(delay, callback, true) end},
    application = {
      get = function(bundle) eq(bundle, BUNDLE); if not f.missingApp then return f.app end end,
      frontmostApplication = function() return f.frontmost end,
      launchOrFocusByBundleID = function(bundle)
        eq(bundle, BUNDLE); f.launches = f.launches + 1
        if f.autoActivate then f.frontmost = f.app end
        return true
      end,
    },
    axuielement = {
      applicationElement = function(app) eq(app, f.app); return f.appElement end,
      systemElementAtPosition = function(point)
        f.hitTests = f.hitTests + 1
        if f.hitHook then return f.hitHook(point) end
        return f.pointHit(point)
      end,
    },
    eventtap = {leftClick = function(point)
      local target = f.pointHit(point)
      expect(target.row, "click did not target a session button")
      f.clicks[#f.clicks + 1] = target
      if f.clickHook then f.clickHook(target)
      else f.web.attributes.AXTitle = target.row.title .. " - Claude Code" end
    end},
    hotkey = {bind = function(mods, key, pressed, released)
      local binding = {mods = mods, key = key, pressed = pressed, released = released}
      function binding:delete() self.deleted = true end
      f.bindings[#f.bindings + 1] = binding
      return binding
    end},
  }
  f.module = dofile(source)
  return f
end
local function test(name, callback)
  local ok, err = pcall(callback)
  if not ok then io.stderr:write("FAIL " .. name .. "\n" .. tostring(err) .. "\n"); os.exit(1) end
  passed = passed + 1
  print("PASS " .. name)
end
local six = {"one", "two", "three", "four", "five", "six"}
local function normal()
  local f = fixture()
  f.first, f.second = f.project("Top", six), f.project("Other", {"other one", "other two"})
  f.setProjects({f.first, f.second})
  return f
end

test("first project provides the six physical slots in order", function()
  local f = normal()
  local state = assert(f.module.readSidebar(f.sidebar))
  eq(state.rows[1].project, "Top"); eq(#state.rows, 6)
  for i = 1, 6 do eq(state.rows[i].button, f.first.rows[i].button) end
end)
test("one snapshot bounds cross-process reads and keeps missing labels cached", function()
  local f = normal()
  for _, row in ipairs(f.first.rows) do row.button.attributes.AXDescription = nil end
  local before = attributeReads
  eq(#assert(f.module.snapshot()).rows, 6)
  expect(attributeReads - before < 450, "snapshot performs repeated accessibility scans: " .. (attributeReads - before))
end)
test("foreground selection begins within 50ms without reactivating Claude", function()
  local f = normal()
  f.module.select(1); f.advance(0.05)
  eq(#f.clicks, 1); eq(f.launches, 0)
end)
test("view confirmation reads the web root without rescanning session rows", function()
  local f = normal()
  f.module.select(1); f.advance(0.04)
  local before = attributeReads
  f.advance(0.04)
  eq(f.module.lastSelection.status, "view-matched")
  expect(attributeReads - before < 30, "view confirmation rescanned the window")
end)
test("DFS preserves order when the first project is more deeply nested", function()
  local f = normal()
  f.setProjects({group({group({f.first})}), f.second})
  eq(assert(f.module.readSidebar(f.sidebar)).rows[1].project, "Top")
end)
test("row wrappers of different depth do not reorder slots", function()
  local f = normal()
  children(f.first, {f.first.header, f.first.anchor, group({group({f.first.rows[1]})}), f.first.rows[2], group({f.first.rows[3]})})
  local state = assert(f.module.readSidebar(f.sidebar))
  for i = 1, 3 do eq(state.rows[i].button, f.first.rows[i].button) end
end)
test("a short first project continues into the next project", function()
  local f = normal()
  children(f.first, {f.first.header, f.first.anchor, f.first.rows[1]})
  local state = assert(f.module.readSidebar(f.sidebar))
  eq(#state.rows, 3); eq(state.rows[2].button, f.second.rows[1].button)
  eq(state.rows[2].group, f.second); eq(state.rows[2].project, "Other")
  f.module.select(2); f.advance(1)
  eq(#f.clicks, 1); eq(f.clicks[1], f.second.rows[1].button)
end)
test("a collapsed or empty first project is skipped", function()
  local f = normal()
  children(f.first, {f.first.header, f.first.anchor})
  local state = assert(f.module.readSidebar(f.sidebar))
  eq(state.rows[1].project, "Other"); eq(#state.rows, 2)
  f.module.select(1); f.advance(1); eq(f.clicks[1], f.second.rows[1].button)
end)
test("three plus two plus one projects fill all six slots in sidebar order", function()
  local f = fixture()
  local a, b, c = f.project("A", {"a1", "a2", "a3"}), f.project("B", {"b1", "b2"}), f.project("C", {"c1"})
  f.setProjects({a, b, c})
  local expected = {a.rows[1], a.rows[2], a.rows[3], b.rows[1], b.rows[2], c.rows[1]}
  local state = assert(f.module.readSidebar(f.sidebar))
  eq(#state.rows, 6)
  for i, row in ipairs(expected) do
    eq(state.rows[i].button, row.button)
    eq(state.rows[i].group, row.attributes.AXParent)
  end
  for i, project in ipairs({a, b, c}) do eq(state.projects[i].header, project.header) end
end)
test("three plus one plus two real wrapper rows preserve all project boundaries", function()
  local f = fixture()
  local a, b, c = f.project("A", {"a1", "a2", "a3"}), f.project("B", {"b1"}), f.project("C", {"c1", "c2"})
  f.setProjects({group({a}), b, group({group({c})})})
  local expected = {a.rows[1], a.rows[2], a.rows[3], b.rows[1], c.rows[1], c.rows[2]}
  for _, row in ipairs(expected) do row.button.attributes.AXDescription = nil end
  local state = assert(f.module.readSidebar(f.sidebar))
  eq(#state.rows, 6)
  for i, row in ipairs(expected) do eq(state.rows[i].button, row.button) end
  f.module.select(4); f.advance(1)
  eq(f.clicks[1], b.rows[1].button); eq(f.module.lastSelection.project, "B")
  f.module.select(6); f.advance(1)
  eq(f.clicks[2], c.rows[2].button); eq(f.module.lastSelection.project, "C")
end)
test("same session title in a later project selects its own row", function()
  local f = fixture()
  local a, b = f.project("A", {"same", "same", "same"}), f.project("B", {"same", "same", "same"})
  f.setProjects({a, b})
  f.module.select(4); f.advance(1); eq(f.clicks[1], b.rows[1].button)
  f.module.select(6); f.advance(1); eq(f.clicks[2], b.rows[3].button)
  eq(f.module.lastSelection.project, "B")
end)
test("archive in an earlier project shifts slots across project boundaries", function()
  local f = fixture()
  local a, b, c = f.project("A", {"a1", "a2", "a3"}), f.project("B", {"b1", "b2"}), f.project("C", {"c1", "c2"})
  f.setProjects({a, b, c})
  f.module.select(3); f.advance(1); eq(f.clicks[1], a.rows[3].button)
  children(a, {a.header, a.anchor, a.rows[2], a.rows[3]})
  local state = assert(f.module.readSidebar(f.sidebar))
  eq(state.rows[3].button, b.rows[1].button); eq(state.rows[6].button, c.rows[2].button)
  f.module.select(3); f.advance(1); eq(f.clicks[2], b.rows[1].button)
  f.module.select(6); f.advance(1); eq(f.clicks[3], c.rows[2].button)
end)
test("a malformed later project cannot block six earlier valid sessions", function()
  local f = normal()
  f.second.header.attributes.AXDescription = "Unknown project"
  local state = assert(f.module.readSidebar(f.sidebar))
  eq(#state.rows, 6)
  f.module.select(6); f.advance(1); eq(f.clicks[1], f.first.rows[6].button)
end)
test("a malformed seventh session cannot block the first six valid sessions", function()
  local f = fixture()
  local p = f.project("Top", {"one", "two", "three", "four", "five", "six", "seven"})
  children(p.rows[7], {p.rows[7].button, element({AXRole = "AXButton"}), p.rows[7].menu})
  f.setProjects({p})
  eq(#assert(f.module.readSidebar(f.sidebar)).rows, 6)
  f.module.select(6); f.advance(1); eq(f.clicks[1], p.rows[6].button)
end)
test("an unused slot is refused only when all project rows are exhausted", function()
  local f = fixture()
  local a, b, c = f.project("A", {"a1", "a2"}), f.project("B", {}), f.project("C", {"c1"})
  f.setProjects({a, b, c})
  eq(#assert(f.module.readSidebar(f.sidebar)).rows, 3)
  f.module.select(4); f.advance(1)
  eq(#f.clicks, 0); expect(f.alerts[1]:find("第 4", 1, true))
end)
test("all collapsed or empty projects produce no slots", function()
  local f = fixture()
  f.setProjects({f.project("A", {}), f.project("B", {})})
  eq(#assert(f.module.readSidebar(f.sidebar)).rows, 0)
  f.module.select(1); f.advance(1); eq(#f.clicks, 0)
end)
test("duplicate titles retain the row identity within the first project", function()
  local f = fixture()
  local a, b = f.project("Top", {"same", "same"}), f.project("Other", {"same"})
  f.setProjects({a, b})
  f.module.select(2); f.advance(1)
  eq(#f.clicks, 1); eq(f.clicks[1], a.rows[2].button)
end)
test("status prefixes do not change the session order", function()
  local f = normal()
  local prefixes = {"Idle ", "Running ", "Needs attention ", "Completed ", "Unread ", ""}
  for i, row in ipairs(f.first.rows) do row.button.attributes.AXDescription = prefixes[i] .. row.title end
  local state = assert(f.module.readSidebar(f.sidebar))
  for i = 1, 6 do eq(state.rows[i].button, f.first.rows[i].button) end
end)
test("unnamed session buttons use their own row menu and child text", function()
  local f = normal()
  for _, row in ipairs(f.first.rows) do
    row.button.attributes.AXDescription = nil
    row.button.attributes.AXTitle = nil
  end
  local state = assert(f.module.readSidebar(f.sidebar))
  for i = 1, 6 do
    eq(state.rows[i].button, f.first.rows[i].button)
    eq(state.rows[i].title, six[i])
  end
  f.module.select(6); f.advance(1); eq(f.clicks[1], f.first.rows[6].button)
end)
test("more than six rows still restricts the callable slots to six", function()
  local f = fixture()
  local p = f.project("Top", {"one", "two", "three", "four", "five", "six", "seven"})
  f.setProjects({p})
  f.module.select(7); f.advance(1)
  eq(f.launches, 0); eq(#f.clicks, 0)
  f.module.select(6); f.advance(1); eq(f.clicks[1], p.rows[6].button)
end)
test("ambiguous session buttons in one row are refused", function()
  local f = normal()
  local row = f.first.rows[1]
  children(row, {row.button, element({AXRole = "AXButton", AXDescription = row.title}), row.menu})
  local state, err = f.module.readSidebar(f.sidebar)
  eq(state, nil); expect(err:find("唯一", 1, true))
end)
test("multiple unnamed buttons in a session row are also refused", function()
  local f = normal()
  local row = f.first.rows[1]
  row.button.attributes.AXDescription = nil
  children(row, {row.button, element({AXRole = "AXButton"}), row.menu})
  eq(f.module.readSidebar(f.sidebar), nil)
end)
test("additional wrappers around the menu preserve the exact row button", function()
  local f = normal()
  local row = f.first.rows[3]
  children(row, {row.button, group({group({group({row.menu})})})})
  local state = assert(f.module.readSidebar(f.sidebar))
  eq(state.rows[3].row, row); eq(state.rows[3].button, row.button)
end)
test("a detached menu cannot borrow a neighboring session button", function()
  local f = normal()
  children(f.first.rows[1], {group({f.first.rows[1].menu})})
  eq(f.module.readSidebar(f.sidebar), nil)
end)
test("multiple session menus in one row are refused", function()
  local f = normal()
  local row = f.first.rows[1]
  children(row, {row.button, group({row.menu, element({AXRole = "AXPopUpButton", AXDescription = "More options for elsewhere"})})})
  eq(f.module.readSidebar(f.sidebar), nil)
end)
test("a missing or ambiguous project header is refused", function()
  local f = normal()
  f.first.header.attributes.AXDescription = "Different"
  eq(f.module.readSidebar(f.sidebar), nil)
end)
test("missing project anchors are refused", function()
  local f = fixture()
  eq(f.module.readSidebar(f.sidebar), nil)
end)
test("every selection rereads current order after a row was archived", function()
  local f = normal()
  f.module.select(1); f.advance(1); eq(f.clicks[1], f.first.rows[1].button)
  children(f.first, {f.first.header, f.first.anchor, f.first.rows[2], f.first.rows[3]})
  f.module.select(1); f.advance(1); eq(f.clicks[2], f.first.rows[2].button)
end)
test("every selection follows a new project at the top", function()
  local f = normal()
  f.module.select(1); f.advance(1)
  f.setProjects({f.second, f.first})
  f.module.select(1); f.advance(1)
  eq(f.clicks[2], f.second.rows[1].button)
end)
test("Claude is activated before the first snapshot is read", function()
  local f = normal()
  f.frontmost = f.otherApp
  local realSnapshot = f.module.snapshot
  f.module.snapshot = function(app)
    eq(f.launches, 1); eq(f.frontmost, f.app)
    return realSnapshot(app)
  end
  f.module.select(1); eq(#f.clicks, 0); f.advance(1)
  eq(f.clicks[1], f.first.rows[1].button)
end)
test("activation waits for Claude without reading another app", function()
  local f = normal()
  f.frontmost, f.autoActivate = f.otherApp, false
  local reads, realSnapshot = 0, f.module.snapshot
  f.module.snapshot = function(app) reads = reads + 1; return realSnapshot(app) end
  f.module.select(1); f.advance(0.5); eq(reads, 0); eq(#f.clicks, 0)
  f.frontmost = f.app; f.advance(1); eq(reads, 1); eq(#f.clicks, 1)
end)
test("failure to activate Claude times out without clicking", function()
  local f = normal()
  f.frontmost, f.autoActivate = f.otherApp, false
  f.module.select(1); f.advance(3)
  eq(#f.clicks, 0); eq(f.module.timer, nil)
end)
for _, role in ipairs({"AXMenu", "AXDialog", "AXSheet"}) do
  test("open " .. role .. " blocks session selection", function()
    local f = normal()
    children(f.web, {f.sidebar, element({AXRole = role})})
    f.module.select(1); f.advance(3)
    eq(#f.clicks, 0); eq(f.module.timer, nil)
  end)
end
test("Archive anyway confirmation blocks session selection", function()
  local f = normal()
  children(f.web, {f.sidebar, element({AXRole = "AXButton", AXDescription = "Archive anyway"})})
  f.module.select(1); f.advance(3); eq(#f.clicks, 0)
end)
test("a descendant hit is accepted for the exact target button", function()
  local f = normal()
  f.hitHook = function() return f.first.rows[1].text end
  f.module.select(1); f.advance(1); eq(f.clicks[1], f.first.rows[1].button)
end)
test("an obscured row is never clicked", function()
  local f = normal()
  f.hitHook = function() return f.web end
  f.module.select(1); f.advance(1); eq(#f.clicks, 0)
end)
test("a disabled row is never clicked", function()
  local f = normal()
  f.first.rows[1].button.attributes.AXEnabled = false
  f.module.select(1); f.advance(1); eq(#f.clicks, 0)
end)
for name, mutate in pairs({
  missing = function(button) button.attributes.AXPosition = nil end,
  nan = function(button) button.attributes.AXPosition.x = 0 / 0 end,
  infinite = function(button) button.attributes.AXPosition.y = math.huge end,
  zero_width = function(button) button.attributes.AXSize.w = 0 end,
  negative_height = function(button) button.attributes.AXSize.h = -1 end,
}) do
  test("invalid coordinates " .. name .. " refuse the click", function()
    local f = normal()
    mutate(f.first.rows[1].button)
    f.module.select(1); f.advance(1); eq(#f.clicks, 0)
  end)
end
test("an offscreen row scrolls once and then clicks the same element", function()
  local f = normal()
  local button, scrolls = f.first.rows[2].button, 0
  button.hidden = true
  button.actions.AXScrollToVisible = function()
    scrolls = scrolls + 1; button.hidden = false
    -- The order changes while scrolling: slot 2 must not be resolved again.
    children(f.first, {f.first.header, f.first.anchor, f.first.rows[2], f.first.rows[1]})
  end
  f.module.select(2); f.advance(1)
  eq(scrolls, 1); eq(#f.clicks, 1); eq(f.clicks[1], button)
end)
test("an ineffective scroll is not repeated and does not click", function()
  local f = normal()
  local scrolls = 0
  f.first.rows[1].button.hidden = true
  f.first.rows[1].button.actions.AXScrollToVisible = function() scrolls = scrolls + 1 end
  f.module.select(1); f.advance(1)
  eq(scrolls, 1); eq(#f.clicks, 0); eq(f.module.timer, nil)
end)
test("losing foreground after scrolling cancels the pending click", function()
  local f = normal()
  local button = f.first.rows[1].button
  button.hidden = true
  button.actions.AXScrollToVisible = function() button.hidden = false; f.frontmost = f.otherApp end
  f.module.select(1); f.advance(1); eq(#f.clicks, 0); eq(f.module.timer, nil)
end)
test("window change after scrolling cancels the pending click", function()
  local f = normal()
  local button = f.first.rows[1].button
  button.hidden = true
  button.actions.AXScrollToVisible = function()
    button.hidden = false; f.appElement.attributes.AXFocusedWindow = element({AXRole = "AXWindow"})
  end
  f.module.select(1); f.advance(1); eq(#f.clicks, 0)
end)
test("foreground change during hit testing prevents the click", function()
  local f = normal()
  f.hitHook = function() f.frontmost = f.otherApp; return f.first.rows[1].button end
  f.module.select(1); f.advance(1); eq(#f.clicks, 0)
end)
test("window change during hit testing prevents the click", function()
  local f = normal()
  f.hitHook = function()
    f.appElement.attributes.AXFocusedWindow = element({AXRole = "AXWindow"})
    return f.first.rows[1].button
  end
  f.module.select(1); f.advance(1); eq(#f.clicks, 0)
end)
test("a removed target row is not clicked after scroll retry", function()
  local f = normal()
  local button = f.first.rows[1].button
  button.hidden = true
  button.actions.AXScrollToVisible = function()
    button.hidden = false
    children(f.first, {f.first.header, f.first.anchor, f.first.rows[2]})
  end
  f.module.select(1); f.advance(1); eq(#f.clicks, 0)
end)
test("a later target project removed during scroll is never clicked", function()
  local f = fixture()
  local a, b = f.project("A", {"a1", "a2", "a3"}), f.project("B", {"b1"})
  f.setProjects({a, b})
  local button = b.rows[1].button
  button.hidden = true
  button.actions.AXScrollToVisible = function()
    button.hidden = false
    f.setProjects({a})
  end
  f.module.select(4); f.advance(1); eq(#f.clicks, 0)
end)
test("a newer key cancels the previous pending selection", function()
  local f = normal()
  f.module.select(1)
  local old = f.module.timer
  f.module.select(2)
  expect(old.stopped)
  f.advance(1); eq(#f.clicks, 1); eq(f.clicks[1], f.first.rows[2].button)
end)
test("stop cancels pending work", function()
  local f = normal()
  f.module.select(1); local old = f.module.timer
  f.module.stop(); expect(old.stopped); eq(f.module.timer, nil)
  f.advance(1); eq(#f.clicks, 0)
end)
test("unconfirmed navigation is reported without repeated clicks", function()
  local f = normal()
  f.clickHook = function() end
  f.module.select(1); f.advance(3)
  eq(#f.clicks, 1); eq(f.module.lastSelection.status, "unconfirmed")
end)
test("main binds six release actions and preserves real F19 archive", function()
  local f = normal()
  local selected, stopped, archiveBound = {}, 0, nil
  local sessions = {select = function(slot) selected[#selected + 1] = slot end, stop = function() stopped = stopped + 1 end}
  local archive = {busy = false, bind = function(dryRun) archiveBound = dryRun end, stop = function() stopped = stopped + 1 end}
  local previousSessions, previousArchive = package.loaded["claude-micro-sidebar"], package.loaded["claude-micro-archive"]
  package.loaded["claude-micro-sidebar"], package.loaded["claude-micro-archive"] = sessions, archive
  local previousOpen, oldMicro, oldTest, oldArchive = io.open, _G.claudeMicro, _G.microTest, _G.claudeArchive
  io.open = function() error("legacy session JSON must not be read") end
  _G.claudeMicro, _G.microTest, _G.claudeArchive = nil, nil, nil
  local ok, err = pcall(function()
    local main = dofile(mainSource).start()
    eq(#f.bindings, 6); eq(archiveBound, false)
    for i, binding in ipairs(f.bindings) do
      eq(binding.key, "f" .. (i + 12)); eq(binding.pressed, nil)
      binding.released(); eq(selected[i], i)
    end
    archive.busy = true
    f.bindings[1].released(); eq(#selected, 6)
    main.stop(); eq(stopped, 2)
    for _, binding in ipairs(f.bindings) do expect(binding.deleted) end
  end)
  io.open = previousOpen
  _G.claudeMicro, _G.microTest, _G.claudeArchive = oldMicro, oldTest, oldArchive
  package.loaded["claude-micro-sidebar"], package.loaded["claude-micro-archive"] = previousSessions, previousArchive
  if not ok then error(err) end
end)
print(string.format("%d sidebar regression tests passed", passed))
