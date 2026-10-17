using System.Collections.ObjectModel;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Windows;
using System.Windows.Media;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using CsServerControl.Server;
using CsServerControl.Services;
using CsServerControl.Shell;

namespace CsServerControl.Maps;

public sealed partial class MapLibraryRowViewModel : ObservableObject {
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(HasPicture))]
    private ImageSource? _thumbnail;

    public MapLibraryRowViewModel(MapLibraryEntry entry, ImageSource? thumbnail) {
        Entry = entry;
        _thumbnail = thumbnail;
    }

    public MapLibraryEntry Entry { get; }
    public string Name => Entry.Name;
    public bool HasNav => Entry.HasNav;
    public bool HasPicture => Thumbnail != null;
    public bool IsInNoMode => Entry.ModeIds.Count == 0;

    public string ModesText {
        get {
            if (Entry.ModeIds.Count == 0) {
                return "In no map list";
            }
            return string.Join(", ", Entry.ModeIds.Select(GameModes.TitleOf));
        }
    }

    public string SourceText {
        get {
            switch (Entry.Source) {
                case MapSource.Stock:
                    return "Stock";
                case MapSource.MapPack:
                    return "Map pack";
                default:
                    return "Custom";
            }
        }
    }

    public string NavText => HasNav ? "Present" : "Missing";
    public string SizeText => (Entry.SizeBytes / 1024.0 / 1024.0).ToString("0.0", CultureInfo.InvariantCulture) + " MB";

    /// <summary>The first mode with a tile on the Server screen, where Pick takes the map.</summary>
    public string? PickModeId => Entry.ModeIds.FirstOrDefault(modeId => GameModes.All.Any(mode => mode.Id == modeId));
    public bool CanPick => PickModeId != null;
}

/// <summary>What the Show list narrows the table to.</summary>
public sealed record MapFilter(string Title, Func<MapLibraryRowViewModel, bool> Matches);

/// <summary>
/// The Maps screen: every installed map in one table, with the modes that
/// play it, its nav file and picture, plus the custom-maps folder. Actions
/// that change the server go through the screen that owns them (Pick to
/// the Server draft, nav files to the Bots queue, Update maps to Install).
/// </summary>
public sealed partial class MapsViewModel : ObservableObject, IScreen {
    private readonly ServerConnection _connection;
    private readonly IDialogService _dialogs;
    private readonly MapThumbnails _thumbnails;
    private readonly Func<string, string, bool> _pickOnServer;
    private readonly Action _queueMissingNavs;
    private readonly Func<Task> _updateMaps;
    private List<MapLibraryRowViewModel> _allRows = [];

    [ObservableProperty]
    private MapFilter _selectedFilter;

    [ObservableProperty]
    private string _searchText = "";

