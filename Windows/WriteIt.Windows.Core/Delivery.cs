namespace WriteIt.Windows.Core;

public enum DeliveryMethod
{
    PasteRequested,
    Clipboard,
    ClipboardFallback,
}

public sealed record DeliveryResult(DeliveryMethod Method, string Message)
{
    public static DeliveryResult PasteRequested { get; } = new(
        DeliveryMethod.PasteRequested,
        "Paste requested; recognized text remains copied to the clipboard.");

    public static DeliveryResult Clipboard { get; } = new(
        DeliveryMethod.Clipboard,
        "Copied to clipboard.");

    public static DeliveryResult ClipboardFallback(string reason) => new(
        DeliveryMethod.ClipboardFallback,
        $"Copied to clipboard: {reason}");
}
