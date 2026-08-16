local obj = {}
obj.__index = obj

obj.name = "HamCmd"
obj.version = "0.1.0"
obj.author = "DropBear Labs"
obj.license = "MIT"

obj.hotkeyModifiers = { "alt" }
obj.settingsKey = "HamCmd.state"

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
  self._lastByKey[initialKey(app)] = bundleID
  hs.settings.set(self.settingsKey, {
    lastByKey = self._lastByKey,
    mru = self._mru,
  })
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

function obj:switch(key)
  local candidates = self:_candidates(key)
  if not candidates[1] then
    self._cycle = nil
    local bundleID = self._lastByKey[key]
    if bundleID then
      hs.application.launchOrFocusByBundleID(bundleID)
    end
    return
  end

  local byBundleID = {}
  for _, app in ipairs(candidates) do
    byBundleID[app:bundleID()] = app
  end

  local frontmost = hs.application.frontmostApplication()
  local frontmostID = frontmost and frontmost:bundleID() or nil

  if #candidates == 1 and candidates[1]:bundleID() == frontmostID then
    self._cycle = nil
    self._expectedActivation = nil
    candidates[1]:hide()
    return
  end

  local target

  if self._cycle and self._cycle.key == key and self._cycle.targetID == frontmostID then
    for offset = 1, #self._cycle.order do
      local index = ((self._cycle.index + offset - 1) % #self._cycle.order) + 1
      local candidate = byBundleID[self._cycle.order[index]]
      if candidate then
        self._cycle.index = index
        target = candidate
        break
      end
    end
  else
    local order = {}
    local targetIndex = 1
    for index, app in ipairs(candidates) do
      table.insert(order, app:bundleID())
      if app:bundleID() == frontmostID then
        targetIndex = (index % #candidates) + 1
      end
    end
    self._cycle = {
      key = key,
      order = order,
      index = targetIndex,
    }
    target = candidates[targetIndex]
  end

  if target then
    self._cycle.targetID = target:bundleID()
    self._expectedActivation = target:bundleID()
    if not target:activate() then
      self._cycle = nil
      self._expectedActivation = nil
    end
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
  local state = hs.settings.get(self.settingsKey) or {}
  self._mru = state.mru or {}
  self._lastByKey = state.lastByKey or {}
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
      local bundleID = app and app:bundleID() or nil
      if self._expectedActivation == bundleID then
        self._expectedActivation = nil
      else
        self._cycle = nil
      end
      self:_remember(app)
    end
  end):start()

  self:_remember(hs.application.frontmostApplication())
  return self
end

return obj
