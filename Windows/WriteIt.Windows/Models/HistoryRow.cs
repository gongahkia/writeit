using WriteIt.Windows.Core;

namespace WriteIt.Windows;

public sealed record HistoryRow(HistoryEntry Entry)
{
    public string Text => Entry.Text;

    public string Detail => $"{Entry.CreatedAt.LocalDateTime:g} · {Entry.DeliveryMethod}";
}
