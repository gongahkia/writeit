using System.Runtime.InteropServices;
using Windows.ApplicationModel.DataTransfer;
using WriteIt.Windows.Core;

namespace WriteIt.Windows.Services;

public sealed class WindowsClipboardDelivery
{
    private const uint InputKeyboard = 1;
    private const uint KeyEventKeyUp = 0x0002;
    private const ushort VirtualKeyControl = 0x11;
    private const ushort VirtualKeyV = 0x56;
    private const uint SwpNoSize = 0x0001;
    private const uint SwpNoMove = 0x0002;
    private const uint SwpShowWindow = 0x0040;
    private static readonly IntPtr HwndTop = IntPtr.Zero;

    public IntPtr CaptureTarget(IntPtr ownWindow)
    {
        var target = GetForegroundWindow();
        return target == ownWindow ? IntPtr.Zero : target;
    }

    public DeliveryResult Deliver(string text, IntPtr target)
    {
        var package = new DataPackage();
        package.SetText(text);
        Clipboard.SetContentWithOptions(package, new ClipboardContentOptions { IsAllowedInHistory = false, IsRoamable = false });
        Clipboard.Flush();

        if (target == IntPtr.Zero) return DeliveryResult.Clipboard;
        if (!IsWindow(target)) return DeliveryResult.ClipboardFallback("the original app is no longer available");
        if (!SetForegroundWindow(target)) return DeliveryResult.ClipboardFallback("the original app could not be activated");
        _ = SetWindowPos(target, HwndTop, 0, 0, 0, 0, SwpNoMove | SwpNoSize | SwpShowWindow);

        var inputs = new[]
        {
            KeyboardInput(VirtualKeyControl, 0),
            KeyboardInput(VirtualKeyV, 0),
            KeyboardInput(VirtualKeyV, KeyEventKeyUp),
            KeyboardInput(VirtualKeyControl, KeyEventKeyUp),
        };
        var sent = SendInput((uint)inputs.Length, inputs, Marshal.SizeOf<Input>());
        return sent == (uint)inputs.Length
            ? DeliveryResult.PasteRequested
            : DeliveryResult.ClipboardFallback("Windows blocked the paste request");
    }

    private static Input KeyboardInput(ushort virtualKey, uint flags) => new()
    {
        Type = InputKeyboard,
        Union = new InputUnion { Keyboard = new KeyboardInputData { VirtualKey = virtualKey, Flags = flags } },
    };

    [DllImport("user32.dll")]
    private static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool IsWindow(IntPtr window);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SetForegroundWindow(IntPtr window);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool SetWindowPos(IntPtr window, IntPtr insertAfter, int x, int y, int width, int height, uint flags);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern uint SendInput(uint inputCount, [In] Input[] inputs, int inputSize);

    [StructLayout(LayoutKind.Sequential)]
    private struct Input
    {
        public uint Type;
        public InputUnion Union;
    }

    [StructLayout(LayoutKind.Explicit)]
    private struct InputUnion
    {
        [FieldOffset(0)] public KeyboardInputData Keyboard;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct KeyboardInputData
    {
        public ushort VirtualKey;
        public ushort Scan;
        public uint Flags;
        public uint Time;
        public IntPtr ExtraInfo;
    }
}
