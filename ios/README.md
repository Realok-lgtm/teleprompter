# Teleprompter — native iPhone app

Films you on the front camera with your script scrolling on top, records
**constant 30fps** video (no TikTok stutter), and saves **straight to your
camera roll**.

## Put it on your iPhone (first time, ~3 minutes)

1. Open the project:
   ```
   open ios/Teleprompter.xcodeproj
   ```
2. In Xcode's left sidebar click the blue **Teleprompter** project → **Signing & Capabilities** tab.
3. Tick **Automatically manage signing**, and under **Team** pick your Apple ID.
   (If none listed: Xcode → Settings → Accounts → **+** → sign in with your Apple ID.)
4. Plug your iPhone into the Mac with a cable. Unlock it and tap **Trust** if asked.
5. At the top of Xcode, click the device dropdown and choose **your iPhone**.
6. Press the **▶ Run** button (or ⌘R).
7. First run only: on the iPhone go to **Settings → General → VPN & Device Management**,
   tap your developer profile, and tap **Trust**. Then tap the app icon to launch.

After that, the app icon stays on your Home Screen and you just tap it.

## Free vs paid Apple account
- **Free Apple ID:** works, but Apple expires the app after **7 days** — re-run
  from Xcode (steps 5–6) to refresh it.
- **Apple Developer Program ($99/yr):** the app stays installed for a year and
  can be sent via TestFlight.

## Rebuilding the project file
The `.xcodeproj` is generated from `project.yml`. If you edit `project.yml`:
```
cd ios && xcodegen generate
```

## Using it
- **Pencil** → type/paste your script.
- **Play / Pause** scrolls; **drag up/down** anytime to reposition.
- **Speed** and **Size** sliders; **Font** picker.
- **Record** films you (clean video, no text); **Stop** saves to your camera roll
  and shows a green ✓.
- Camera-flip and restart buttons next to the font picker.
