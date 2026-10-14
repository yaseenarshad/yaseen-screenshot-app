<p align="center">
  <img src="docs/assets/icon.png" width="112" alt="The icon of Yaseen Screenshot: a white Y in four crop corners">
</p>

<h1 align="center">Yaseen Screenshot</h1>

<p align="center">
  <b>Press one hotkey. Drag a box. Done.</b><br>
  The image is on your clipboard and in your folder, on every monitor you plug in.
</p>

<p align="center">
  <a href="https://github.com/yaseenarshad/yaseen-screenshot-app/releases/latest"><b>Download for Mac</b></a><br>
  <sub>Free · Apple Silicon · macOS 14 or later · under 1 MB</sub>
</p>

<p align="center">
  <img src="docs/assets/hero.gif" width="860" alt="Press Shift-Command-D, the screen freezes, drag a box, draw a rectangle and an arrow, click Done. The image is copied and saved.">
</p>

## The problem

I used the same screenshot app for years. Then I plugged in a second monitor, and it stopped working.

I looked for a replacement. Each one had the same small problems:

- **The screen moves while you select.** The thing that you wanted is gone before you finish the box.
- **You need a second app to draw one arrow.** Take the shot, open it, mark it, save it again.
- **File or clipboard: pick one.** You wanted to paste it now and also find it later.
- **Big apps for a small job.** Many desktop apps carry a full web browser inside and are 200 MB or more.

## The answer

So I built the app that I wanted. It does one job, and it is fast.

1. **It freezes every screen at once.** Nothing moves while you select.
2. **You mark the image right there.** No second app.
3. **It copies and saves, each time.** No choice, no extra step.

## What you can do

### Freeze every screen at once

Press the hotkey, and all your screens stop. A laptop screen and a wide monitor freeze together, each one at its own sharpness.

**So what:** you select what you saw, not what the screen became a second later. And a second monitor is not a problem. That is the reason this app exists.

<p align="center">
  <img src="docs/assets/two-monitors.png" width="860" alt="Two monitors, frozen and dim at the same moment, with a bright box on one of them">
</p>

### Mark it up, then fix it

Draw a rectangle, an ellipse, an arrow, a free line, a highlight or a note. Three sizes and six colours. Then click **Select** to move a mark, change its size, change its colour, or delete it.

**So what:** a mark in the wrong place is not a reason to start again.

<p align="center">
  <img src="docs/assets/annotate.gif" width="860" alt="Draw a rectangle, an arrow, a highlight and a note. Then select the rectangle and move it.">
</p>

### Grab a full window with one click

Move the pointer over a window, and it becomes bright. Click, and the box is exactly that window.

**So what:** you do not drag along the edges and miss by two pixels.

<p align="center">
  <img src="docs/assets/click-a-window.gif" width="860" alt="The window below the pointer becomes bright. One click puts the box on that window.">
</p>

### Paste it now, find it later

Click **Done**, press **Enter**, or double-click in the box. The image goes to your clipboard and into your Pictures folder, each time, as a sharp PNG.

**So what:** you paste it into your message immediately, and the file is still there next week.

<p align="center">
  <img src="docs/assets/result.png" width="720" alt="A finished screenshot with marks, as the app saves it">
</p>

### Make it yours

Change the hotkey. Change the save folder. Let the app open when you log in. That is the full list of settings.

**So what:** it fits your keys and your folders, and there is nothing else to learn.

<p align="center">
  <img src="docs/assets/settings.png" width="560" alt="The settings: Hotkey, Save folder, Open at login">
</p>

## Small and fast

Each number is measured, not estimated.

| What | Number |
| -- | -- |
| The app | 880 KB |
| The download | 333 KB |
| From the hotkey to the frozen screen | 109 ms on average (67 to 183 ms, 20 real captures on an M1 Max) |
| Outside code in the app | None |
| Automatic tests | 89 |

It is a native Mac app, written in Swift. It lives in the menu bar and has no Dock icon. It has no network code, so your screen stays on your Mac.

## Get it in one minute

1. [**Download the latest `.dmg`**](https://github.com/yaseenarshad/yaseen-screenshot-app/releases/latest).
2. Open it. Drag **Yaseen Screenshot** to **Applications**.
3. Open the app. macOS stops it the first time. Go to **System Settings › Privacy & Security** and click **Open Anyway**. You do this one time.
4. The app asks for the **Screen Recording** permission. Turn it on. Each screenshot app needs this.
5. Press **Shift-Command-D**.

The app needs a Mac with Apple Silicon and macOS 14 or later.

## Questions

**Is it free?**
Yes. The code is open, with the [MIT license](LICENSE). You can read it, build it and change it.

**Why does macOS say "Open Anyway"?**
Apple has not notarized the app. That needs a paid Apple developer account. The code is in this repo, and you can build the app yourself.

**Why does it need the Screen Recording permission?**
macOS asks each app that reads the screen. The app reads the screen only when you press the hotkey. It has no network code.

**macOS asked for the permission again after an update. Why?**
The download has a simple signature, and macOS sees an update as a new app. If you build the app yourself with a fixed certificate, macOS asks one time only. The [developer page](docs/DEVELOPMENT.md) tells how.

**I do not see the icon in the menu bar.**
On a MacBook with a notch, a full menu bar hides some icons. Hold Command and drag your icons to put them in a different order. The hotkey works also when the icon is hidden.

**Does it run on an Intel Mac or on Windows?**
No. It is for Apple Silicon Macs only.

**Where is the rest?**
The [guide](docs/GUIDE.md) has each detail of the app. The [developer page](docs/DEVELOPMENT.md) tells how to build, sign and release it.

<p align="center">
  <br>
  <a href="https://github.com/yaseenarshad/yaseen-screenshot-app/releases/latest"><b>Download Yaseen Screenshot for Mac</b></a><br>
  <sub>Free · under 1 MB · one hotkey</sub>
</p>
