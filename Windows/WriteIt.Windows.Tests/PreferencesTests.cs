using WriteIt.Windows.Core;

namespace WriteIt.Windows.Tests;

public sealed class PreferencesTests
{
    [Fact]
    public void Defaults_are_valid_for_the_windows_mvp()
    {
        var preferences = new WriteItPreferences();

        preferences.Validate();

        Assert.Equal(RecognitionLanguage.English, preferences.RecognitionLanguage);
        Assert.Equal(HistoryMode.TextOnly, preferences.HistoryMode);
        Assert.Equal(7, preferences.HistoryRetentionDays);
    }

    [Theory]
    [InlineData(0)]
    [InlineData(366)]
    public void It_rejects_out_of_range_history_retention(int retentionDays)
    {
        var preferences = new WriteItPreferences { HistoryRetentionDays = retentionDays };

        Assert.Throws<InvalidOperationException>(preferences.Validate);
    }
}
