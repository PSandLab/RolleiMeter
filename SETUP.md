# RolleiMeter

The GitHub workflow builds an **unsigned** .ipa. Sign and install it with your own signer.

## Build
Actions tab > Build IPA > Run workflow. Download the `RolleiMeter-ipa` artifact, unzip, sign `RolleiMeter.ipa`.

## Using it
- Opens straight to the camera. The viewfinder takes all the space the controls don't.
- **Matrix / Highlight** chips switch the metering. **Tap the viewfinder** to spot meter that point (the badge shows SPOT, pinch resizes the circle). Tap a chip to leave spot.
- Aperture bar: shutter speed above each aperture. An aperture turns **red when its shutter speed is slower than 1/60**. `500+` (orange) means even 1/500 can't hold back enough light. `<2` means slower than 1/2.
- Tap an aperture to select it for depth of field. Long-press to set the golden aperture (green).
- Distance dial (LiDAR iPhones): Rollei 35 focusing scale. Triangle = distance to the metered point. Orange band = depth of field at the selected aperture. Closest focus (0.9 m / 3 ft) is green. Closer than that, the dial goes red and flashes TOO CLOSE. Tap the dial to switch meters/feet.
- Round button freezes exposure and distance. Tap again to release.
- Gear: ISO/DIN, meters/feet, golden aperture, calibration.

## Metering
- **Matrix:** centre-weighted average of the frame, placed at middle grey.
- **Highlight:** same, except if the bright end of the scene (98th percentile) would land more than 1.5 stops above grey, the reading is raised so it sits at +1.5. It can only ever give the same or less exposure than matrix.
- **Spot:** the circle you tapped.
- **The preview shows the metered exposure.** The phone's exposure is steered so the metered reference sits at middle grey. Tap a bright spot and the whole view darkens by the same number of stops the shutter speed moves. Highlight mode darkens by exactly the protection it applies. The preview takes a second or two to settle after a change; the shutter speeds don't wait for it.
- HDR, low-light boost and wide colour are switched off to keep the pixels plain. True RAW isn't available for live metering on iOS.

## Calibrate (optional)
Leave it at 0 and shoot a roll first. To check: in full sun at ISO 100, the ƒ/16 column should show about 1/125. Faster? Tap Calibration down. Slower? Up. Each tap is 1/3 stop.

## Notes
- Depth of field uses a 0.03 mm circle of confusion and the Sonnar's 40 mm focal length.
- LiDAR reads roughly 0.3 m to 5 m. Beyond that the dial shows a dash. Non-LiDAR phones don't show the dial.
- Untested on a device. If something looks wrong, say what it does.
