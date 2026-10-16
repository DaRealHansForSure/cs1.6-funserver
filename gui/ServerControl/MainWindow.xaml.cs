using System.Collections.Specialized;
using System.Windows;

namespace ServerControl;

public partial class MainWindow : Window {
    public MainWindow() {
        InitializeComponent();

        // The newest console line should always be visible, like in a terminal.
        ((INotifyCollectionChanged)ConsoleList.Items).CollectionChanged += (_, args) => {
            if (args.Action == NotifyCollectionChangedAction.Add && ConsoleList.Items.Count > 0) {
                ConsoleList.ScrollIntoView(ConsoleList.Items[^1]);
            }
        };
    }
}
