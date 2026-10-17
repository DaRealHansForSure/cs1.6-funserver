using System.Windows;
using System.Windows.Threading;
using CsServerControl.Services;
using CsServerControl.Shell;

namespace CsServerControl;

public partial class App : Application {
    private ServerConnection? _connection;

    protected override void OnStartup(StartupEventArgs e) {
        base.OnStartup(e);
        DispatcherUnhandledException += OnUnhandledException;

        PackagePaths paths = PackagePaths.Locate();
        AppSettings settings = AppSettings.Load();
        _connection = new ServerConnection(paths, settings, Dispatcher);

        var shell = new ShellViewModel(_connection);
        var window = new MainWindow(shell, settings);
        MainWindow = window;
        window.Show();
    }

    protected override void OnExit(ExitEventArgs e) {
        _connection?.Dispose();
        base.OnExit(e);
    }

    private void OnUnhandledException(object sender, DispatcherUnhandledExceptionEventArgs e) {
        // The server keeps running without this window, so a bug here should
        // say what happened instead of closing silently.
        ConfirmDialog.ShowMessage(MainWindow, "Unexpected error", e.Exception.Message);
        e.Handled = true;
    }
}
