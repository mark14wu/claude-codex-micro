-- Offline regression tests: no real app or accessibility setting is changed.
local source = arg[1] or "scripts/hammerspoon/claude-micro-accessibility.lua"
local accessibility = dofile(source)
local passed = 0
local function expect(value, message)
  if not value then error(message or "expectation failed", 2) end
end
local function test(name, run)
  local ok, err = pcall(run)
  if not ok then io.stderr:write("FAIL ", name, ": ", tostring(err), "\n"); os.exit(1) end
  passed = passed + 1
  print("PASS " .. name)
end
local function application(enabled)
  local app = {enabled = enabled, writes = 0}
  local element = {}
  function element:attributeValue(key)
    expect(key == "AXManualAccessibility", "unexpected accessibility flag")
    return app.enabled
  end
  function element:setAttributeValue(key, value)
    expect(key == "AXManualAccessibility" and value == true, "unexpected setting")
    app.writes = app.writes + 1
    app.enabled = value
    return self
  end
  app.element = element
  return app
end
hs = {axuielement = {applicationElement = function(app) return app.element end}}

test("explicitly disabled accessibility is enabled before returning the element", function()
  local app = application(false)
  expect(accessibility.applicationElement(app) == app.element)
  expect(app.enabled == true and app.writes == 1)
end)
test("an already enabled app is never written again", function()
  local app = application(true)
  accessibility.applicationElement(app); accessibility.applicationElement(app)
  expect(app.writes == 0)
end)
test("a successful repair is not repeated on the next read", function()
  local app = application(false)
  accessibility.applicationElement(app); accessibility.applicationElement(app)
  expect(app.writes == 1)
end)
test("a missing or unsupported attribute is not written", function()
  local app = application(nil)
  expect(accessibility.applicationElement(app) == app.element and app.writes == 0)
  function app.element:attributeValue() error("unsupported attribute") end
  expect(accessibility.applicationElement(app) == app.element and app.writes == 0)
end)
test("rejected and throwing setters leave the element available", function()
  local app = application(false)
  function app.element:setAttributeValue() return nil, "not implemented" end
  expect(accessibility.applicationElement(app) == app.element)
  function app.element:setAttributeValue() error("AX service unavailable") end
  expect(accessibility.applicationElement(app) == app.element)
end)
test("a restarted app with a new PID receives its own accessibility request", function()
  local before, after = application(false), application(false)
  function before:pid() return 101 end
  function after:pid() return 102 end
  accessibility.applicationElement(before)
  accessibility.applicationElement(after)
  expect(before.writes == 1 and after.writes == 1)
end)
test("a successful write is not repeated when Electron keeps reporting false", function()
  local app = application(false)
  function app.element:setAttributeValue()
    app.writes = app.writes + 1
    return self
  end
  for _ = 1, 100 do accessibility.applicationElement(app) end
  expect(app.writes == 1 and app.enabled == false)
end)
test("new wrappers for the same PID do not send another request", function()
  local first, second = application(false), application(false)
  function first:pid() return 103 end
  function second:pid() return 103 end
  accessibility.applicationElement(first)
  accessibility.applicationElement(second)
  expect(first.writes == 1 and second.writes == 0)
end)
test("a failed write is not cached as a successful request", function()
  local app = application(false)
  local setter = app.element.setAttributeValue
  function app.element:setAttributeValue() return nil, "temporary failure" end
  accessibility.applicationElement(app)
  app.element.setAttributeValue = setter
  accessibility.applicationElement(app)
  expect(app.writes == 1 and app.enabled == true)
end)
test("an exception does not prevent a later successful request", function()
  local app = application(false)
  local setter = app.element.setAttributeValue
  function app.element:setAttributeValue() error("AX failure") end
  accessibility.applicationElement(app)
  app.element.setAttributeValue = setter
  accessibility.applicationElement(app)
  expect(app.writes == 1 and app.enabled == true)
end)
test("an unavailable application element does not throw", function()
  expect(accessibility.applicationElement({}) == nil)
  hs.axuielement.applicationElement = function() error("process exited") end
  expect(accessibility.applicationElement({}) == nil)
end)
print(string.format("%d accessibility tests passed", passed))
