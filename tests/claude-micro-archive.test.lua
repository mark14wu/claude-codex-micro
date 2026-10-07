-- Offline regression tests: these mocks never connect to Claude or press real keys.
-- Run from the repository root with: lua tests/claude-micro-archive.test.lua
local source = arg[1] or "scripts/hammerspoon/claude-micro-archive.lua"
package.path = "scripts/hammerspoon/?.lua;" .. package.path
local harness = dofile("tests/helpers/claude-session-menu-fixture.lua")(source)
local fixture, expect, element, children = harness.fixture, harness.expect, harness.element, harness.children
local passed = 0

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
