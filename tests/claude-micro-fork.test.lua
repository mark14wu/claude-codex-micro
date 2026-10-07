-- Offline regression tests; no real app, hardware, or session is touched.
-- Run from the repository root: lua tests/claude-micro-fork.test.lua
package.path = "scripts/hammerspoon/?.lua;" .. package.path
local source = arg[1] or "scripts/hammerspoon/claude-micro-fork.lua"
local harness = dofile("tests/helpers/claude-session-menu-fixture.lua")(source, "Fork")
local fixture, expect, element, children = harness.fixture, harness.expect, harness.element, harness.children
local passed = 0
local function test(name, run)
  local ok, err = pcall(run)
  if not ok then io.stderr:write("FAIL ", name, ": ", tostring(err), "\n"); os.exit(1) end
  passed = passed + 1
  print("PASS " .. name)
end

test("Ctrl+F20 acts on release and creates only one fork", function()
  local f = fixture()
  f.module.bind()
  expect(f.boundKey == "f20" and #f.boundModifiers == 1 and f.boundModifiers[1] == "ctrl")
  expect(f.boundPressed == nil and type(f.boundReleased) == "function")
  f.boundReleased(); f.boundReleased(); f.advance(0.04)
  expect(f.clicks == 0 and f.archiveReturns == 0)
  f.boundReleased(); f.advance(0.5); f.boundReleased(); f.advance(0.2)
  expect(f.clicks == 1 and f.archiveReturns == 1 and not f.module.busy)
  expect(f.module.lastFork.confirmation == "view-changed" and f.module.lastArchive == nil)
end)

test("only an exact Fork menu item can receive Return", function()
  for _, title in ipairs({"Archive", "Delete", "Fork from here", "Fork session"}) do
    local f = fixture({items = {{title = title}}})
    f.module.fork(false); f.advance(4.5)
    expect(f.archiveReturns == 0 and not f.module.busy and f.module.lastFork == nil, title)
  end
end)

test("Fork is selected by identity when Archive is also present", function()
  local f = fixture({items = {{title = "Fork"}, {title = "Archive"}, {title = "Delete"}}})
  local entries = f.menu.attributes.AXChildren
  children(f.menu, {entries[2], entries[1], entries[3]})
  f.module.fork(false); f.advance(0.5)
  expect(f.archiveReturns == 1 and f.focusRequests == 1 and f.module.lastFork ~= nil)
end)

test("a dry run verifies Fork focus and closes the menu without creating a session", function()
  local f = fixture()
  f.module.bind(true); f.boundReleased(); f.advance(0.5)
  expect(f.archiveReturns == 0 and f.escapes == 1 and not f.module.busy)
  expect(f.module.lastDryRun.focusVerified and f.module.lastFork == nil)
end)

test("disabled or duplicate Fork entries never receive Return", function()
  for _, items in ipairs({{{title = "Fork", enabled = false}}, {{title = "Fork"}, {title = "Fork"}}}) do
    local f = fixture({items = items})
    f.module.fork(false); f.advance(4.5)
    expect(f.archiveReturns == 0 and not f.module.busy)
  end
end)

test("a same-title sidebar menu cannot supply Fork", function()
  local f = fixture({sidebarMenuOnPress = true})
  f.module.fork(false); f.advance(0.5)
  expect(f.archiveReturns == 0 and not f.module.busy and f.module.lastFork == nil)
end)

test("an obscured current-session menu is not clicked", function()
  local f = fixture({obscured = true})
  f.module.fork(false); f.advance(0.5)
  expect(f.clicks == 0 and f.archiveReturns == 0 and not f.module.busy)
end)

test("split view is refused instead of guessing which session to fork", function()
  local f = fixture({secondaryPane = true})
  f.module.fork(false); f.advance(0.5)
  expect(f.clicks == 0 and f.archiveReturns == 0 and not f.module.busy)
end)

test("a changed session between release and execution cancels Fork", function()
  local f = fixture()
  f.module.bind(); f.boundReleased()
  f.web.attributes.AXURL = "https://claude.ai/epitaxy/other"
  f.advance(0.5)
  expect(f.clicks == 0 and f.archiveReturns == 0 and not f.module.busy)
end)

test("focus on a different same-title Fork item cannot authorize Return", function()
  local f = fixture({focusWrongArchive = true})
  f.module.fork(false); f.advance(4.5)
  expect(f.focusRequests == 1 and f.archiveReturns == 0 and not f.module.busy)
end)

test("focus leaving the exact Fork item prevents Return", function()
  local f = fixture({focusFinalChange = true})
  f.module.fork(false); f.advance(0.5)
  expect(f.archiveReturns == 0 and not f.module.busy)
end)

test("stopping cancels the pending release before any menu action", function()
  local f = fixture()
  f.module.bind(); f.boundReleased(); f.module.stop(); f.advance(0.5)
  expect(f.clicks == 0 and f.archiveReturns == 0 and f.module.triggerTimer == nil)
end)

test("stopping during menu focus verification prevents Return", function()
  local f = fixture()
  f.module.fork(false); f.advance(0.13); f.module.stop(); f.advance(1)
  expect(f.focusRequests == 1 and f.archiveReturns == 0 and f.module.timer == nil)
end)

test("Fork without a changed view is never repeated or reported as completed", function()
  local f = fixture({archiveNoEffect = true})
  f.module.fork(false); f.advance(4)
  expect(f.archiveReturns == 1 and not f.module.busy and f.module.lastFork == nil)
  expect(f.module.lastAttempt.status == "unconfirmed")
end)

test("closing the menu alone cannot confirm Fork", function()
  local f = fixture({archiveCloseOnly = true})
  f.module.fork(false); f.advance(4)
  expect(f.archiveReturns == 1 and f.module.lastFork == nil and f.module.lastAttempt.status == "unconfirmed")
end)

test("home or an external route cannot be mistaken for a newly forked Code session", function()
  for _, url in ipairs({"https://claude.ai/", "https://claude.ai/epitaxy", "https://example.com/fork"}) do
    local f = fixture({nextURL = url})
    f.module.fork(false); f.advance(4)
    expect(f.archiveReturns == 1 and f.module.lastFork == nil and f.module.lastAttempt.status == "unconfirmed", url)
  end
end)

test("a changed view must remain stable for two observations", function()
  local f = fixture()
  f.module.fork(false); f.advance(0.37)
  expect(f.module.busy and f.module.lastFork == nil)
  f.advance(0.12)
  expect(not f.module.busy and f.module.lastFork.confirmation == "view-changed")
end)

test("a visible sheet blocks Fork before opening the menu", function()
  local f = fixture()
  children(f.window, {f.web, element({AXRole = "AXSheet", AXDescription = "Save changes?"})})
  f.module.fork(false); f.advance(0.5)
  expect(f.clicks == 0 and f.archiveReturns == 0 and not f.module.busy)
end)

test("an archive confirmation is never accepted by the Fork key", function()
  local f = fixture()
  f.showConfirmation()
  f.module.fork(false); f.advance(0.5)
  expect(f.clicks == 0 and f.archiveReturns == 0 and f.confirmationClicks == 0)
end)

test("a modal after Fork is left to the user even if the route changes", function()
  local f = fixture({confirmationAfterReturn = true, confirmationWithRoute = true})
  f.module.fork(false); f.advance(0.6)
  expect(f.archiveReturns == 1 and not f.module.busy and f.module.lastFork == nil)
  expect(f.module.lastAttempt.status == "confirmation-required" and f.confirmationClicks == 0)
end)

test("a blocked action cannot schedule a release or run directly", function()
  local f = fixture()
  local prepared = 0
  f.module.bind(false, function() return false end, function() prepared = prepared + 1 end)
  f.boundReleased(); f.module.fork(false); f.advance(0.5)
  expect(prepared == 0 and f.clicks == 0 and f.module.triggerTimer == nil)
end)

test("the interlock is rechecked after leaving the hotkey event", function()
  local f = fixture()
  local allowed, prepared = true, 0
  f.module.bind(false, function() return allowed end, function() prepared = prepared + 1 end)
  f.boundReleased(); allowed = false; f.advance(0.5)
  expect(prepared == 1 and f.clicks == 0 and f.module.triggerTimer == nil and not f.module.busy)
end)

test("release preparation cancels pending navigation before capturing its target", function()
  local f = fixture()
  local prepared = 0
  f.module.bind(false, function() return true end, function() prepared = prepared + 1 end)
  f.boundReleased()
  expect(prepared == 1 and f.module.triggerTimer ~= nil and f.clicks == 0)
  f.advance(0.6)
  expect(prepared == 1 and f.archiveReturns == 1)
end)

test("direct Fork performs the same preparation once", function()
  local f = fixture()
  local prepared = 0
  f.module.bind(false, function() return true end, function() prepared = prepared + 1 end)
  f.module.fork(false); f.advance(0.5)
  expect(prepared == 1 and f.archiveReturns == 1)
end)

test("Archive and Fork instances do not share timers, hotkeys, or result fields", function()
  local f = fixture()
  local archive = assert(loadfile("scripts/hammerspoon/claude-micro-archive.lua"))()
  archive.bind()
  expect(f.boundKey == "f19" and #f.boundModifiers == 0)
  f.module.bind(); f.boundReleased()
  expect(f.module.triggerTimer ~= nil and archive.triggerTimer == nil)
  archive.stop(); f.advance(0.6)
  expect(f.archiveReturns == 1 and f.module.lastFork ~= nil)
  expect(archive.lastArchive == nil and archive.lastFork == nil and not archive.busy)
end)

test("the Archive instance cannot select a Fork-only menu", function()
  local f = fixture()
  local archive = assert(loadfile("scripts/hammerspoon/claude-micro-archive.lua"))()
  archive.archive(false); f.advance(4.5)
  expect(f.archiveReturns == 0 and archive.lastArchive == nil and not archive.busy)
  expect(f.module.lastFork == nil and f.module.lastAttempt == nil)
end)

print(string.format("%d offline fork tests passed", passed))
