local obj = {}
obj.__index = obj

obj.name = "HamCmd"
obj.version = "0.1.0"
obj.author = "DropBear Labs"
obj.license = "MIT"

obj.hotkeyModifiers = { "alt" }
obj.shortcuts = {}
obj.cycleTimeout = 1.0

local function maskIsSet(value, mask)
  return math.floor(value / mask) % 2 == 1
end

local function initialKey(app)
  local name = app:name()
  return name and name:lower():match("^%s*([a-z])") or nil
end

local function isSwitchable(app)
  return app and app:kind() == 1 and app:bundleID() ~= nil and initialKey(app) ~= nil
end

function obj:_remember(app)
  if not isSwitchable(app) then
    return
  end

  local bundleID = app:bundleID()
  for index, rememberedID in ipairs(self._mru) do
    if rememberedID == bundleID then
      table.remove(self._mru, index)
      break
    end
  end
  table.insert(self._mru, 1, bundleID)
end

function obj:_candidates(key)
  local rank = {}
  for index, bundleID in ipairs(self._mru) do
    rank[bundleID] = index
  end

  local candidates = {}
  for _, app in ipairs(hs.application.runningApplications()) do
    if isSwitchable(app) and initialKey(app) == key then
      table.insert(candidates, app)
    end
  end

  table.sort(candidates, function(left, right)
    local leftRank = rank[left:bundleID()] or math.huge
    local rightRank = rank[right:bundleID()] or math.huge
    if leftRank == rightRank then
      return left:name():lower() < right:name():lower()
    end
    return leftRank < rightRank
  end)

  return candidates
end

function obj:_runningApp(bundleID)
  for _, app in ipairs(hs.application.runningApplications()) do
    if app:kind() == 1 and app:bundleID() == bundleID then
      return app
    end
  end
  return nil
end

function obj:_activateCycleTarget(target)
  self._cycle.targetID = target:bundleID()
  if not target:activate() then
    self._cycle = nil
  end
end

function obj:_advanceCycle()
  for offset = 1, #self._cycle.order do
    local index = ((self._cycle.index + offset - 1) % #self._cycle.order) + 1
    local target = self:_runningApp(self._cycle.order[index])
    if target then
      self._cycle.index = index
      self._cycle.lastPress = hs.timer.secondsSinceEpoch()
      self:_activateCycleTarget(target)
      return
    end
  end
  self._cycle = nil
end

function obj:_startCycle(key, fixedApp)
  local order = { fixedApp:bundleID() }
  for _, app in ipairs(self:_candidates(key)) do
    if app:bundleID() ~= fixedApp:bundleID() then
      table.insert(order, app:bundleID())
    end
  end

  if #order == 1 then
    return
  end

  self._cycle = {
    key = key,
    order = order,
    index = 1,
    targetID = fixedApp:bundleID(),
  }
  self:_advanceCycle()
end

function obj:_switchFixed(key, fixedBundleID)
  local fixedApp = self:_runningApp(fixedBundleID)
  if not fixedApp then
    self._cycle = nil
    hs.application.launchOrFocusByBundleID(fixedBundleID)
    return
  end

  local frontmost = hs.application.frontmostApplication()
  local frontmostID = frontmost and frontmost:bundleID() or nil
  local now = hs.timer.secondsSinceEpoch()
  local continuing = self._cycle
    and self._cycle.key == key
    and self._cycle.targetID == frontmostID
    and now - self._cycle.lastPress <= self.cycleTimeout
  if continuing then
    self:_advanceCycle()
  elseif fixedBundleID == frontmostID then
    self._cycle = nil
    self:_startCycle(key, fixedApp)
  else
    self._cycle = nil
    fixedApp:activate()
  end
end

function obj:switch(key)
  local fixedBundleID = self.shortcuts[key]
  if fixedBundleID then
    self:_switchFixed(key, fixedBundleID)
    return
  end

  self._cycle = nil
  local candidates = self:_candidates(key)
  if not candidates[1] then
    return
  end

  local frontmost = hs.application.frontmostApplication()
  local frontmostID = frontmost and frontmost:bundleID() or nil
  if candidates[1]:bundleID() ~= frontmostID then
    candidates[1]:activate()
  end
end

function obj:_setHotkeysEnabled(enabled)
  if self._hotkeysEnabled == enabled then
    return
  end

  for _, hotkey in pairs(self._hotkeys) do
    if enabled then
      hotkey:enable()
    else
      hotkey:disable()
    end
  end
  self._hotkeysEnabled = enabled
end

function obj:start()
  self._mru = {}
  self._hotkeys = {}
  self._hotkeysEnabled = false

  for byte = string.byte("a"), string.byte("z") do
    local key = string.char(byte)
    self._hotkeys[key] = hs.hotkey.new(self.hotkeyModifiers, key, function()
      self:switch(key)
    end)
  end

  local rightAltMask = hs.eventtap.event.rawFlagMasks.deviceRightAlternate
  self._modifierWatcher = hs.eventtap.new({ hs.eventtap.event.types.flagsChanged }, function(event)
    self:_setHotkeysEnabled(maskIsSet(event:rawFlags(), rightAltMask))
  end):start()

  self._watcher = hs.application.watcher.new(function(_, event, app)
    if event == hs.application.watcher.activated then
      self:_remember(app)
    end
  end):start()

  self:_remember(hs.application.frontmostApplication())
  return self
end

return obj
