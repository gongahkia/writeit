using System.Runtime.InteropServices;
using Microsoft.UI.Windowing;
using Microsoft.UI.Xaml;
using Windows.Graphics;
using WinRT.Interop;

namespace WriteIt.Windows.Services;

public static class WindowPlacement
{
    private const int GwLExStyle = -20;
    private const long WsExNoActivate = 0x08000000L;
    private const long WsExToolWindow = 0x00000080L;
    private const uint SwpNoActivate = 0x0010;
    private const uint SwpShowWindow = 0x0040;
    private static readonly IntPtr HwndTopMost = new(-1);

    public static IntPtr HandleFor(Window window) => WindowNative.GetWindowHandle(window);

    public static void ShowAsOverlay(Window window, IntPtr sourceWindow)
    {
        var handle = HandleFor(window);
        var style = GetWindowLongPtr(handle, GwLExStyle).ToInt64();
        _ = SetWindowLongPtr(handle, GwLExStyle, new IntPtr(style | WsExNoActivate | WsExToolWindow));
        var area = WorkingAreaFor(sourceWindow);
        var width = Math.Max(560, area.Right - area.Left - 48);
        var height = Math.Min(390, Math.Max(280, area.Bottom - area.Top - 48));
        var appWindow = AppWindow.GetFromWindowId(Win32Interop.GetWindowIdFromWindow(handle));
        appWindow.MoveAndResize(new RectInt32(area.Left + 24, area.Bottom - height - 30, width, height));
        _ = SetWindowPos(handle, HwndTopMost, 0, 0, 0, 0, SwpNoActivate | SwpShowWindow | 0x0001 | 0x0002);
    }

    private static Rect WorkingAreaFor(IntPtr sourceWindow)
    {
        var monitor = MonitorFromWindow(sourceWindow, sourceWindow == IntPtr.Zero ? 1u : 2u);
        var info = new MonitorInfo { Size = Marshal.SizeOf<MonitorInfo>() };
        if (monitor == IntPtr.Zero || !GetMonitorInfo(monitor, ref info))
            return new Rect { Left = 0, Top = 0, Right = 1280, Bottom = 720 };
        return info.Work;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct Rect
    {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct MonitorInfo
    {
        public int Size;
        public Rect Monitor;
        public Rect Work;
        public uint Flags;
    }

    [DllImport("user32.dll", EntryPoint = "GetWindowLongPtrW")]
    private static extern IntPtr GetWindowLongPtr(IntPtr window, int index);

    [DllImport("user32.dll", EntryPoint = "SetWindowLongPtrW")]
    private static extern IntPtr SetWindowLongPtr(IntPtr window, int index, IntPtr value);

    [DllImport("user32.dll")]
    private static extern IntPtr MonitorFromWindow(IntPtr window, uint flags);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool GetMonitorInfo(IntPtr monitor, ref MonitorInfo info);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SetWindowPos(IntPtr window, IntPtr insertAfter, int x, int y, int width, int height, uint flags);
}
