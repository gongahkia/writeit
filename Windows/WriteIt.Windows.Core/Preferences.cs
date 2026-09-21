namespace WriteIt.Windows.Core;

public enum HistoryMode
{
    Full,
    TextOnly,
    Off,
}

[Flags]
public enum ShortcutModifiers : uint
{
    None = 0,
    Alt = 0x0001,
    Control = 0x0002,
    Shift = 0x0004,
    Windows = 0x0008,
}

public sealed record GlobalShortcut(uint VirtualKey, ShortcutModifiers Modifiers)
{
    public static GlobalShortcut Default { get; } = new(0x20, ShortcutModifiers.Control | ShortcutModifiers.Alt);

    public string DisplayName => $"{(Modifiers.HasFlag(ShortcutModifiers.Control) ? "Ctrl+" : string.Empty)}{(Modifiers.HasFlag(ShortcutModifiers.Alt) ? "Alt+" : string.Empty)}{(Modifiers.HasFlag(ShortcutModifiers.Shift) ? "Shift+" : string.Empty)}{(Modifiers.HasFlag(ShortcutModifiers.Windows) ? "Win+" : string.Empty)}{KeyName}";

    private string KeyName => VirtualKey == 0x20 ? "Space" : $"VK-{VirtualKey:X2}";
}

public sealed record WriteItPreferences
{
    public int SchemaVersion { get; init; } = 1;
    public GlobalShortcut Shortcut { get; init; } = GlobalShortcut.Default;
    public RecognitionLanguage RecognitionLanguage { get; init; } = RecognitionLanguage.English;
    public HistoryMode HistoryMode { get; init; } = HistoryMode.TextOnly;
    public bool HistoryAutoDelete { get; init; } = true;
    public int HistoryRetentionDays { get; init; } = 7;
    public double StrokeWidth { get; init; } = 4;

    public void Validate()
    {
        if (SchemaVersion != 1) throw new InvalidOperationException("Unsupported preferences schema.");
        if (Shortcut.VirtualKey == 0 || Shortcut.Modifiers == ShortcutModifiers.None)
            throw new InvalidOperationException("A shortcut must include a key and modifier.");
        if (HistoryRetentionDays is < 1 or > 365)
            throw new InvalidOperationException("History retention must be between 1 and 365 days.");
        if (StrokeWidth is < 1 or > 12)
            throw new InvalidOperationException("Stroke width must be between 1 and 12.");
    }
}
