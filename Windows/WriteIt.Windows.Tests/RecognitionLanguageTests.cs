using WriteIt.Windows.Core;

namespace WriteIt.Windows.Tests;

public sealed class RecognitionLanguageTests
{
    [Fact]
    public void It_preserves_the_requested_installed_language()
    {
        var available = new HashSet<RecognitionLanguage> { RecognitionLanguage.English, RecognitionLanguage.French };

        var resolution = RecognitionLanguageResolver.Resolve(RecognitionLanguage.French, available);

        Assert.Equal(new LanguageResolution(RecognitionLanguage.French, RecognitionLanguage.French), resolution);
    }

    [Fact]
    public void It_falls_back_to_english_when_available()
    {
        var resolution = RecognitionLanguageResolver.Resolve(
            RecognitionLanguage.German,
            new HashSet<RecognitionLanguage> { RecognitionLanguage.English });

        Assert.Equal(new LanguageResolution(RecognitionLanguage.German, RecognitionLanguage.English), resolution);
        Assert.True(resolution!.UsedFallback);
    }

    [Fact]
    public void It_refuses_recognition_when_neither_language_nor_english_is_installed()
    {
        var resolution = RecognitionLanguageResolver.Resolve(
            RecognitionLanguage.German,
            new HashSet<RecognitionLanguage> { RecognitionLanguage.French });

        Assert.Null(resolution);
    }

    [Fact]
    public void It_parses_a_configurable_global_shortcut()
    {
        var parsed = GlobalShortcut.TryParse("Ctrl+Alt+W", out var shortcut, out var error);

        Assert.True(parsed, error);
        Assert.Equal(new GlobalShortcut((uint)'W', ShortcutModifiers.Control | ShortcutModifiers.Alt), shortcut);
        Assert.Equal("Ctrl+Alt+W", shortcut!.DisplayName);
    }

    [Fact]
    public void It_rejects_a_shortcut_without_a_modifier()
    {
        var parsed = GlobalShortcut.TryParse("W", out _, out var error);

        Assert.False(parsed);
        Assert.NotNull(error);
    }

    [Theory]
    [InlineData("en-SG", RecognitionLanguage.English)]
    [InlineData("pt-BR", RecognitionLanguage.Portuguese)]
    [InlineData("de-AT", RecognitionLanguage.German)]
    public void It_accepts_regional_variants_of_supported_ocr_languages(string tag, RecognitionLanguage expected)
    {
        Assert.Equal(expected, RecognitionLanguages.FromTag(tag));
    }
}
