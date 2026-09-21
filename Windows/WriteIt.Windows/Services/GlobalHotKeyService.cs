using System.ComponentModel;
using System.Runtime.InteropServices;
using WriteIt.Windows.Core;

namespace WriteIt.Windows.Services;

public sealed class GlobalHotKeyService : IDisposable
{
    private const uint WmHotKey = 0x0312;
    private const uint ModNoRepeat = 0x4000;
    private const int HotKeyId = 1;
    private readonly string _className = $"WriteIt.HotKey.{Guid.NewGuid():N}";
    private readonly WindowProcedure _windowProcedure;
    private IntPtr _window;
    private IntPtr _instance;
    private bool _registered;

    public GlobalHotKeyService()
    {
        _windowProcedure = WindowProcedureCallback;
        CreateMessageWindow();
    }

    public event EventHandler? Pressed;

    public void Register(GlobalShortcut shortcut)
    {
        Unregister();
        if (!RegisterHotKey(_window, HotKeyId, (uint)shortcut.Modifiers | ModNoRepeat, shortcut.VirtualKey))
        {
            throw new Win32Exception(Marshal.GetLastWin32Error(), $"{shortcut.DisplayName} is already in use by another app.");
        }

        _registered = true;
    }

    public void Unregister()
    {
        if (!_registered) return;
        _ = UnregisterHotKey(_window, HotKeyId);
        _registered = false;
    }

    public void Dispose()
    {
        Unregister();
        if (_window != IntPtr.Zero)
        {
            _ = DestroyWindow(_window);
            _window = IntPtr.Zero;
        }
        if (_instance != IntPtr.Zero)
        {
            _ = UnregisterClass(_className, _instance);
            _instance = IntPtr.Zero;
        }
    }

    private void CreateMessageWindow()
    {
        _instance = GetModuleHandle(null);
        var windowClass = new WindowClassEx
        {
            Size = (uint)Marshal.SizeOf<WindowClassEx>(),
            Instance = _instance,
            ClassName = _className,
            WindowProcedure = _windowProcedure,
        };
        var atom = RegisterClassEx(ref windowClass);
        if (atom == 0) throw new Win32Exception(Marshal.GetLastWin32Error(), "WriteIt could not create a global shortcut listener.");
        _window = CreateWindowEx(0, _className, "WriteIt HotKey", 0, 0, 0, 0, 0, new IntPtr(-3), IntPtr.Zero, _instance, IntPtr.Zero);
        if (_window == IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error(), "WriteIt could not create a global shortcut listener.");
    }

    private IntPtr WindowProcedureCallback(IntPtr window, uint message, IntPtr wParam, IntPtr lParam)
    {
        if (message == WmHotKey && wParam.ToInt32() == HotKeyId) Pressed?.Invoke(this, EventArgs.Empty);
        return DefWindowProc(window, message, wParam, lParam);
    }

    private delegate IntPtr WindowProcedure(IntPtr window, uint message, IntPtr wParam, IntPtr lParam);

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct WindowClassEx
    {
        public uint Size;
        public uint Style;
        public WindowProcedure? WindowProcedure;
        public int ClassExtra;
        public int WindowExtra;
        public IntPtr Instance;
        public IntPtr Icon;
        public IntPtr Cursor;
        public IntPtr Background;
        public string? MenuName;
        public string ClassName;
        public IntPtr IconSmall;
    }

    [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern ushort RegisterClassEx([In] ref WindowClassEx windowClass);

    [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    private static extern IntPtr CreateWindowEx(uint extendedStyle, string className, string windowName, uint style, int x, int y, int width, int height, IntPtr parent, IntPtr menu, IntPtr instance, IntPtr parameter);

    [DllImport("user32.dll")]
    private static extern IntPtr DefWindowProc(IntPtr window, uint message, IntPtr wParam, IntPtr lParam);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool DestroyWindow(IntPtr window);

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool RegisterHotKey(IntPtr window, int id, uint modifiers, uint virtualKey);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool UnregisterHotKey(IntPtr window, int id);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool UnregisterClass(string className, IntPtr instance);

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
    private static extern IntPtr GetModuleHandle(string? moduleName);
}
