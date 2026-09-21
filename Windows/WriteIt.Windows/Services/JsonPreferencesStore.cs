using System.Text.Json;
using WriteIt.Windows.Core;

namespace WriteIt.Windows.Services;

public sealed class JsonPreferencesStore
{
    private static readonly JsonSerializerOptions SerializerOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.SnakeCaseLower,
        WriteIndented = true,
    };

    private readonly string _filePath;

    public JsonPreferencesStore(string directory)
    {
        _filePath = Path.Combine(directory, "preferences.json");
    }

    public async Task<WriteItPreferences> LoadAsync()
    {
        if (!File.Exists(_filePath)) return new WriteItPreferences();
        await using var stream = File.OpenRead(_filePath);
        var preferences = await JsonSerializer.DeserializeAsync<WriteItPreferences>(stream, SerializerOptions);
        preferences?.Validate();
        return preferences ?? new WriteItPreferences();
    }

    public async Task SaveAsync(WriteItPreferences preferences)
    {
        preferences.Validate();
        Directory.CreateDirectory(Path.GetDirectoryName(_filePath)!);
        var temporaryPath = _filePath + ".tmp";
        await using (var stream = File.Create(temporaryPath))
        {
            await JsonSerializer.SerializeAsync(stream, preferences, SerializerOptions);
        }

        File.Move(temporaryPath, _filePath, overwrite: true);
    }
}
