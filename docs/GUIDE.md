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

### If macOS asks for the permission again after an update

The download from GitHub has a simple signature. Thus macOS sees an update as a new app, and asks for the Screen Recording permission again. Turn it on again.

If you build the app yourself with a fixed certificate, macOS asks one time only. The [developer page](DEVELOPMENT.md) tells how.

## Use

1. Press Shift-Command-D, or select "Take screenshot" in the menu. All screens freeze.
2. Drag a box. Or click a window: the window below the pointer is bright, and a click puts the box on it.
3. The Rectangle is on. Drag inside the box to draw. Drag outside it for a new box. Drag a handle to change its size. A right-click removes it. To move the box, click the Rectangle to turn it off, then drag inside the box.
4. Draw more marks with the toolbar below the box, or with its keys, if you want.
5. Press Enter, press the hotkey again, or click Done. A double-click in the box does the same, except with Select, Text or Number.

Esc or Cancel stops the capture. Nothing is copied and nothing is saved. Esc first closes an open text, and then clears a selected mark.

### The toolbar

- **Select:** click a mark to select it. Drag it to move it. Drag a handle to change a rectangle, an ellipse or an arrow. Drag a corner of a text to make it bigger or smaller. Delete removes it. A double-click on a text opens the text again. Command-C copies it, Command-X cuts it, and Command-V pastes a copy 16 points to the right and down. After a cut, the first paste goes to the same place. The copy stays until you copy or cut a different mark, or quit the app.
- **Rectangle, Ellipse, Arrow, Pen, Highlight, Text:** drag in the box to draw. For Text, click, type, and press Return. Return selects the text, so you can size it or move it at once. Press T for the next text.
- **Number:** click in the box to put a numbered circle: 1, 2, 3. The next number is the highest number in the box, plus 1.
- **Sizes and colours:** Thin, Medium and Thick, and six colours. They show when a tool or a mark is selected, and they change the selected mark. Each tool starts with Thick and red. Highlight starts with amber.
- **Undo:** the button or Command-Z. Shift-Command-Z puts the change back.

While marks exist, the box does not move, and a right-click does nothing.

### The toolbar keys

One key selects a tool, a size or a colour. Thus you can drag the box, press A, and drag an arrow at once.

| Key | Action |
| --- | --- |
| V | Select |
| R | Rectangle |
| O | Ellipse |
| A | Arrow |
| W or P | Pen |
| H | Highlight |
| T | Text |
| N | Number |
| 1, 2, 3 | Thin, Medium, Thick |
| 4 to 9 | Red, Amber, Green, Blue, Black, White |
| 1 to 9, 0 (a text is selected) | Font size 12, 16, 20, 24, 32, 40, 56, 72, 96, 128 |

- The keys are the keys of Yaseen Screendraw.
- A tool key always selects its tool. A second press keeps it. A click on the selected tool still clears it.
- A key works after the box exists. It does nothing during a drag. While you type a text, each key is for the text.
- Move the pointer onto the toolbar to see the keys. The tip of each button names its key too.

### Where the image goes

- On the clipboard, each time.
- In the save folder, each time. The default folder is `~/Pictures`.
- The file name is `Snip<date>_<number>.png`, for example `Snip20261012_16.png`. The number is 1 more than the highest number of that day. The app never writes over a file.

### The menu and the settings

The menu has four rows: "Take screenshot", "Open screenshots folder", "Settings…" and "Quit".

"Settings…" has four rows and the toolbar part:

- **Hotkey:** click the field and press the new keys. It needs Command, Control or Option. The default is Shift-Command-D.
- **Save folder:** the default is `~/Pictures`.
- **Play the screenshot sound:** the Mac screenshot sound when a capture is done. The default is on. macOS keeps it silent when "Play user interface sound effects" is off.
- **Open at login:** the default is on. It works only in the installed app.
- **Tool after you select an area:** the tool that is on when the box appears. The default is Rectangle. "None" turns no tool on: then a drag in the box moves it.
- **Toolbar keys:** click a key, then type the new key. A key is one letter, digit or punctuation mark, with no Command, Control or Option. A key that a different button has is refused. Esc stops. "Reset to the start keys" gives the keys of the table above again. A new key works in the next capture.
