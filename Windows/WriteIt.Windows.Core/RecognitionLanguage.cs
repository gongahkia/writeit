namespace WriteIt.Windows.Core;

public enum RecognitionLanguage
{
    English,
    French,
    German,
    Spanish,
    Italian,
    Portuguese,
}

public static class RecognitionLanguages
{
    public static readonly IReadOnlyDictionary<RecognitionLanguage, string> Tags =
        new Dictionary<RecognitionLanguage, string>
        {
            [RecognitionLanguage.English] = "en-US",
            [RecognitionLanguage.French] = "fr-FR",
            [RecognitionLanguage.German] = "de-DE",
            [RecognitionLanguage.Spanish] = "es-ES",
            [RecognitionLanguage.Italian] = "it-IT",
            [RecognitionLanguage.Portuguese] = "pt-PT",
        };

    public static string DisplayName(RecognitionLanguage language) => language switch
    {
        RecognitionLanguage.English => "English",
        RecognitionLanguage.French => "French",
        RecognitionLanguage.German => "German",
        RecognitionLanguage.Spanish => "Spanish",
        RecognitionLanguage.Italian => "Italian",
        RecognitionLanguage.Portuguese => "Portuguese",
        _ => language.ToString(),
    };

    public static RecognitionLanguage? FromTag(string? tag)
    {
        if (String.IsNullOrWhiteSpace(tag)) return null;

        foreach (var pair in Tags)
        {
            if (StringComparer.OrdinalIgnoreCase.Equals(pair.Value, tag)) return pair.Key;
        }

        // Windows exposes language tags for the actual installed regional pack
        // (for example en-SG or pt-BR), rather than necessarily the regional
        // default we store for this supported language. OCR can use either.
        var primarySubtag = tag.Split('-', StringSplitOptions.RemoveEmptyEntries)[0];
        var regionalMatch = Tags.FirstOrDefault(pair =>
            StringComparer.OrdinalIgnoreCase.Equals(
                pair.Value.Split('-', StringSplitOptions.RemoveEmptyEntries)[0],
                primarySubtag));
        return regionalMatch.Value is null ? null : regionalMatch.Key;
    }
}

public sealed record LanguageResolution(
    RecognitionLanguage Requested,
    RecognitionLanguage Resolved)
{
    public bool UsedFallback => Requested != Resolved;
}

public static class RecognitionLanguageResolver
{
    public static LanguageResolution? Resolve(
        RecognitionLanguage requested,
        ISet<RecognitionLanguage> available)
    {
        if (available.Contains(requested)) return new LanguageResolution(requested, requested);
        return available.Contains(RecognitionLanguage.English)
            ? new LanguageResolution(requested, RecognitionLanguage.English)
            : null;
    }
}
