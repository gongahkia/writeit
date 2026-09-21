# WriteIt cross-platform contracts

These fixtures define the selected user-visible behavior shared by native implementations. They are not a shared runtime or a cross-platform persistence format.

- `capture-lifecycle/v1.json` defines allowed capture phase changes.
- `recognition-languages/v1.json` defines the v1 language set and the English fallback rule.

The macOS implementation informs these behaviors. Windows tests consume the fixtures; a later compatibility milestone may add equivalent macOS fixture tests.
