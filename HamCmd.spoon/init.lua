local obj = {}
obj.__index = obj

obj.name = "HamCmd"
obj.version = "0.1.0"
obj.author = "Drop Bear Labs"
obj.license = "MIT"

obj.hyper = { "cmd", "alt", "ctrl", "shift" }

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

function obj:switch(key)
  local candidates = self:_candidates(key)
  if candidates[1] then
    candidates[1]:activate()
  end
end

function obj:start()
  self._mru = {}
  self._hotkeys = {}

  for byte = string.byte("a"), string.byte("z") do
    local key = string.char(byte)
    self._hotkeys[key] = hs.hotkey.bind(self.hyper, key, function()
      self:switch(key)
    end)
  end

  self._watcher = hs.application.watcher.new(function(_, event, app)
    if event == hs.application.watcher.activated then
      self:_remember(app)
    end
  end):start()

  self:_remember(hs.application.frontmostApplication())
  return self
end

return obj
