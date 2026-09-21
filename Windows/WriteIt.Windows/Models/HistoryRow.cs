using WriteIt.Windows.Core;

namespace WriteIt.Windows;

public sealed class HistoryRow(HistoryEntry entry)
{
    public HistoryEntry Entry { get; set; } = entry;

    public string Text => Entry.Text;

    public string Detail => $"{Entry.CreatedAt.LocalDateTime:g} · {Entry.DeliveryMethod}";
}
