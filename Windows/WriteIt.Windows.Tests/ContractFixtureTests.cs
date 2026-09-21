using System.Text.Json;
using WriteIt.Windows.Core;

namespace WriteIt.Windows.Tests;

public sealed class ContractFixtureTests
{
    [Fact]
    public async Task It_matches_the_v1_capture_lifecycle_contract()
    {
        var path = Path.Combine(AppContext.BaseDirectory, "contracts", "capture-lifecycle", "v1.json");
        using var document = JsonDocument.Parse(await File.ReadAllTextAsync(path));
        Assert.Equal(1, document.RootElement.GetProperty("schema_version").GetInt32());

        foreach (var transition in document.RootElement.GetProperty("transitions").EnumerateArray())
        {
            var from = ParsePhase(transition[0].GetString()!);
            var to = ParsePhase(transition[1].GetString()!);
            Assert.True(CaptureLifecycle.AllowsTransition(from, to), $"Expected {from} -> {to} to be allowed.");
        }
    }

    [Fact]
    public async Task It_matches_the_v1_language_contract()
    {
        var path = Path.Combine(AppContext.BaseDirectory, "contracts", "recognition-languages", "v1.json");
        using var document = JsonDocument.Parse(await File.ReadAllTextAsync(path));
        var expectedTags = document.RootElement.GetProperty("languages").EnumerateArray().Select(value => value.GetString()).ToArray();

        Assert.Equal(expectedTags.OrderBy(value => value), RecognitionLanguages.Tags.Values.OrderBy(value => value));
        Assert.Equal("en-US", document.RootElement.GetProperty("fallback_language").GetString());
    }

    private static CapturePhase ParsePhase(string value) => Enum.Parse<CapturePhase>(value, ignoreCase: true);
}
