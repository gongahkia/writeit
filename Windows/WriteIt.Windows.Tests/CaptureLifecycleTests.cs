using WriteIt.Windows.Core;

namespace WriteIt.Windows.Tests;

public sealed class CaptureLifecycleTests
{
    [Fact]
    public void It_runs_the_drawing_to_delivery_lifecycle()
    {
        var lifecycle = new CaptureLifecycle();

        Assert.True(lifecycle.Begin());
        Assert.Equal(CapturePhase.Drawing, lifecycle.Phase);
        Assert.True(lifecycle.BeginRecognition());
        Assert.True(lifecycle.BeginDelivery());
        Assert.True(lifecycle.CompleteDelivery("Copied to clipboard."));
        Assert.Equal(CapturePhase.Delivered, lifecycle.Phase);
        Assert.Equal("Copied to clipboard.", lifecycle.Message);
        Assert.True(lifecycle.Dismiss());
        Assert.Equal(CapturePhase.Idle, lifecycle.Phase);
    }

    [Fact]
    public void It_rejects_illegal_lifecycle_transitions()
    {
        var lifecycle = new CaptureLifecycle();

        Assert.False(lifecycle.BeginRecognition());
        Assert.False(lifecycle.CompleteDelivery("Done"));
        Assert.Equal(CapturePhase.Idle, lifecycle.Phase);
    }
}
