using System.Numerics;
using Windows.Foundation;
using Windows.UI.Input.Inking;
using WriteIt.Windows.Controls;
using WriteIt.Windows.Core;

namespace WriteIt.Windows.Services;

public sealed record RecognitionResult(string Text, LanguageResolution Resolution);

/// <summary>
/// Uses the Windows Ink recognition engine directly. Image OCR is retained for
/// document-like content elsewhere, but it is not suitable for freehand input.
/// </summary>
public static class WindowsHandwritingRecognizer
{
    public static ISet<RecognitionLanguage> AvailableLanguages => AvailableRecognizers.Keys.ToHashSet();

    public static async Task<RecognitionResult> RecognizeAsync(
        IReadOnlyList<InkStrokeCapture> capturedStrokes,
        RecognitionLanguage requestedLanguage)
    {
        var recognizers = AvailableRecognizers;
        var resolution = RecognitionLanguageResolver.Resolve(requestedLanguage, recognizers.Keys.ToHashSet())
            ?? throw new InvalidOperationException("Windows has no supported handwriting recognizer. Install English handwriting recognition in Windows Settings.");

        var strokeCollection = CreateStrokeCollection(capturedStrokes);
        var recognizerContainer = new InkRecognizerContainer();
        recognizerContainer.SetDefaultRecognizer(recognizers[resolution.Resolved]);
        var results = await recognizerContainer.RecognizeAsync(strokeCollection, InkRecognitionTarget.All);
        var text = String.Join(" ", results
            .Select(TopCandidate)
            .Where(candidate => !String.IsNullOrWhiteSpace(candidate)))
            .Trim();
        if (String.IsNullOrWhiteSpace(text))
            throw new InvalidOperationException("Windows handwriting recognition could not read that ink. Try writing larger with separated words.");

        return new RecognitionResult(text, resolution);
    }

    private static string? TopCandidate(InkRecognitionResult result)
    {
        var candidates = result.GetTextCandidates();
        return candidates.Count == 0 ? null : candidates[0];
    }

    private static IReadOnlyDictionary<RecognitionLanguage, InkRecognizer> AvailableRecognizers => new InkRecognizerContainer()
        .GetRecognizers()
        .Select(recognizer => new { Language = LanguageForRecognizer(recognizer.Name), Recognizer = recognizer })
        .Where(candidate => candidate.Language is not null)
        .GroupBy(candidate => candidate.Language!.Value)
        .ToDictionary(group => group.Key, group => group.First().Recognizer);

    private static InkStrokeContainer CreateStrokeCollection(IReadOnlyList<InkStrokeCapture> capturedStrokes)
    {
        var collection = new InkStrokeContainer();
        var builder = new InkStrokeBuilder();
        foreach (var capturedStroke in capturedStrokes.Where(stroke => stroke.Samples.Count >= 2))
        {
            var points = capturedStroke.Samples
                .Select(sample => new InkPoint(new Point(sample.X, sample.Y), sample.Pressure))
                .ToArray();
            collection.AddStroke(builder.CreateStrokeFromInkPoints(points, Matrix3x2.Identity));
        }

        if (!collection.GetStrokes().Any())
            throw new InvalidOperationException("Write something before recognizing.");
        return collection;
    }

    private static RecognitionLanguage? LanguageForRecognizer(string name)
    {
        var normalized = name.ToUpperInvariant();
        if (normalized.Contains("ENGLISH") || normalized.Contains("ANGLAIS")) return RecognitionLanguage.English;
        if (normalized.Contains("FRENCH") || normalized.Contains("FRANÇAIS")) return RecognitionLanguage.French;
        if (normalized.Contains("GERMAN") || normalized.Contains("DEUTSCH")) return RecognitionLanguage.German;
        if (normalized.Contains("SPANISH") || normalized.Contains("ESPAÑOL")) return RecognitionLanguage.Spanish;
        if (normalized.Contains("ITALIAN") || normalized.Contains("ITALIANO")) return RecognitionLanguage.Italian;
        if (normalized.Contains("PORTUGUESE") || normalized.Contains("PORTUGUÊS")) return RecognitionLanguage.Portuguese;
        return null;
    }
}
