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

    private string KeyName => VirtualKey switch
    {
        0x20 => "Space",
        >= 0x30 and <= 0x39 => ((char)(ushort)VirtualKey).ToString(),
        >= 0x41 and <= 0x5A => ((char)(ushort)VirtualKey).ToString(),
        _ => $"VK-{VirtualKey:X2}",
    };

    public static bool TryParse(string? input, out GlobalShortcut? shortcut, out string? error)
    {
        shortcut = null;
        error = null;
        var parts = input?.Split('+', StringSplitOptions.TrimEntries | StringSplitOptions.RemoveEmptyEntries) ?? [];
        if (parts.Length < 2)
        {
            error = "Use a modifier and key, for example Ctrl+Alt+Space.";
            return false;
        }

        var modifiers = ShortcutModifiers.None;
        uint? virtualKey = null;
        foreach (var part in parts)
        {
            switch (part.ToUpperInvariant())
            {
                case "CTRL" or "CONTROL": modifiers |= ShortcutModifiers.Control; break;
                case "ALT": modifiers |= ShortcutModifiers.Alt; break;
                case "SHIFT": modifiers |= ShortcutModifiers.Shift; break;
                case "WIN" or "WINDOWS": modifiers |= ShortcutModifiers.Windows; break;
                case "SPACE" when virtualKey is null: virtualKey = 0x20; break;
                case { Length: 1 } key when key[0] is >= 'A' and <= 'Z': virtualKey = key[0]; break;
                case { Length: 1 } key when key[0] is >= '0' and <= '9': virtualKey = key[0]; break;
                default:
                    error = "Use Ctrl, Alt, Shift, Win, Space, or one letter or number.";
                    return false;
            }
        }

        if (virtualKey is null || modifiers == ShortcutModifiers.None)
        {
            error = "A shortcut needs at least one modifier and one key.";
            return false;
        }

        shortcut = new GlobalShortcut(virtualKey.Value, modifiers);
        return true;
    }
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
