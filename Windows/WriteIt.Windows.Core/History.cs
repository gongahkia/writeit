namespace WriteIt.Windows.Core;

public sealed record HistoryEntry(
    Guid Id,
    DateTimeOffset CreatedAt,
    string Text,
    string Source,
    string DeliveryMethod,
    RecognitionLanguage Language,
    byte[]? InkData = null)
{
    public static HistoryEntry Create(
        string text,
        string source,
        string deliveryMethod,
        RecognitionLanguage language,
        byte[]? inkData) => new(Guid.NewGuid(), DateTimeOffset.UtcNow, text, source, deliveryMethod, language, inkData);
}

public static class HistoryRetention
{
    public static IReadOnlyList<HistoryEntry> Retain(
        IEnumerable<HistoryEntry> entries,
        DateTimeOffset now,
        int retentionDays)
    {
        if (retentionDays is < 1 or > 365) throw new ArgumentOutOfRangeException(nameof(retentionDays));
        var cutoff = now.AddDays(-retentionDays);
        return entries.Where(entry => entry.CreatedAt >= cutoff)
            .OrderByDescending(entry => entry.CreatedAt)
            .ToArray();
    }
}
