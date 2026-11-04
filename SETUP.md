# RolleiMeter

A light meter and film logbook for people shooting film. Native SwiftUI, iOS 17 and later, with Liquid Glass on iOS 26 and later.

The GitHub workflow builds an **unsigned** .ipa. Sign and install it with your own signer.

## Build
Actions tab > Build IPA > Run workflow. Download the `RolleiMeter-ipa` artifact, unzip, sign `RolleiMeter.ipa`. Locally, `python3 build.py` does the same and drops the file in `~/Downloads`.

## The viewfinder
The camera fills the middle of the screen. Everything else is a floating readout tile, so nothing is hidden behind a menu.

- **Viewfinder.** Tap to measure the distance there (the white bracket is where LiDAR reads). Press, hold and drag to spot meter that point; pinch to resize the circle. The two points are independent: meter the face, focus on the eyes.
- **Shutter.** The metered speed for the selected aperture. The wheel turns to the gear's nearest marked speed. Accent colour = correct, orange = slower than 1/60, red = out of range (the amount over or under is shown instead of "seconds").
- **Film.** Film name, the speed you are rating it at, and the camera it lives in. **Drag** sideways to rate the ISO in third stops, **tap** to open the logbook, **hold** to snap back to the box speed.
- **Frame.** Frame number against the roll length, plus how many frames are logged. Tap to open the frame list.
- **Aperture.** Drag sideways to pick a stop. **Tap** for auto aperture (the widest stop that still gives a usable shutter speed; "AUTO" lights in green, orange or red), **hold** to jump back to the default stop.
- **Focus.** Manual focus on the lens's own scale, 0.9 m at the left and infinity at the right. Slide to rack focus. The **amber band** is the depth of field at the selected aperture, so you can see what will be sharp, and the number at the top right is the distance you set (tap to switch metres / feet). **Double-tap** to return to autofocus. "Autofocus" reads green while the LiDAR measurement is valid and red when the subject is closer than the lens can focus.
- **Shutter button** (bottom right), or a volume button, freezes exposure and distance — "hold". While held it becomes a discard button and a log button; the log button saves the frame with its photo, then releases.
- **Metering menu** (left of the shutter button): Multi, Bright or Spot.
- **Top bar.** The ±EV pill opens exposure compensation; the stack icon opens the logbook on the Scans tab; the gear opens Settings.

## The logbook
A three-tab sheet, all standard iOS lists.

- **Roll.** The loaded stock and the body side by side, both at the same weight: artwork, serif name, one line of detail. Tapping either one opens it. Below them a strip of 35 mm film — **press and hold** and the strip winds onto the spool frame by frame, then the roll clears and the next one starts at frame 1.
- **Film library.** Searchable, grouped by brand, filtered by Colour / B&W / Slide / Custom. Pick a stock, choose the speed variant, the roll length, and whether it is expired (the app adds about a stop of compensation per decade for colour negative). **Press and hold** the bar to load it — the log pops back to the roll when it is in the camera. Custom stocks are kept in the Custom tab.
- **Camera & Lens.** Brands first (Popular, plus a Vintage & rare shelf for one-off and discontinued makers), then a brand's bodies, then the lens. A fixed-lens body shows its lens as the subject of the screen and a single **hold to mount** control — there is nothing to choose. Interchangeable bodies list "Body only", "Use an adapter" (any lens, f/1.2 to f/32) and the native-mount lenses; tapping an option selects it, the hold mounts it. Lenses are listed as `24mm f/2.8` with the number of versions; versions (New FD, AI-S, Pre-AI …) are chosen on the lens page, which ends in its own hold-to-mount. Mounting closes the whole catalog and returns to the roll. "Enter a custom camera" sits under Custom on every camera screen, and the custom form only asks for a name and a mount before offering the stop ranges.
- **Frames.** Every logged frame grouped by roll, with a thumbnail, the exposure and the note. Swipe to delete; tap for the full record, the photo viewer and a share action.
- **Scans.** Import a folder of lab scans or individual files, match them to frames, nudge the match with a stepper, then write EXIF/XMP into the files or share them.

## Metering
- **Multi:** centre-weighted average of the frame, placed at middle grey.
- **Bright:** same, except if the bright end of the scene (98th percentile) would land more than 1.5 stops above grey, the reading is raised so it sits at +1.5. It can only ever give the same or less exposure than Multi.
- **Spot:** the circle you held.
- **The preview shows the metered exposure.** The phone's exposure is steered so the metered reference sits at middle grey. Tap a bright spot and the whole view darkens by the same number of stops the shutter speed moves. Bright mode darkens by exactly the protection it applies.

## Calibrate (optional)
Leave it at 0 and shoot a roll first. To check: in full sun at ISO 100, f/16 should show about 1/125. Faster? Tap Calibration down. Slower? Up. Each tap is 1/3 stop.

## Design notes
- Type is **Geist** (Sans for interface copy, Mono for readouts, Serif for the wordmark and film names), bundled under the SIL Open Font License.
- Colours come from the system: `systemBackground`, `secondarySystemGroupedBackground`, `.label`, `.separator`, plus one amber accent declared in the asset catalog (`AccentColor`).
- Readouts use the system material; Liquid Glass is reserved for the control layer (the shutter button, the EV pill and the round buttons) exactly as Apple's guidance asks.
- Text uses Dynamic Type styles in the sheets and a `k`-scaled type ramp in the meter, so the instrument stays legible at any screen size.
- The logbook, gear picker and scan matcher are plain `List`/`Form` flows: system rows, separators, swipe actions, search fields and empty states.

## Notes
- The sensor is natively landscape, so metering and LiDAR read it unrotated. Turning the phone between the two landscape orientations only turns the preview.
- Depth of field uses a 0.03 mm circle of confusion and the configured lens focal length.
- LiDAR reads roughly 0.3 m to 5 m. Beyond that the distance readout disappears. Non-LiDAR phones have no distance readout.
- iOS sets focus as a 0 to 1 lens position, not a distance. The app converts your distance to that using a typical focal length for the main camera, so the distance on the slider is approximate. Trust the peaking for what is actually sharp, and compare with the LiDAR reading in autofocus.
- Peaking is only calculated while you are using the slider, so it costs nothing the rest of the time. If it lights up too much or too little, change `peakThreshold` at the top of `CameraMeter.swift`.
