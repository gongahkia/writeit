using System.Runtime.InteropServices.WindowsRuntime;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media.Imaging;
using Windows.Graphics.Imaging;
using Windows.Storage.Streams;

namespace WriteIt.Windows.Services;

public static class InkRasterizer
{
    public static async Task<byte[]> RenderPngAsync(InkCanvas canvas)
    {
        if (canvas.InkPresenter.StrokeContainer.GetStrokes().Count == 0)
            throw new InvalidOperationException("Write something before recognizing.");

        var bitmap = new RenderTargetBitmap();
        await bitmap.RenderAsync(canvas, Math.Max(1, (int)canvas.ActualWidth), Math.Max(1, (int)canvas.ActualHeight));
        var pixels = await bitmap.GetPixelsAsync();
        using var stream = new InMemoryRandomAccessStream();
        var encoder = await BitmapEncoder.CreateAsync(BitmapEncoder.PngEncoderId, stream);
        encoder.SetPixelData(
            BitmapPixelFormat.Bgra8,
            BitmapAlphaMode.Premultiplied,
            (uint)bitmap.PixelWidth,
            (uint)bitmap.PixelHeight,
            96,
            96,
            pixels.ToArray());
        await encoder.FlushAsync();
        return await ReadAllBytesAsync(stream);
    }

    public static async Task<byte[]> SaveInkAsync(InkCanvas canvas)
    {
        using var stream = new InMemoryRandomAccessStream();
        await canvas.InkPresenter.StrokeContainer.SaveAsync(stream);
        return await ReadAllBytesAsync(stream);
    }

    private static async Task<byte[]> ReadAllBytesAsync(IRandomAccessStream stream)
    {
        stream.Seek(0);
        if (stream.Size > Int32.MaxValue) throw new InvalidOperationException("The ink capture is too large to save.");
        using var reader = new DataReader(stream.GetInputStreamAt(0));
        await reader.LoadAsync((uint)stream.Size);
        var bytes = new byte[(int)stream.Size];
        reader.ReadBytes(bytes);
        return bytes;
    }
}
