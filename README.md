# Swinger

Minimalist swing timer addon for WoW Forever.

## Features
- Independently show or hide Main Hand, Off Hand, and Ranged swing bars
- Smooth progress fill and optional countdown and labels
- Custom bar fill/text colours, font size, width, height, and spacing
- Movable bars with lock-to-click-through functionality
- Settings preview and persistent preferences
- Uses WoW Forever native `PLAYER_SWING` event

## Installation
Remove the prior `XenSwing` addon folder, then copy `Swinger/` into your `Interface/AddOns/` directory.

**Before publishing:** verify and update the `## Interface:` value in `Swinger/Swinger.toc` to the value actually tested on your client.

## Commands
- `/swinger` — Open settings
- `/swinger lock` — Toggle position lock
- `/swinger reset` — Reset position
- `/xswing` — Legacy shortcut

## Updating from XenSwing
The addon loads the prior `XenSwingDB` saved variable as a one-time fallback if no `SwingerDB` exists.

## Compatibility
WoW Forever; other clients untested.
