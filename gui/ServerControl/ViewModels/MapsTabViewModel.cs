using System.Collections.ObjectModel;
using System.ComponentModel;
using System.IO;
using System.Windows.Data;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using ServerControl.Services;

namespace ServerControl.ViewModels;

public sealed class MapTile {
    public required MapEntry Map { get; init; }
    public ImageSource? Preview { get; init; }

    /// <summary>Radar images are top-down plans, shown whole instead of cropped.</summary>
    public bool IsRadar { get; init; }

    public string Name => Map.Name;
    public string Prefix => Map.Name.Contains('_') ? Map.Name[..Map.Name.IndexOf('_')] : Map.Name;
    public string ModeList => Map.Modes.Count == 0 ? "not in any map list" : string.Join(", ", Map.Modes.Select(id => GameModes.Find(id).Title));
}

public sealed record MapFilter(string? ModeId, string Title);

public sealed partial class MapsTabViewModel : TabViewModel {
    private readonly Action<string> _useAsStartMap;
    private readonly ObservableCollection<MapTile> _tiles = [];

    public ICollectionView Tiles { get; }
    public IReadOnlyList<MapFilter> Filters { get; }

    [ObservableProperty]
    private MapFilter _selectedFilter;

    [ObservableProperty]
    private string _searchText = "";

    [ObservableProperty]
    private MapTile? _selectedTile;

    public MapsTabViewModel(ServerConnection connection, Action<string> useAsStartMap)
        : base("Maps", connection) {
        _useAsStartMap = useAsStartMap;
        Filters = [new MapFilter(null, "All"), .. GameModes.All.Select(mode => new MapFilter(mode.Id, mode.Title))];
        _selectedFilter = Filters[0];
        Tiles = CollectionViewSource.GetDefaultView(_tiles);
        Tiles.Filter = item => item is MapTile tile && Matches(tile);
    }

    public void ShowMode(string modeId) {
        SelectedFilter = Filters.First(filter => filter.ModeId == modeId);
    }

    public override Task ActivateAsync() {
        if (_tiles.Count == 0) {
            Reload();
        }
        return Task.CompletedTask;
    }

    partial void OnSelectedFilterChanged(MapFilter value) => Tiles.Refresh();
    partial void OnSearchTextChanged(string value) => Tiles.Refresh();

    [RelayCommand]
    private void Reload() {
        _tiles.Clear();
        foreach (MapEntry map in Connection.Maps.Load()) {
            bool isRadar = map.PreviewPath != null
                && Path.GetDirectoryName(map.PreviewPath)!.Equals(Connection.Paths.OverviewsDir, StringComparison.OrdinalIgnoreCase);
            ImageSource? preview = LoadPreview(map.PreviewPath);
            _tiles.Add(new MapTile {
                Map = map,
                Preview = isRadar && preview is BitmapSource radar ? RemoveRadarBackground(radar) : preview,
                IsRadar = isRadar,
            });
        }
    }

    [RelayCommand]
    private async Task PlayNow(MapTile? tile) {
        if (tile == null) {
            return;
        }
        if (!Connection.IsRunning) {
            Connection.AddConsoleLine("! The server is not running. Use 'Start map' to start on this map.");
            return;
        }
        await Connection.RunAsync($"amx_map {tile.Name}");
    }

    [RelayCommand]
    private void UseAsStartMap(MapTile? tile) {
        if (tile != null) {
            _useAsStartMap(tile.Name);
        }
    }

    private bool Matches(MapTile tile) {
        bool modeMatches = SelectedFilter.ModeId == null || tile.Map.Modes.Contains(SelectedFilter.ModeId);
        bool searchMatches = SearchText.Length == 0 || tile.Name.Contains(SearchText.Trim(), StringComparison.OrdinalIgnoreCase);
        return modeMatches && searchMatches;
    }

    private static ImageSource? LoadPreview(string? path) {
        if (path == null) {
            return null;
        }

        try {
            // Decoding to tile size keeps memory low with many large screenshots,
            // OnLoad releases the file so the installer can replace it.
            var image = new BitmapImage();
            image.BeginInit();
            image.UriSource = new Uri(path);
            image.DecodePixelWidth = 320;
            image.CacheOption = BitmapCacheOption.OnLoad;
            image.EndInit();
            image.Freeze();
            return image;
        } catch (Exception exception) when (exception is IOException or NotSupportedException or FileFormatException) {
            return null;
        }
    }

    /// <summary>
    /// The game draws radar images with pure green as the "nothing here" color.
    /// Making it transparent lets the tile color show through instead.
    /// </summary>
    private static BitmapSource RemoveRadarBackground(BitmapSource radar) {
        var converted = new FormatConvertedBitmap(radar, PixelFormats.Bgra32, null, 0);
        int stride = converted.PixelWidth * 4;
        byte[] pixels = new byte[stride * converted.PixelHeight];
        converted.CopyPixels(pixels, stride, 0);

        for (int i = 0; i < pixels.Length; i += 4) {
            byte blue = pixels[i];
            byte green = pixels[i + 1];
            byte red = pixels[i + 2];
            bool isBackground = green > 200 && red < 60 && blue < 60;
            if (isBackground) {
                pixels[i + 3] = 0;
            }
        }

        BitmapSource result = BitmapSource.Create(converted.PixelWidth, converted.PixelHeight, 96, 96, PixelFormats.Bgra32, null, pixels, stride);
        result.Freeze();
        return result;
    }

}
