# HamCmd

HamCmd is a small Hammerspoon Spoon for switching applications with `Hyper + letter`.
It is designed for a Karabiner-Elements mapping that emits Hyper
(`Command + Option + Control + Shift`) from Right Option.

## Behaviour

- The first letter of each running Dock application's name becomes its shortcut.
- A letter focuses the most recently activated matching application.
- Repeating the letter cycles through all running applications with that initial.
- If only the frontmost application matches, repeating its letter hides it.
- If no matching application is running, HamCmd launches the application most
  recently remembered for that letter.

Assignments and recency are stored with `hs.settings`, so they survive Hammerspoon
reloads. HamCmd intentionally has no switcher UI or static assignments.

## Install

Symlink the Spoon into the Hammerspoon configuration directory:

```sh
mkdir -p ~/.hammerspoon/Spoons
ln -s `pwd`/HamCmd.spoon ~/.hammerspoon/Spoons/HamCmd.spoon
```

Add this to `~/.hammerspoon/init.lua`:

```lua
hs.loadSpoon("HamCmd")
spoon.HamCmd:start()
```

Then reload the Hammerspoon configuration. Hammerspoon must have Accessibility
permission for global shortcuts and application activation.

## Test

```sh
luajit test/hamcmd_test.lua
```
