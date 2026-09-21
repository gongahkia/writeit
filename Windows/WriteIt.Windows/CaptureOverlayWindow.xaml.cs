using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using WriteIt.Windows.Controls;
using WriteIt.Windows.Services;

namespace WriteIt.Windows;

public sealed partial class CaptureOverlayWindow : Window
{
    public CaptureOverlayWindow()
    {
        InitializeComponent();
    }

    public event Func<byte[], byte[]?, Task>? Submitted;

    public event EventHandler? Cancelled;

    public void Present(IntPtr sourceWindow)
    {
        Reset();
        Activate();
        WindowPlacement.ShowAsOverlay(this, sourceWindow);
    }

    public void SetStrokeWidth(double width)
    {
        InkSurface.StrokeWidth = width;
    }

    public void Reset()
    {
        InkSurface.ClearInk();
        InkSurface.Visibility = Visibility.Visible;
        ResultPanel.Visibility = Visibility.Collapsed;
        TitleText.Text = "Write naturally";
        ClearButton.Visibility = Visibility.Visible;
        SubmitButton.Visibility = Visibility.Visible;
        CloseButton.Visibility = Visibility.Collapsed;
    }

    public void ShowResult(string text, string title, string message)
    {
        InkSurface.Visibility = Visibility.Collapsed;
        ResultTitle.Text = title;
        ResultText.Text = text;
        ResultMessage.Text = message;
        ResultPanel.Visibility = Visibility.Visible;
        TitleText.Text = "Done";
        ClearButton.Visibility = Visibility.Collapsed;
        SubmitButton.Visibility = Visibility.Collapsed;
        CloseButton.Visibility = Visibility.Visible;
    }

    public void HideOverlay()
    {
        WindowPlacement.Hide(this);
    }

    private void ClearButton_Click(object sender, RoutedEventArgs e)
    {
        InkSurface.ClearInk();
    }

    private async void SubmitButton_Click(object sender, RoutedEventArgs e)
    {
        if (Submitted is null) return;
        SubmitButton.IsEnabled = false;
        ClearButton.IsEnabled = false;
        TitleText.Text = "Recognizing locally…";
        try
        {
            var png = await InkRasterizer.RenderPngAsync(InkSurface);
            var ink = await InkRasterizer.SaveInkAsync(InkSurface);
            await Submitted.Invoke(png, ink);
        }
        catch (Exception exception)
        {
            ShowResult(String.Empty, "Couldn’t read handwriting", exception.Message);
        }
        finally
        {
            SubmitButton.IsEnabled = true;
            ClearButton.IsEnabled = true;
        }
    }

    private void CancelButton_Click(object sender, RoutedEventArgs e)
    {
        Cancelled?.Invoke(this, EventArgs.Empty);
    }

    private void CloseButton_Click(object sender, RoutedEventArgs e)
    {
        Cancelled?.Invoke(this, EventArgs.Empty);
    }
}
