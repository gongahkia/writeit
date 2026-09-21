using Microsoft.UI;
using Microsoft.UI.Input;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Microsoft.UI.Xaml.Shapes;

namespace WriteIt.Windows.Controls;

/// <summary>
/// WinUI 3 has no stable InkCanvas control. This surface captures mouse and pen
/// pointers, renders the strokes, and exposes a portable snapshot for history.
/// </summary>
public sealed class InkCaptureSurface : Canvas
{
    private readonly Dictionary<uint, ActiveStroke> _activeStrokes = [];
    private readonly List<InkStrokeCapture> _completedStrokes = [];
    private readonly SolidColorBrush _inkBrush = new(Colors.Black);
    private double _strokeWidth = 4;

    public InkCaptureSurface()
    {
        Background = new SolidColorBrush(Colors.White);
        PointerPressed += InkCaptureSurface_PointerPressed;
        PointerMoved += InkCaptureSurface_PointerMoved;
        PointerReleased += InkCaptureSurface_PointerReleased;
        PointerCanceled += InkCaptureSurface_PointerCanceled;
        PointerCaptureLost += InkCaptureSurface_PointerCaptureLost;
    }

    public double StrokeWidth
    {
        get => _strokeWidth;
        set => _strokeWidth = Math.Clamp(value, 1, 32);
    }

    public bool HasInk => _completedStrokes.Count != 0 || _activeStrokes.Values.Any(stroke => stroke.Samples.Count != 0);

    public void ClearInk()
    {
        ReleasePointerCaptures();
        _activeStrokes.Clear();
        _completedStrokes.Clear();
        Children.Clear();
    }

    public IReadOnlyList<InkStrokeCapture> Snapshot()
    {
        return [
            .. _completedStrokes,
            .. _activeStrokes.Values.Select(stroke => stroke.Snapshot()),
        ];
    }

    private void InkCaptureSurface_PointerPressed(object sender, PointerRoutedEventArgs e)
    {
        var point = e.GetCurrentPoint(this);
        if (!IsSupported(point)) return;

        var stroke = new ActiveStroke(StrokeWidth);
        _activeStrokes[point.PointerId] = stroke;
        AppendPoint(stroke, point);
        CapturePointer(e.Pointer);
        Focus(FocusState.Pointer);
        e.Handled = true;
    }

    private void InkCaptureSurface_PointerMoved(object sender, PointerRoutedEventArgs e)
    {
        if (!_activeStrokes.TryGetValue(e.Pointer.PointerId, out var stroke)) return;

        foreach (var point in e.GetIntermediatePoints(this).OrderBy(point => point.Timestamp))
            AppendPoint(stroke, point);
        e.Handled = true;
    }

    private void InkCaptureSurface_PointerReleased(object sender, PointerRoutedEventArgs e)
    {
        CompleteStroke(e);
    }

    private void InkCaptureSurface_PointerCanceled(object sender, PointerRoutedEventArgs e)
    {
        CompleteStroke(e);
    }

    private void InkCaptureSurface_PointerCaptureLost(object sender, PointerRoutedEventArgs e)
    {
        CompleteStroke(e);
    }

    private void CompleteStroke(PointerRoutedEventArgs e)
    {
        if (!_activeStrokes.Remove(e.Pointer.PointerId, out var stroke)) return;

        AppendPoint(stroke, e.GetCurrentPoint(this));
        if (stroke.Samples.Count != 0) _completedStrokes.Add(stroke.Snapshot());
        ReleasePointerCapture(e.Pointer);
        e.Handled = true;
    }

    private void AppendPoint(ActiveStroke stroke, PointerPoint point)
    {
        var sample = new InkSample(point.Position.X, point.Position.Y, NormalizePressure(point.Properties.Pressure));
        if (stroke.Samples.Count == 0)
        {
            stroke.Samples.Add(sample);
            DrawDot(sample, stroke.Width);
            return;
        }

        var previous = stroke.Samples[^1];
        if (previous.X == sample.X && previous.Y == sample.Y) return;

        stroke.Samples.Add(sample);
        Children.Add(new Line
        {
            X1 = previous.X,
            Y1 = previous.Y,
            X2 = sample.X,
            Y2 = sample.Y,
            Stroke = _inkBrush,
            StrokeThickness = EffectiveWidth(stroke.Width, (previous.Pressure + sample.Pressure) / 2),
            StrokeStartLineCap = PenLineCap.Round,
            StrokeEndLineCap = PenLineCap.Round,
        });
    }

    private void DrawDot(InkSample sample, double width)
    {
        var size = EffectiveWidth(width, sample.Pressure);
        var dot = new Ellipse
        {
            Width = size,
            Height = size,
            Fill = _inkBrush,
        };
        SetLeft(dot, sample.X - (size / 2));
        SetTop(dot, sample.Y - (size / 2));
        Children.Add(dot);
    }

    private static bool IsSupported(PointerPoint point)
    {
        return point.PointerDeviceType is PointerDeviceType.Mouse or PointerDeviceType.Pen;
    }

    private static float NormalizePressure(float pressure)
    {
        return Math.Clamp(pressure <= 0 ? 0.65F : pressure, 0.25F, 1F);
    }

    private static double EffectiveWidth(double width, float pressure)
    {
        return width * pressure;
    }

    private sealed class ActiveStroke(double width)
    {
        public double Width { get; } = width;

        public List<InkSample> Samples { get; } = [];

        public InkStrokeCapture Snapshot() => new(Width, [.. Samples]);
    }
}

public sealed record InkStrokeCapture(double Width, IReadOnlyList<InkSample> Samples);

public readonly record struct InkSample(double X, double Y, float Pressure);
