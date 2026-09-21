using System.Collections.ObjectModel;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using WriteIt.Windows.Core;
using WriteIt.Windows.Models;
using WriteIt.Windows.Services;

namespace WriteIt.Windows;

public sealed partial class MainWindow : Window
{
    private readonly string _applicationDirectory = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "WriteIt");
    private readonly CaptureLifecycle _lifecycle = new();
    private readonly WindowsOcrRecognizer _recognizer = new();
    private readonly WindowsClipboardDelivery _delivery = new();
    private readonly CaptureOverlayWindow _overlay = new();
    private readonly ObservableCollection<HistoryRow> _historyRows = [];
    private JsonPreferencesStore? _preferencesStore;
    private ProtectedHistoryStore? _historyStore;
    private GlobalHotKeyService? _hotKey;
    private WriteItPreferences _preferences = new();
    private List<HistoryEntry> _history = [];
    private IntPtr _targetWindow;
    private bool _loading;
    private bool _initialized;

    public ObservableCollection<HistoryRow> HistoryEntries => _historyRows;

    public MainWindow()
    {
        InitializeComponent();
        Root.DataContext = this;
        Closed += MainWindow_Closed;
        _overlay.Submitted += RecognizeAndDeliverAsync;
        _overlay.Cancelled += Overlay_Cancelled;
        Activated += MainWindow_Activated;
    }

    private async void MainWindow_Activated(object sender, WindowActivatedEventArgs args)
    {
        if (_initialized) return;
        _initialized = true;
        Directory.CreateDirectory(_applicationDirectory);
        _preferencesStore = new JsonPreferencesStore(_applicationDirectory);
        _historyStore = new ProtectedHistoryStore(_applicationDirectory);
        try
        {
            _preferences = await _preferencesStore.LoadAsync();
            _history = (await _historyStore.LoadAsync()).ToList();
            ApplyRetention();
            PopulateSettings();
            RegisterShortcut();
            SetStatus("Ready", "Press the shortcut or select Start writing.", InfoBarSeverity.Informational);
        }
        catch (Exception exception)
        {
            PopulateSettings();
            SetStatus("Setup needs attention", exception.Message, InfoBarSeverity.Error);
        }
    }

    private void PopulateSettings()
    {
        _loading = true;
        try
        {
            ShortcutText.Text = _preferences.Shortcut.DisplayName;
            var languageOptions = _recognizer.AvailableLanguages
                .OrderBy(language => RecognitionLanguages.Tags[language])
                .Select(language => new LanguageOption(language))
                .ToArray();
            LanguagePicker.ItemsSource = languageOptions;
            LanguagePicker.SelectedItem = languageOptions.FirstOrDefault(
                option => option.Language == _preferences.RecognitionLanguage);
            HistoryModePicker.SelectedIndex = _preferences.HistoryMode switch
            {
                HistoryMode.TextOnly => 0,
                HistoryMode.Full => 1,
                HistoryMode.Off => 2,
                _ => 0,
            };
            AutoDeleteToggle.IsOn = _preferences.HistoryAutoDelete;
            RetentionDaysBox.Value = _preferences.HistoryRetentionDays;
            StrokeWidthBox.Value = _preferences.StrokeWidth;
            _overlay.SetStrokeWidth(_preferences.StrokeWidth);
            StartCaptureButton.IsEnabled = RecognitionLanguageResolver.Resolve(
                _preferences.RecognitionLanguage,
                _recognizer.AvailableLanguages) is not null;
            RefreshHistoryRows();
        }
        finally
        {
            _loading = false;
        }
    }

    private void RegisterShortcut()
    {
        _hotKey?.Dispose();
        _hotKey = new GlobalHotKeyService();
        _hotKey.Pressed += (_, _) => DispatcherQueue.TryEnqueue(StartCapture);
        _hotKey.Register(_preferences.Shortcut);
    }

    private void StartCapture()
    {
        if (RecognitionLanguageResolver.Resolve(_preferences.RecognitionLanguage, _recognizer.AvailableLanguages) is null)
        {
            SetStatus("Recognition unavailable", "Install English or the selected Windows OCR language pack before capturing.", InfoBarSeverity.Warning);
            return;
        }

        if (!_lifecycle.Begin()) return;
        var ownWindow = WindowPlacement.HandleFor(this);
        _targetWindow = _delivery.CaptureTarget(ownWindow);
        _overlay.Present(_targetWindow);
        SetStatus("Writing", _targetWindow == IntPtr.Zero ? "No previous app target was captured; the result will be copied." : "Write, then choose Recognize.", InfoBarSeverity.Informational);
    }

    private async Task RecognizeAndDeliverAsync(byte[] png, byte[]? ink)
    {
        if (!_lifecycle.BeginRecognition()) return;
        try
        {
            var recognized = await _recognizer.RecognizeAsync(png, _preferences.RecognitionLanguage);
            if (!_lifecycle.BeginDelivery()) return;
            var outcome = _delivery.Deliver(recognized.Text, _targetWindow);
            _lifecycle.CompleteDelivery(outcome.Message);
            await AddHistoryAsync(recognized, outcome, ink);
            var notice = recognized.Resolution.UsedFallback
                ? $" Used English because {RecognitionLanguages.DisplayName(recognized.Resolution.Requested)} is unavailable."
                : String.Empty;
            _overlay.ShowResult(recognized.Text, outcome.Method == DeliveryMethod.PasteRequested ? "Paste requested" : "Copied to clipboard", outcome.Message + notice);
            SetStatus("Done", outcome.Message + notice, InfoBarSeverity.Success);
        }
        catch (Exception exception)
        {
            _lifecycle.Fail(exception.Message);
            _overlay.ShowResult(String.Empty, "Couldn’t read handwriting", exception.Message);
            SetStatus("Recognition failed", exception.Message, InfoBarSeverity.Error);
        }
    }

    private async Task AddHistoryAsync(RecognitionResult recognized, DeliveryResult outcome, byte[]? ink)
    {
        if (_preferences.HistoryMode == HistoryMode.Off || _historyStore is null) return;
        var historyInk = _preferences.HistoryMode == HistoryMode.Full ? ink : null;
        _history.Insert(0, HistoryEntry.Create(recognized.Text, "windows-ocr", outcome.Method.ToString(), recognized.Resolution.Resolved, historyInk));
        ApplyRetention();
        await _historyStore.SaveAsync(_history);
        RefreshHistoryRows();
    }

    private void ApplyRetention()
    {
        if (_preferences.HistoryAutoDelete)
            _history = HistoryRetention.Retain(_history, DateTimeOffset.UtcNow, _preferences.HistoryRetentionDays).ToList();
    }

    private void RefreshHistoryRows()
    {
        _historyRows.Clear();
        foreach (var entry in _history.OrderByDescending(entry => entry.CreatedAt)) _historyRows.Add(new HistoryRow(entry));
    }

    private async Task SavePreferencesAsync()
    {
        if (_preferencesStore is null || _loading) return;
        try
        {
            _preferences.Validate();
            await _preferencesStore.SaveAsync(_preferences);
            ApplyRetention();
            if (_historyStore is not null) await _historyStore.SaveAsync(_history);
            RefreshHistoryRows();
        }
        catch (Exception exception)
        {
            SetStatus("Couldn’t save settings", exception.Message, InfoBarSeverity.Error);
        }
    }

    private void StartCaptureButton_Click(object sender, RoutedEventArgs e) => StartCapture();

    private async void ApplyShortcutButton_Click(object sender, RoutedEventArgs e)
    {
        if (!GlobalShortcut.TryParse(ShortcutText.Text, out var shortcut, out var error))
        {
            SetStatus("Shortcut is invalid", error!, InfoBarSeverity.Warning);
            return;
        }

        var previous = _preferences;
        _preferences = _preferences with { Shortcut = shortcut! };
        try
        {
            RegisterShortcut();
            await SavePreferencesAsync();
            ShortcutText.Text = _preferences.Shortcut.DisplayName;
            SetStatus("Shortcut updated", $"{_preferences.Shortcut.DisplayName} is ready to capture.", InfoBarSeverity.Success);
        }
        catch (Exception exception)
        {
            _preferences = previous;
            try
            {
                RegisterShortcut();
            }
            catch
            {
                // The original shortcut is unavailable too; preserve the actionable registration error below.
            }

            ShortcutText.Text = _preferences.Shortcut.DisplayName;
            SetStatus("Shortcut unavailable", exception.Message, InfoBarSeverity.Error);
        }
    }

    private async void LanguagePicker_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (_loading || LanguagePicker.SelectedItem is not LanguageOption option) return;
        _preferences = _preferences with { RecognitionLanguage = option.Language };
        await SavePreferencesAsync();
    }

    private async void HistoryModePicker_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (_loading || HistoryModePicker.SelectedItem is not ComboBoxItem item || item.Tag is not string value) return;
        if (!Enum.TryParse<HistoryMode>(value, out var mode)) return;
        _preferences = _preferences with { HistoryMode = mode };
        await SavePreferencesAsync();
    }

    private async void AutoDeleteToggle_Toggled(object sender, RoutedEventArgs e)
    {
        if (_loading) return;
        _preferences = _preferences with { HistoryAutoDelete = AutoDeleteToggle.IsOn };
        await SavePreferencesAsync();
    }

    private async void RetentionDaysBox_ValueChanged(NumberBox sender, NumberBoxValueChangedEventArgs args)
    {
        if (_loading || Double.IsNaN(args.NewValue)) return;
        _preferences = _preferences with { HistoryRetentionDays = Math.Clamp((int)Math.Round(args.NewValue), 1, 365) };
        await SavePreferencesAsync();
    }

    private async void StrokeWidthBox_ValueChanged(NumberBox sender, NumberBoxValueChangedEventArgs args)
    {
        if (_loading || Double.IsNaN(args.NewValue)) return;
        var width = Math.Clamp(args.NewValue, 1, 12);
        _preferences = _preferences with { StrokeWidth = width };
        _overlay.SetStrokeWidth(width);
        await SavePreferencesAsync();
    }

    private void Overlay_Cancelled(object? sender, EventArgs e)
    {
        _overlay.HideOverlay();
        _lifecycle.Dismiss();
        SetStatus("Ready", "Capture cancelled.", InfoBarSeverity.Informational);
    }

    private void MainWindow_Closed(object sender, WindowEventArgs args)
    {
        _hotKey?.Dispose();
        _overlay.Close();
    }

    private void SetStatus(string title, string message, InfoBarSeverity severity)
    {
        StatusInfoBar.Title = title;
        StatusInfoBar.Message = message;
        StatusInfoBar.Severity = severity;
        StatusInfoBar.IsOpen = true;
    }
}
