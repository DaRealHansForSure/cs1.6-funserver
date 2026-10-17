using System.IO;
using System.Windows.Threading;
using CsServerControl.Install;
using CsServerControl.Maps;
using CsServerControl.Options;
using CsServerControl.Services;
using CsServerControl.Shell;
using Xunit;

namespace CsServerControl.Tests;

/// <summary>
/// Builds the screens the way the window does at startup, without a window.
/// A constructor that throws here leaves the real app without a window.
/// </summary>
public class ScreenStartupTests : IDisposable {
    private readonly string _rootDir = Path.Combine(Path.GetTempPath(), "cs16-startup-tests-" + Guid.NewGuid().ToString("N"));
    private readonly ServerConnection _connection;

    public ScreenStartupTests() {
        Directory.CreateDirectory(Path.Combine(_rootDir, "tools"));
        var settings = new AppSettings { RconPassword = "test-only", FilePath = Path.Combine(_rootDir, "settings.json") };
        _connection = new ServerConnection(new PackagePaths(_rootDir), settings, Dispatcher.CurrentDispatcher);
    }

    public void Dispose() {
        _connection.Dispose();
        FileTree.DeleteFolderQuietly(_rootDir);
    }

    [Fact]
    public void OptionsStartsWithoutChangesAndOffersAutomaticFirst() {
        var options = new OptionsViewModel(_connection, [new OptionChoice("Server", "Server")]);

        Assert.False(options.IsDirty);
        Assert.Equal("", options.SelectedAddress.Value);
        Assert.Equal("", options.AddressChoices[0].Value);
        Assert.Equal("", options.SelectedStartScreen.Value);
    }

    [Fact]
    public void MapsStartsOnAnEmptyPackage() {
        var maps = new MapsViewModel(_connection, new NoDialogs(), (_, _) => false, () => { }, () => Task.CompletedTask);

        Assert.Equal("All maps", maps.SelectedFilter.Title);
        Assert.Empty(maps.Rows);
    }

    private sealed class NoDialogs : IDialogService {
        public Task<bool> ConfirmAsync(string title, string message, string okText) {
            return Task.FromResult(false);
        }

        public Task ShowAsync(ModalViewModel modal) {
            return Task.CompletedTask;
        }
    }
}
