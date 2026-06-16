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

Official API surface used:

- `SNAudioStreamAnalyzer`
- `SNClassifySoundRequest`
- `SNClassificationResult`
- `MLModel.load(contentsOf:)`
- `MLModel.compileModel(at:)`
