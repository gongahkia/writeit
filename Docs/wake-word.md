# Wake Word

`Wake phrase` defaults to live SpeechAnalyzer transcription. This is easy to configure, but it keeps the microphone and speech recognizer active while armed.

For a dedicated on-device wake model, add a SoundAnalysis/Core ML config at:

```sh
~/Library/Application Support/cerberus/wake-word-sound-classifier.json
```

Example:

```json
{
  "modelPath": "/Users/me/Models/CerberusWakeWord.mlmodelc",
  "targetLabels": ["hey_cerberus"],
  "confidenceThreshold": 0.85,
  "overlapFactor": 0.5,
  "windowDurationSeconds": 1.0,
  "computeUnits": "cpuAndNeuralEngine"
}
```

Then enable `Wake phrase` and `Use sound wake model` in Settings.

The model must be a Core ML sound classifier accepted by `SNClassifySoundRequest`: audio input, classification dictionary output, and labels matching `targetLabels`. `.mlmodelc` is loaded directly; `.mlmodel` is compiled at startup.

If the config or model fails to load, cerberus falls back to SpeechAnalyzer phrase matching and reports the error in Settings.

## Collect Samples

Use the sample collector to build a local dataset before training a SoundAnalysis/Core ML classifier:

```sh
Scripts/record_wake_samples.sh --label hey_cerberus --count 40 --seconds 1.5 --note quiet
Scripts/record_wake_samples.sh --label background --count 40 --seconds 1.5 --note room_noise
```

The collector writes mono 16 kHz WAV files and a `manifest.jsonl` file under:

```sh
~/Library/Application Support/cerberus/wake-word-samples/
```

Labels become directory names, which matches the class-folder layout expected by common audio-classifier training workflows. Capture positive wake phrase samples and negative classes such as `background`, `music`, `keyboard`, `walking`, and `noisy_room`, including AirPods microphone samples if that is the target runtime.

After training/exporting a Core ML sound classifier, point `wake-word-sound-classifier.json` at the resulting `.mlmodelc` or `.mlmodel`.

Official API surface used:

- `SNAudioStreamAnalyzer`
- `SNClassifySoundRequest`
- `SNClassificationResult`
- `MLModel.load(contentsOf:)`
- `MLModel.compileModel(at:)`
- `AVAudioRecorder`
