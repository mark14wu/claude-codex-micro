-- Electron may hide its web accessibility tree after an app restart. Its flag
-- can still read false after enabling, and repeated writes reset a 2s debounce.
local M = {}
local requested = {}
local function processKey(app)
  local ok, pid = pcall(function() return app:pid() end)
  if ok and type(pid) == "number" and pid > 0 then return pid end
  return app
end
function M.applicationElement(app)
  local ok, element = pcall(hs.axuielement.applicationElement, app)
  if not ok or not element then return nil end
  local key = processKey(app)
  if requested[key] then return element end
  local readable, enabled = pcall(function() return element:attributeValue("AXManualAccessibility") end)
  if readable and enabled == false then
    -- Confirm readiness from the actual web tree, not this flag's readback.
    -- Failed or unsupported writes never prevent normal navigation or retries.
    local written, result = pcall(function() return element:setAttributeValue("AXManualAccessibility", true) end)
    if written and result ~= nil and result ~= false then requested[key] = true end
  end
  return element
end
return M
