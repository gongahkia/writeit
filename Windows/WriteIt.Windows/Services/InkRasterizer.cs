using System.Runtime.InteropServices.WindowsRuntime;
using System.Text.Json;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Media.Imaging;
using Windows.Graphics.Imaging;
using Windows.Storage.Streams;
using WriteIt.Windows.Controls;

namespace WriteIt.Windows.Services;

public static class InkRasterizer
{
    public static async Task<byte[]> RenderPngAsync(InkCaptureSurface surface)
    {
        if (!surface.HasInk)
            throw new InvalidOperationException("Write something before recognizing.");

        var bitmap = new RenderTargetBitmap();
        await bitmap.RenderAsync(surface, Math.Max(1, (int)surface.ActualWidth), Math.Max(1, (int)surface.ActualHeight));
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

    public static Task<byte[]> SaveInkAsync(InkCaptureSurface surface)
    {
        return Task.FromResult(JsonSerializer.SerializeToUtf8Bytes(surface.Snapshot()));
    }

    private static async Task<byte[]> ReadAllBytesAsync(InMemoryRandomAccessStream stream)
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
