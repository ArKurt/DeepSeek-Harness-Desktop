using System.Windows;
using Microsoft.Web.WebView2.Core;

namespace DeepSeekDesktop;

/// <summary>
/// 主窗口：WebView2 承载 DeepSeek Harness Web UI。
/// </summary>
public partial class MainWindow : Window
{
    private readonly ServerManager _server;
    private readonly string _url;

    public MainWindow(ServerManager server, string url)
    {
        InitializeComponent();
        _server = server;
        _url = url;

        Closing += OnClosing;
        Loaded += OnLoaded;
    }

    private async void OnLoaded(object sender, RoutedEventArgs e)
    {
        try
        {
            // 确保 WebView2 运行时已初始化（Windows 10/11 一般已预装）
            await WebView.EnsureCoreWebView2Async();
            WebView.CoreWebView2.Navigate(_url);

            // target=_blank 交给系统默认浏览器
            WebView.CoreWebView2.NewWindowRequested += (_, args) =>
            {
                args.Handled = true;
                try { System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo(args.Uri) { UseShellExecute = true }); }
                catch { /* 打开外部浏览器失败则忽略 */ }
            };
        }
        catch (Exception ex)
        {
            MessageBox.Show(
                $"WebView2 初始化失败：{ex.Message}\n\n请确认系统已安装 Microsoft Edge WebView2 Runtime。",
                "DeepSeek",
                MessageBoxButton.OK,
                MessageBoxImage.Error);
        }
    }

    private void OnClosing(object? sender, System.ComponentModel.CancelEventArgs e)
    {
        // 退出时清理由本 App 拉起的服务器（外部已有的服务器不动）
        _server.Shutdown();
    }
}
