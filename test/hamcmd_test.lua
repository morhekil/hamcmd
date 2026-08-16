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

local function newHost(apps, initialFrontmost, settingsStore)
  local host = {
    apps = apps,
    frontmost = initialFrontmost,
    hotkeys = {},
    settingsStore = settingsStore or {},
  }

  for _, app in ipairs(apps) do
    app._host = host
  end

  local hs = {
    application = {},
    hotkey = {},
    settings = {},
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

  function hs.hotkey.bind(modifiers, key, callback)
    host.hotkeys[key] = {
      modifiers = modifiers,
      callback = callback,
    }
    return {}
  end


  function hs.settings.get(key)
    return host.settingsStore[key]
  end

  function hs.settings.set(key, value)
    host.settingsStore[key] = value
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

test("Hyper+letter focuses the most recently activated matching app", function()
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
  assertEqual(table.concat(host.hotkeys.s.modifiers, "+"), "cmd+alt+ctrl+shift", "Hyper modifiers")
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

test("a remembered app can be launched after it quits and Hammerspoon reloads", function()
  local settingsStore = {}
  local safari = newApp("Safari", "com.apple.Safari")
  local firstHs = newHost({ safari }, safari, settingsStore)
  _G.hs = firstHs
  dofile("HamCmd.spoon/init.lua"):start()

  local secondHs, secondHost = newHost({}, nil, settingsStore)
  _G.hs = secondHs
  dofile("HamCmd.spoon/init.lua"):start()
  secondHost.hotkeys.s.callback()

  assertEqual(secondHost.launchedBundleID, "com.apple.Safari", "launched bundle ID")
end)

if failures > 0 then
  os.exit(1)
end
