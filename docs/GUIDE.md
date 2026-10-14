# The guide

How to install and use Yaseen Screenshot, with each detail. The short version is on the [first page](../README.md).

## Install from a release

1. If you use the old app Snip, quit it first. Snip and this app both use Shift-Command-D.
2. Open the [releases page](https://github.com/yaseenarshad/yaseen-screenshot-app/releases/latest) and download `Yaseen-Screenshot-<version>-arm64.dmg`.
3. Open the `.dmg`. Drag "Yaseen Screenshot" onto the "Applications" link.
4. Start the app from `/Applications`. macOS stops it the first time, because the app is not notarized.
5. Open System Settings, then Privacy & Security. Click "Open Anyway" next to "Yaseen Screenshot". You do this one time.
6. The app asks for the Screen Recording permission. Open System Settings, Privacy & Security, Screen & System Audio Recording. Turn on "Yaseen Screenshot".
7. If macOS asks, quit the app and open it again. Then press Shift-Command-D.

### If you do not see the menu bar icon

A MacBook with a notch hides the icons that do not fit. A full menu bar can put an icon behind the notch.

- At its first start, the app asks macOS for a place to the right of the notch.
- To move an icon, hold Command and drag it. Put the icons that you use most at the right, near the clock.
- The hotkey works also when the icon does not show.

## Use

1. Press Shift-Command-D, or select "Take screenshot" in the menu. All screens freeze.
2. Drag a box. Or click a window: the window below the pointer is bright, and a click puts the box on it.
3. Adjust the box. Drag inside it to move it. Drag a handle to change its size. A right-click removes it.
4. Draw marks with the toolbar below the box, if you want.
5. Press Enter, or click Done. A double-click in the box does the same when nothing is selected in the toolbar.

Esc or Cancel stops the capture. Nothing is copied and nothing is saved. Esc first closes an open text, and then clears a selected mark.

### The toolbar

- **Select:** click a mark to select it. Drag it to move it. Drag a handle to change a rectangle, an ellipse or an arrow. Delete removes it. A double-click on a text opens the text again.
- **Rectangle, Ellipse, Arrow, Pen, Highlight, Text:** drag in the box to draw. For Text, click, type, and press Return.
- **Sizes and colours:** Thin, Medium and Thick, and six colours. They show when a tool or a mark is selected, and they change the selected mark. Each tool starts with Thick and red. Highlight starts with amber.
- **Undo:** the button or Command-Z. Shift-Command-Z puts the change back.

While marks exist, the box does not move, and a right-click does nothing.

### Where the image goes

- On the clipboard, each time.
- In the save folder, each time. The default folder is `~/Pictures`.
- The file name is `Snip<date>_<number>.png`, for example `Snip20261012_16.png`. The number is 1 more than the highest number of that day. The app never writes over a file.

### The menu and the settings

The menu has four rows: "Take screenshot", "Open screenshots folder", "Settings…" and "Quit".

"Settings…" has three rows:

- **Hotkey:** click the field and press the new keys. It needs Command, Control or Option. The default is Shift-Command-D.
- **Save folder:** the default is `~/Pictures`.
- **Open at login:** the default is on. It works only in the installed app.
