# RolleiMeter: setup

The workflow builds an **unsigned** .ipa. Signing and installing is yours.

## Build
1. Create a **private** GitHub repo and upload this project (see the chat for the website steps).
2. Actions tab > Build IPA > Run workflow. Optionally set the bundle ID (default `com.example.rolleimeter`).
3. Download the `RolleiMeter-ipa` artifact, unzip it, sign `RolleiMeter.ipa` with your own signer.

No secrets needed.

## Using it
- Opens straight to the camera. Tap the preview to spot meter that point, pinch to resize the spot.
- Chips on the preview switch Matrix / Spot / Highlight.
- Aperture scale: shutter speed above each aperture. If an aperture can't expose correctly it turns red, shows a sun (too bright) or moon (too dark) instead of a speed, and the error in stops sits below it.
- Tap an aperture to select it for depth of field. Long-press to set the golden aperture (green).
- Distance dial (LiDAR iPhones): Rollei 35 focusing scale. Orange triangle = distance to the metered point. Orange band = depth of field at the selected aperture, with near and far limits underneath. Closest focus (0.9 m / 3 ft) is green. Tap the dial to switch meters/feet.
- Round button freezes exposure and distance. Tap again to release.
- Gear: ISO/DIN, meters/feet, golden aperture, calibration.

## Metering notes
- **Matrix:** centre-weighted average of the frame, placed at middle grey.
- **Highlight:** same as matrix, except if the bright end of the scene (98th percentile) would land more than 2 stops above grey, the reading is raised so the highlight sits at +2. It can only ever give the same or less exposure than matrix, never more. The preview is also shot 1.5 stops darker in this mode so bright areas don't clip.
- **Spot:** the phone's auto exposure follows the tapped point, so the spot sits near mid-grey where the reading is most accurate.
- HDR, low-light boost and wide colour are switched off to keep the pixels as plain as the camera allows.
- True RAW isn't available for live metering on iOS. Apple only gives RAW for single still photos.

## Calibrate (optional)
Leave it at 0 and shoot a roll first. To check: in full sun at ISO 100, the ƒ/16 column should show about 1/125. Shows faster? Tap Calibration down. Slower? Up. Each tap is 1/3 stop.

## Notes
- Depth of field uses a 0.03 mm circle of confusion and the Sonnar's 40 mm focal length.
- LiDAR reads roughly 0.3 m to 5 m. Beyond that the dial shows a dash. Non-LiDAR phones don't show the dial. Metering works either way.
- Untested on a device. If something looks wrong, say what it does.
