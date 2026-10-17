using System.IO;
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
        // say what happened instead of closing silently. The full exception
        // goes into a log, the dialog only has room for the first message.
        string logFile = WriteErrorLog(e.Exception);
        Exception innermost = e.Exception.GetBaseException();
        string message = string.IsNullOrWhiteSpace(innermost.Message) ? innermost.GetType().Name : innermost.Message;
        ConfirmDialog.ShowMessage(MainWindow, "Unexpected error", $"{message}\n\nDetails: {logFile}");
        e.Handled = true;
    }

    private static string WriteErrorLog(Exception exception) {
        string logFile = Path.Combine(Path.GetDirectoryName(AppSettings.SettingsFile)!, "error.log");
        try {
            Directory.CreateDirectory(Path.GetDirectoryName(logFile)!);
            File.AppendAllText(logFile, $"{DateTime.Now:yyyy-MM-dd HH:mm:ss}\r\n{exception}\r\n\r\n");
        } catch (Exception writeError) when (writeError is IOException or UnauthorizedAccessException) {
            // Without a log the dialog still shows the message.
        }
        return logFile;
    }
}
