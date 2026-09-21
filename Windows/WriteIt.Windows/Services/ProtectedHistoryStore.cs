using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using WriteIt.Windows.Core;

namespace WriteIt.Windows.Services;

public sealed class ProtectedHistoryStore
{
    private static readonly byte[] Entropy = Encoding.UTF8.GetBytes("WriteIt.Windows.History.v1");
    private static readonly JsonSerializerOptions SerializerOptions = new()
    {
        PropertyNamingPolicy = JsonNamingPolicy.SnakeCaseLower,
    };

    private readonly string _filePath;

    public ProtectedHistoryStore(string directory)
    {
        _filePath = Path.Combine(directory, "history.protected");
    }

    public async Task<IReadOnlyList<HistoryEntry>> LoadAsync()
    {
        if (!File.Exists(_filePath)) return Array.Empty<HistoryEntry>();
        var protectedBytes = await File.ReadAllBytesAsync(_filePath);
        var clearBytes = ProtectedData.Unprotect(protectedBytes, Entropy, DataProtectionScope.CurrentUser);
        return JsonSerializer.Deserialize<List<HistoryEntry>>(clearBytes, SerializerOptions) ?? [];
    }

    public async Task SaveAsync(IReadOnlyCollection<HistoryEntry> entries)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(_filePath)!);
        var clearBytes = JsonSerializer.SerializeToUtf8Bytes(entries, SerializerOptions);
        var protectedBytes = ProtectedData.Protect(clearBytes, Entropy, DataProtectionScope.CurrentUser);
        var temporaryPath = _filePath + ".tmp";
        await File.WriteAllBytesAsync(temporaryPath, protectedBytes);
        File.Move(temporaryPath, _filePath, overwrite: true);
    }
}
