# RolleiMeter

The GitHub workflow builds an **unsigned** .ipa. Sign and install it with your own signer.

## Build
Actions tab > Build IPA > Run workflow. Download the `RolleiMeter-ipa` artifact, unzip, sign `RolleiMeter.ipa`.

## Using it
Landscape only, both directions. Dark, with nothing hidden behind menus: every control is on the screen, laid out on a 12 x 6 grid.

- **Viewfinder** (centre). The live camera. **Tap** to measure distance there (white bracket = where LiDAR reads). **Press, hold and drag** to spot meter that point (circle; pinch resizes). The two points are independent: meter the face, focus on the eyes.
- **SHUTTER** (top left). The metered shutter speed for the selected aperture. The wheel turns to the Rollei's nearest marked speed. Yellow = correct, orange = slower than 1/60, red = out of range (the amount over or under is shown instead of "sec").
- **METER** (middle left). Multi, Bright (highlights) or Spot. Tap to switch.
- **FILM** (bottom left, yellow). Film speed. **Drag** sideways to change it in thirds of a stop, **tap** to switch ISO / DIN, **hold** to jump back to 100.
- **EV bar** (top centre). Exposure compensation, -2 to +2 in thirds. Drag along the bar, double-tap to reset to 0.
- **APERTURE** (top right). Drag sideways to pick f/2.8 to f/22. **Tap** for auto aperture (picks the widest stop that still gives a usable shutter speed; an "A" lights in green / orange / red), **hold** to jump back to f/8.
- **FOCUS** (middle right). Manual focus on the Rollei's own scale: 0.9 m at the left, infinity at the right, with the lens's marked distances. Put a finger on the panel and **slide left / right**: the lens follows. The **red band** is the depth of field at the selected aperture, so you can see at a glance what will be sharp, and the **number** at the top right is the distance you've set (tap it to switch metres / feet). While you slide, the viewfinder dims and the sharp areas turn red (focus peaking); lift your finger and the red stays for two seconds. **Double-tap** to go back to autofocus. Top left says AF or MF. In autofocus, LiDAR iPhones show the measured distance and its red band instead.
- **Round button** (bottom right), or a **volume button**, freezes exposure and distance ("hold"). Press again to release.
- **SET** (top right of the viewfinder): units, calibration and arm offset. Top left of the viewfinder shows EV, HOLD / SPOT and any compensation.
- Full-screen: status bar and home indicator are hidden (swipe up from the bottom edge to reach the home bar).

## Metering
- **Multi:** centre-weighted average of the frame, placed at middle grey.
- **Bright:** same, except if the bright end of the scene (98th percentile) would land more than 1.5 stops above grey, the reading is raised so it sits at +1.5. It can only ever give the same or less exposure than Multi.
- **Spot:** the circle you held.
- **The preview shows the metered exposure.** The phone's exposure is steered so the metered reference sits at middle grey. Tap a bright spot and the whole view darkens by the same number of stops the shutter speed moves. Bright mode darkens by exactly the protection it applies. The preview takes a second or two to settle after a change; the shutter speeds don't wait for it.
- HDR, low-light boost and wide colour are switched off to keep the pixels plain. True RAW isn't available for live metering on iOS.

## Calibrate (optional)
Leave it at 0 and shoot a roll first. To check: in full sun at ISO 100, f/16 should show about 1/125. Faster? Tap Calibrate down. Slower? Up. Each tap is 1/3 stop.

## Notes
- The sensor is natively landscape, so metering and LiDAR read it unrotated. Turning the phone between the two landscape orientations only turns the preview.
- Depth of field uses a 0.03 mm circle of confusion and the Sonnar's 40 mm focal length.
- LiDAR reads roughly 0.3 m to 5 m. Beyond that the distance readout disappears. Non-LiDAR phones have no distance readout.
- iOS sets focus as a 0 to 1 lens position, not a distance. The app converts your distance to that using a typical focal length for the main camera, so the distance on the slider is approximate. Trust the red peaking for what is actually sharp, and compare with the LiDAR reading in autofocus to see how close the two are.
- The red band uses the Rollei's depth of field (40 mm lens, 0.03 mm circle of confusion), not the phone's.
- Peaking is only calculated while you are using the slider, so it costs nothing the rest of the time. If it lights up too much or too little, change `peakThreshold` at the top of `CameraMeter.swift` (higher = less red); `peakWash` sets how strong the red fill is.
- Untested on a device. If something looks wrong, say what it does.
