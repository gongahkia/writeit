using WriteIt.Windows.Core;

namespace WriteIt.Windows.Tests;

public sealed class HistoryRetentionTests
{
    [Fact]
    public void It_removes_entries_older_than_the_configured_retention_period()
    {
        var now = new DateTimeOffset(2026, 9, 21, 12, 0, 0, TimeSpan.Zero);
        var recent = HistoryEntry.Create("recent", "windows-ocr", "Clipboard", RecognitionLanguage.English, null) with { CreatedAt = now.AddDays(-6) };
        var old = HistoryEntry.Create("old", "windows-ocr", "Clipboard", RecognitionLanguage.English, null) with { CreatedAt = now.AddDays(-8) };

        var retained = HistoryRetention.Retain([old, recent], now, 7);

        Assert.Collection(retained, entry => Assert.Equal(recent.Id, entry.Id));
    }
}
