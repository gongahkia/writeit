using Windows.Globalization;
using Windows.Graphics.Imaging;
using Windows.Media.Ocr;
using Windows.Storage.Streams;
using WriteIt.Windows.Core;

namespace WriteIt.Windows.Services;

public sealed record RecognitionResult(string Text, LanguageResolution Resolution);

public sealed class WindowsOcrRecognizer
{
    public static ISet<RecognitionLanguage> AvailableLanguages => OcrEngine.AvailableRecognizerLanguages
        .Select(language => RecognitionLanguages.FromTag(language.LanguageTag))
        .Where(language => language is not null)
        .Select(language => language!.Value)
        .ToHashSet();

    public static async Task<RecognitionResult> RecognizeAsync(byte[] pngData, RecognitionLanguage requestedLanguage)
    {
        var resolution = RecognitionLanguageResolver.Resolve(requestedLanguage, AvailableLanguages)
            ?? throw new InvalidOperationException("Windows OCR has no supported installed language. Install English or the selected language pack.");
        var engine = OcrEngine.TryCreateFromLanguage(new Language(RecognitionLanguages.Tags[resolution.Resolved]))
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
