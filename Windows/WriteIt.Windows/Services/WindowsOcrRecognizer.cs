using Windows.Globalization;
using Windows.Graphics.Imaging;
using Windows.Media.Ocr;
using Windows.Storage.Streams;
using WriteIt.Windows.Core;

namespace WriteIt.Windows.Services;

public sealed record RecognitionResult(string Text, LanguageResolution Resolution);

public sealed class WindowsOcrRecognizer
{
    public static ISet<RecognitionLanguage> AvailableLanguages => AvailableRecognizerLanguages.Keys.ToHashSet();

    private static IReadOnlyDictionary<RecognitionLanguage, Language> AvailableRecognizerLanguages => OcrEngine.AvailableRecognizerLanguages
        .Select(language => new { RecognitionLanguage = RecognitionLanguages.FromTag(language.LanguageTag), Language = language })
        .Where(candidate => candidate.RecognitionLanguage is not null)
        .GroupBy(candidate => candidate.RecognitionLanguage!.Value)
        .ToDictionary(
            group => group.Key,
            group => group
                .OrderBy(candidate => StringComparer.OrdinalIgnoreCase.Equals(
                    candidate.Language.LanguageTag,
                    RecognitionLanguages.Tags[group.Key]) ? 0 : 1)
                .ThenBy(candidate => candidate.Language.LanguageTag, StringComparer.OrdinalIgnoreCase)
                .First()
                .Language);

    public static async Task<RecognitionResult> RecognizeAsync(byte[] pngData, RecognitionLanguage requestedLanguage)
    {
        var availableRecognizers = AvailableRecognizerLanguages;
        var resolution = RecognitionLanguageResolver.Resolve(requestedLanguage, availableRecognizers.Keys.ToHashSet())
            ?? throw new InvalidOperationException("Windows OCR has no supported installed language. Install English or the selected language pack.");
        var engine = OcrEngine.TryCreateFromLanguage(availableRecognizers[resolution.Resolved])
            ?? throw new InvalidOperationException("Windows OCR could not initialize the selected language.");

        using var stream = new InMemoryRandomAccessStream();
        using (var writer = new DataWriter(stream))
        {
            writer.WriteBytes(pngData);
            await writer.StoreAsync();
            writer.DetachStream();
        }

        stream.Seek(0);
        var decoder = await BitmapDecoder.CreateAsync(stream);
        using var bitmap = await decoder.GetSoftwareBitmapAsync();
        var result = await engine.RecognizeAsync(bitmap);
        var text = String.Join(" ", result.Lines.Select(line => line.Text)).Trim();
        if (String.IsNullOrWhiteSpace(text)) throw new InvalidOperationException("Windows OCR could not read any text from this capture.");
        return new RecognitionResult(text, resolution);
    }
}
