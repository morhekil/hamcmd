# HamCmd

HamCmd is a small Hammerspoon Spoon for switching applications with
`Right Option + letter`. It distinguishes the physical Right Option key inside
Hammerspoon, leaving normal Left Option shortcuts untouched. Karabiner-Elements
is not required.

## Behaviour

- An unconfigured letter focuses the most recently activated matching Dock app,
  then repeated presses cycle through the other running matches.
- App names match their displayed-name initial after invisible prefixes are
  ignored. Vendor-prefixed names also match the product initial, so Microsoft
  Excel matches both `M` and `E` without configuration.
- Unconfigured letters never launch apps. If there is no running match, nothing
  happens.
- A fixed letter always targets its configured bundle ID. It launches the app when
  absent and focuses it when it is running in the background.
- Pressing a fixed letter while its app is already frontmost starts a stable cycle
  through the other running apps whose names begin with that letter, then returns
  to the fixed app.
- Pausing longer than `cycleTimeout` rebuilds a dynamic cycle from current app
  recency, or resets a fixed cycle so the next press focuses the fixed app.

HamCmd keeps only in-memory application recency and cycle state. It does not
persist inferred matches or launch apps that are not explicitly configured.

## Install

Symlink the Spoon into the Hammerspoon configuration directory:

```sh
mkdir -p ~/.hammerspoon/Spoons
ln -s `pwd`/HamCmd.spoon ~/.hammerspoon/Spoons/HamCmd.spoon
```

Add this to `~/.hammerspoon/init.lua`, using bundle IDs for fixed shortcuts:

```lua
hs.loadSpoon("HamCmd")

spoon.HamCmd.shortcuts = {
  c = "com.google.Chrome",
}
spoon.HamCmd.cycleTimeout = 1.0
spoon.HamCmd:start()
```

Shortcut keys must be lowercase. To look up an application's bundle ID:

```sh
osascript -e 'id of app "Google Chrome"'
```

Then reload the Hammerspoon configuration. Hammerspoon must have Accessibility
permission for global shortcuts and application activation.

## Test

```sh
luajit test/hamcmd_test.lua
```
