using System.Collections.Concurrent;
using System.IO;
using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace CsServerControl.Services;

/// <summary>
/// Small map pictures: the screenshot the installer downloaded into
/// tools\previews, else the stock radar image from cstrike\overviews.
/// </summary>
public sealed class MapThumbnails {
    // WPF reads these without extra codecs; the radar .tga files are skipped.
    private static readonly string[] Extensions = [".jpg", ".jpeg", ".png", ".bmp"];


    private readonly PackagePaths _paths;
    private readonly ConcurrentDictionary<string, ImageSource?> _cache = new(StringComparer.OrdinalIgnoreCase);

    private readonly int _decodeWidth;

    /// <summary>Small pictures for lists by default, a larger width for the details dialog.</summary>
    public MapThumbnails(PackagePaths paths, int decodeWidth = 160) {
        _decodeWidth = decodeWidth;
        _paths = paths;
    }

    public ImageSource? Get(string mapName) {
        return _cache.GetOrAdd(mapName, Load);
    }

    private ImageSource? Load(string mapName) {
        foreach (string folder in new[] { _paths.PreviewsDir, _paths.OverviewsDir }) {
            foreach (string extension in Extensions) {
                string candidate = Path.Combine(folder, mapName + extension);
                if (!File.Exists(candidate)) {
                    continue;
                }

                ImageSource? image = Decode(candidate, _decodeWidth);
                bool isRadar = folder == _paths.OverviewsDir;
                if (isRadar && image is BitmapSource radar) {
                    return RemoveRadarBackground(radar);
                }
                return image;
            }
        }
        return null;
    }

    private static ImageSource? Decode(string path, int decodeWidth) {
        try {
            // OnLoad releases the file so the installer can replace it.
            var image = new BitmapImage();
            image.BeginInit();
            image.UriSource = new Uri(path);
            image.DecodePixelWidth = decodeWidth;
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
    /// Making it transparent lets the row background show through instead.
    /// </summary>
    private static BitmapSource RemoveRadarBackground(BitmapSource radar) {
        var converted = new FormatConvertedBitmap(radar, PixelFormats.Bgra32, null, 0);
        int stride = converted.PixelWidth * 4;
        byte[] pixels = new byte[stride * converted.PixelHeight];
        converted.CopyPixels(pixels, stride, 0);

        for (int index = 0; index < pixels.Length; index += 4) {
            byte blue = pixels[index];
            byte green = pixels[index + 1];
            byte red = pixels[index + 2];
            bool isBackground = green > 200 && red < 60 && blue < 60;
            if (isBackground) {
                pixels[index + 3] = 0;
            }
        }

        BitmapSource result = BitmapSource.Create(converted.PixelWidth, converted.PixelHeight, 96, 96, PixelFormats.Bgra32, null, pixels, stride);
        result.Freeze();
        return result;
    }
}
