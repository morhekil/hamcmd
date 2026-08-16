local failures = 0

local function assertEqual(actual, expected, message)
  if actual ~= expected then
    error((message or "values differ") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
  end
end

local function test(name, body)
  local ok, err = pcall(body)
  if ok then
    io.write("ok - " .. name .. "\n")
  else
    failures = failures + 1
    io.write("not ok - " .. name .. "\n" .. err .. "\n")
  end
end

local function newHost(apps, initialFrontmost)
  local host = {
    apps = apps,
    frontmost = initialFrontmost,
    hotkeys = {},
  }

  for _, app in ipairs(apps) do
    app._host = host
  end

  local hs = {
    application = {},
    eventtap = {},
    hotkey = {},
  }

  hs.eventtap.event = {
    rawFlagMasks = {
      alternate = 2,
      deviceRightAlternate = 4,
    },
    types = {
      flagsChanged = 12,
    },
  }

  hs.application.watcher = {
    activated = 1,
    new = function(callback)
      host.watcherCallback = callback
      return {
        start = function(self)
          return self
        end,
      }
    end,
  }

  function hs.application.runningApplications()
    return host.apps
  end

  function hs.application.frontmostApplication()
    return host.frontmost
  end

  function hs.application.launchOrFocusByBundleID(bundleID)
    host.launchedBundleID = bundleID
    return true
  end

  function hs.hotkey.new(modifiers, key, callback)
    local hotkey = {
      modifiers = modifiers,
      callback = callback,
      enabled = false,
    }
    function hotkey:enable()
      self.enabled = true
      return self
    end
    function hotkey:disable()
      self.enabled = false
      return self
    end
    host.hotkeys[key] = hotkey
    return hotkey
  end

  function hs.eventtap.new(_, callback)
    host.modifierCallback = callback
    return {
      start = function(self)
        return self
      end,
    }
  end

  function host:setRawFlags(rawFlags)
    self.modifierCallback({
      rawFlags = function()
        return rawFlags
      end,
    })
  end

  function host:press(key)
    local hotkey = self.hotkeys[key]
    if not hotkey or not hotkey.enabled then
      return false
    end
    hotkey.callback()
    return true
  end

  return hs, host
end

local function newApp(name, bundleID, kind)
  local app = {
    activationCount = 0,
    hideCount = 0,
  }

  function app:name()
    return name
  end

  function app:bundleID()
    return bundleID
  end

  function app:kind()
    return kind or 1
  end

  function app:activate()
    self.activationCount = self.activationCount + 1
    self._host.frontmost = self
    return true
  end

  function app:hide()
    self.hideCount = self.hideCount + 1
    return true
  end

  return app
end

test("Right Option+letter focuses the most recently activated matching app", function()
  local finder = newApp("Finder", "com.apple.finder")
  local safari = newApp("Safari", "com.apple.Safari")
  local slack = newApp("Slack", "com.tinyspeck.slackmacgap")
  local background = newApp("Sync Service", "example.sync", 0)
  local fakeHs, host = newHost({ finder, safari, slack, background }, finder)
  _G.hs = fakeHs

  local hamcmd = dofile("HamCmd.spoon/init.lua")
  hamcmd:start()

  host.watcherCallback(safari:name(), fakeHs.application.watcher.activated, safari)
  host.watcherCallback(slack:name(), fakeHs.application.watcher.activated, slack)
  host.hotkeys.s.callback()

  assertEqual(slack.activationCount, 1, "most recent matching app activation count")
  assertEqual(safari.activationCount, 0, "older matching app activation count")
  assertEqual(background.activationCount, 0, "non-Dock app activation count")
  assertEqual(table.concat(host.hotkeys.s.modifiers, "+"), "alt", "hotkey modifiers")
end)

test("repeated presses cycle through same-letter apps in a stable order", function()
  local finder = newApp("Finder", "com.apple.finder")
  local safari = newApp("Safari", "com.apple.Safari")
  local spotify = newApp("Spotify", "com.spotify.client")
  local slack = newApp("Slack", "com.tinyspeck.slackmacgap")
  local fakeHs, host = newHost({ finder, safari, spotify, slack }, finder)
  _G.hs = fakeHs

  local hamcmd = dofile("HamCmd.spoon/init.lua")
  hamcmd:start()

  host.watcherCallback(safari:name(), fakeHs.application.watcher.activated, safari)
  host.watcherCallback(spotify:name(), fakeHs.application.watcher.activated, spotify)
  host.watcherCallback(slack:name(), fakeHs.application.watcher.activated, slack)

  host.hotkeys.s.callback()
  host.watcherCallback(slack:name(), fakeHs.application.watcher.activated, slack)
  assertEqual(host.frontmost, slack, "first app")

  host.hotkeys.s.callback()
  host.watcherCallback(spotify:name(), fakeHs.application.watcher.activated, spotify)
  assertEqual(host.frontmost, spotify, "second app")

  host.hotkeys.s.callback()
  assertEqual(host.frontmost, safari, "third app")
end)

test("pressing the key for the only matching frontmost app hides it", function()
  local safari = newApp("Safari", "com.apple.Safari")
  local fakeHs, host = newHost({ safari }, safari)
  _G.hs = fakeHs

  local hamcmd = dofile("HamCmd.spoon/init.lua")
  hamcmd:start()
  host.hotkeys.s.callback()

  assertEqual(safari.hideCount, 1, "hide count")
  assertEqual(safari.activationCount, 0, "activation count")
end)

test("an unconfigured key does not launch an app remembered from an earlier run", function()
  local safari = newApp("Safari", "com.apple.Safari")
  local firstHs = newHost({ safari }, safari)
  _G.hs = firstHs
  dofile("HamCmd.spoon/init.lua"):start()

  local secondHs, secondHost = newHost({}, nil)
  _G.hs = secondHs
  dofile("HamCmd.spoon/init.lua"):start()
  secondHost.hotkeys.s.callback()

  assertEqual(secondHost.launchedBundleID, nil, "launched bundle ID")
end)

test("only Right Option enables and consumes the letter shortcuts", function()
  local finder = newApp("Finder", "com.apple.finder")
  local safari = newApp("Safari", "com.apple.Safari")
  local fakeHs, host = newHost({ finder, safari }, finder)
  _G.hs = fakeHs
  dofile("HamCmd.spoon/init.lua"):start()

  host:setRawFlags(fakeHs.eventtap.event.rawFlagMasks.alternate)
  assertEqual(host:press("s"), false, "Left Option shortcut consumption")

  host:setRawFlags(fakeHs.eventtap.event.rawFlagMasks.deviceRightAlternate)
  assertEqual(host:press("s"), true, "Right Option shortcut consumption")
  assertEqual(safari.activationCount, 1, "Right Option app activation count")

  host:setRawFlags(0)
  assertEqual(host:press("s"), false, "shortcut consumption after releasing Right Option")
end)

if failures > 0 then
  os.exit(1)
end
