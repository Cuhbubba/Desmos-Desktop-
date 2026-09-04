# Desmos Desktop (macOS)

A floating Desmos graphing/scientific calculator that sits infront of every window (full screen apps too).
Toggle visibility with keystroke (default **⌥ ⇧ D**). Both graphing and scientific calculator.  

Recommended: Leave the launch at login in the settings toggled ON to be able to pull up the app with just the keystroke rather than needing to relaunch it.
Use the (X) close out button to hide the app, but have it be able to be pulled back up using the keystroke rather than quitting the app. 


## Install

1. Download **`DesmosDesktop-mac.zip`**  and unzip it.
2. Drag **Desmos Desktop.app** into your **Applications** folder.
3. Open it once. Because this is a free, unsigned app (not notarized with Apple), macOS will
   block the first launch. Do **one** of the following:
   - **macOS 15 Sequoia or newer:** open the app (it'll say it couldn't be verified) → go to
     **System Settings → Privacy & Security**, scroll down, click **Open Anyway**, then open the app again.
   - **macOS 13–14:** right-click the app → **Open** → **Open**.
   - **Terminal (any version):**
     ```bash
     xattr -cr "/Applications/Desmos Desktop.app"
     ```
4. The calculator appears and a **ƒ** icon shows in your menu bar. Press **⌥ ⇧ D** to hide/show it.

Note: Requires macOS 13 Ventura or newer



MIT — see [LICENSE](LICENSE).