    [ObservableProperty]
    private string _summary = "";

    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(CanGenerateThumbnails))]
    private bool _isGenerating;

    [ObservableProperty]
    private string _generateProgress = "";

    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(CanGenerateThumbnails), nameof(GenerateThumbnailsText))]
    private int _missingPictureCount;

    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(QueueNavText), nameof(CanQueueNavs))]
    private int _missingNavCount;

    public MapsViewModel(ServerConnection connection, IDialogService dialogs, Func<string, string, bool> pickOnServer,
            Action queueMissingNavs, Func<Task> updateMaps) {
        _connection = connection;
        _dialogs = dialogs;
        _pickOnServer = pickOnServer;
        _queueMissingNavs = queueMissingNavs;
        _updateMaps = updateMaps;
        _thumbnails = new MapThumbnails(connection.Paths);

        List<MapFilter> filters = [new("All maps", _ => true)];
        foreach (string modeId in Install.MapModes.AllModes) {
            filters.Add(new MapFilter(GameModes.TitleOf(modeId), row => row.Entry.ModeIds.Contains(modeId)));
        }
        // Like the Bots queue: only maps in a map list get a nav file built.
        filters.Add(new MapFilter("Missing navigation", row => !row.HasNav && !row.IsInNoMode));
        filters.Add(new MapFilter("Missing picture", row => !row.HasPicture));
        filters.Add(new MapFilter("In no map list", row => row.IsInNoMode));
        filters.Add(new MapFilter("Custom maps", row => row.Entry.Source == MapSource.Custom));
        Filters = filters;
        _selectedFilter = filters[0];
    }

    public IReadOnlyList<MapFilter> Filters { get; }
    public ObservableCollection<MapLibraryRowViewModel> Rows { get; } = [];
    public ObservableCollection<WaitingMap> WaitingMaps { get; } = [];
    public bool IsServerRunning => _connection.IsRunning;
    public bool CanGenerateThumbnails => !IsGenerating && MissingPictureCount > 0;
    public string GenerateThumbnailsText => $"Generate missing pictures ({MissingPictureCount})";
    public bool CanQueueNavs => MissingNavCount > 0;
    public string QueueNavText => $"Queue missing navigation ({MissingNavCount})";
    public string CustomMapsDir => Path.Combine(_connection.Paths.RootDir, "custom-maps");

    public IReadOnlyList<string> StatusItems => [Summary];
    public string StatusRight => "Pictures from tools\\previews";

    public void OnShown() {
        _ = RefreshAsync();
    }

    public void OnHidden() {
    }

    partial void OnSelectedFilterChanged(MapFilter value) {
        ApplyFilter();
    }

    partial void OnSearchTextChanged(string value) {
        ApplyFilter();
    }

    [RelayCommand]
    private async Task RefreshAsync() {
        PackagePaths paths = _connection.Paths;
        (IReadOnlyList<MapLibraryEntry> entries, IReadOnlyList<WaitingMap> waiting) = await Task.Run(() =>
            (MapLibrary.Scan(paths), MapLibrary.ScanCustomMaps(CustomMapsDir, paths.MapsDir)));

        _allRows = entries.Select(entry => new MapLibraryRowViewModel(entry, _thumbnails.Get(entry.Name))).ToList();
        WaitingMaps.Clear();
        foreach (WaitingMap map in waiting) {
            WaitingMaps.Add(map);
        }
        UpdateCounts();
        ApplyFilter();
    }

    [RelayCommand]
    private async Task ShowDetails(MapLibraryRowViewModel? row) {
        if (row == null) {
            return;
        }
        string? modeId = row.PickModeId;
        Action? pick = null;
        if (modeId != null) {
            pick = () => _pickOnServer(modeId, row.Name);
        }
        var details = new MapDetailsViewModel(_connection, row.Name, GameModes.TitleOf(modeId), pick, () => SetNextMap(row));
        await _dialogs.ShowAsync(details);
    }

    [RelayCommand]
    private void PickOnServer(MapLibraryRowViewModel? row) {
        string? modeId = row?.PickModeId;
        if (row == null || modeId == null) {
            return;
        }
        _pickOnServer(modeId, row.Name);
    }

    [RelayCommand]
    private async Task SetNextMap(MapLibraryRowViewModel? row) {
        if (row == null || !_connection.IsRunning) {
            return;
        }
        await _connection.RunAsync($"amx_nextmap {row.Name}");
        _connection.NextMap = row.Name;
    }

    /// <summary>
    /// One map after the other on the UI thread: WPF renders there, and the
    /// .bsp reading in between runs in the background.
    /// </summary>
    [RelayCommand]
    private async Task GenerateThumbnails() {
        if (IsGenerating) {
            return;
        }
        IsGenerating = true;
        try {
            Color Read(string key) => (Color)Application.Current.FindResource(key);
            var generator = new ThumbnailGenerator(_connection.Paths, Read("ViewportBackgroundColor"), Read("WireLowColor"), Read("WireHighColor"));
            List<MapLibraryRowViewModel> missing = _allRows.Where(row => !row.HasPicture).ToList();
            int failed = 0;
            for (int index = 0; index < missing.Count; index++) {
                MapLibraryRowViewModel row = missing[index];
                GenerateProgress = $"Rendering {index + 1} of {missing.Count}: {row.Name}";
                if (await generator.GenerateAsync(row.Name)) {
                    row.Thumbnail = _thumbnails.Get(row.Name);
                } else {
                    failed++;
                }
            }
            GenerateProgress = failed == 0 ? $"{missing.Count} pictures rendered" : $"{missing.Count - failed} pictures rendered, {failed} maps could not be read";
            UpdateCounts();
        } finally {
            IsGenerating = false;
        }
    }

    [RelayCommand]
    private void QueueMissingNavs() {
        _queueMissingNavs();
    }

    [RelayCommand]
    private async Task UpdateMaps() {
        await _updateMaps();
    }

    [RelayCommand]
    private void OpenCustomMapsFolder() {
        Directory.CreateDirectory(CustomMapsDir);
        Process.Start(new ProcessStartInfo { FileName = CustomMapsDir, UseShellExecute = true });
    }

    private void UpdateCounts() {
        MissingPictureCount = _allRows.Count(row => !row.HasPicture);
        MissingNavCount = _allRows.Count(row => !row.HasNav && !row.IsInNoMode);
        string waitingText = WaitingMaps.Count == 0 ? "" : $" · {WaitingMaps.Count} waiting in custom-maps";
        Summary = $"{_allRows.Count} maps · {MissingNavCount} without navigation · {MissingPictureCount} without picture{waitingText}";
    }

    private void ApplyFilter() {
        string search = SearchText.Trim();
        Rows.Clear();
        foreach (MapLibraryRowViewModel row in _allRows) {
            bool matchesSearch = search.Length == 0 || row.Name.Contains(search, StringComparison.OrdinalIgnoreCase);
            if (matchesSearch && SelectedFilter.Matches(row)) {
                Rows.Add(row);
            }
        }
    }
}
