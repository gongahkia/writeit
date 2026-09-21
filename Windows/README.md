# WriteIt for Windows

This is the focused Windows 11 x64 MVP. It is a native WinUI 3/MSIX app, not a rewrite of the macOS application. Its central package configuration pins the current stable Windows App SDK; update that pin only through a tested dependency change.

It provides local Windows OCR for the same six Latin-language choices as macOS, a global `Ctrl+Alt+Space` toggle shortcut, mouse and pen ink capture, encrypted local history, and a best-effort Ctrl+V delivery path that always leaves the result on the clipboard.

Cloud OCR, AI cleanup, diagrams, custom models, profiles, configuration import/export, launch at login, advanced capture modes, UI Automation replacement, and undo are deliberately outside this first Windows beta.

## Development

Use Windows 11 x64 with Visual Studio and the .NET 10 SDK installed:

```powershell
dotnet test .\Windows\WriteIt.Windows.Tests\WriteIt.Windows.Tests.csproj -c Release
pwsh .\Windows\script\create-package-assets.ps1 -AssetDirectory .\Windows\WriteIt.Windows\Assets
msbuild .\Windows\WriteIt.Windows\WriteIt.Windows.csproj /restore /p:Configuration=Release /p:Platform=x64
```

To generate a local unsigned MSIX package, use the same `msbuild` command with `GenerateAppxPackageOnBuild=true`; installation requires a locally trusted development certificate. The generated PNG branding assets are ignored and must not be committed.

Windows OCR depends on installed OCR language packs. If the selected language is absent, WriteIt uses English when it is installed; otherwise capture stays disabled.

## Manual beta checks

- Capture with both a mouse and a pressure-sensitive pen; verify clear, cancel, and a non-empty OCR result.
- Verify the overlay appears on the display of the foreground app, rather than moving that app's window.
- Test best-effort Ctrl+V in Notepad and one browser or editor. In every failed delivery case, verify the recognized text remains on the clipboard.
- Test that a non-English selection visibly falls back to English when its Windows OCR language pack is absent, and that capture disables when no supported language is installed.
- Restart the app and verify settings, text-only history, full ink history, and seven-day retention behavior.
