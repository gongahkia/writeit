using WriteIt.Windows.Core;

namespace WriteIt.Windows.Models;

public sealed record LanguageOption(RecognitionLanguage Language)
{
    public string DisplayName => RecognitionLanguages.DisplayName(Language);
}
