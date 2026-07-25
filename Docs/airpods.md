# AirPods

## Motion Unavailable

AirPods head gestures use `CMHeadphoneMotionManager`. If headphone motion is unavailable, cerberus cannot receive nod or shake samples.

Check:

- the AirPods model supports headphone motion
- the AirPods are connected and worn
- Settings shows `No AirPods motion sample is available yet.` when calibration is pressed before samples arrive
- `Log gesture validation CSV` does not append rows to `~/Library/Application Support/cerberus/head-gesture-validation.csv`

Recovery steps:

- reconnect the AirPods
- quit and relaunch cerberus
- reset gesture thresholds, then press `Calibrate AirPods` after motion samples start
- use `Scripts/evaluate_head_gestures.sh ~/Library/Application\ Support/cerberus/head-gesture-validation.csv` after collecting samples

If motion remains unavailable, use manual `Listen`, Control-Option-Space, media-key trigger, or wake phrase while recording the Mac model, macOS build, AirPods model, and firmware for a hardware report.
