using CommunityToolkit.Mvvm.ComponentModel;

namespace ServerControl.ViewModels;

/// <summary>One tab of the window.</summary>
public abstract class TabViewModel(string title, ServerConnection connection) : ObservableObject {
    public string Title { get; } = title;
    public ServerConnection Connection { get; } = connection;

    /// <summary>Called when the tab becomes visible, to refresh what it shows.</summary>
    public virtual Task ActivateAsync() {
        return Task.CompletedTask;
    }
}
