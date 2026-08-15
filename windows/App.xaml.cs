using System.Windows;

namespace DeepSeekDesktop;

public partial class App : Application
{
    private ServerManager? _server;
    private SplashWindow? _splash;
    private MainWindow? _main;

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);

        // 先显示启动动画窗口
        _splash = new SplashWindow();
        _splash.Show();

        // 尽早拉起本地服务器（与界面并行）
        _server = new ServerManager();
        _ = StartupAsync();
    }

    private async Task StartupAsync()
    {
        string? error = null;
        try
        {
            await _server!.EnsureServerAsync();
        }
        catch (Exception ex)
        {
            error = ex.Message;
        }

        // 保证动画至少播放完（约 5 秒），服务器就绪后切换主窗口
        await Task.Delay(TimeSpan.FromSeconds(5));

        await Dispatcher.InvokeAsync(() =>
        {
            _splash?.Close();
            _splash = null;

            if (error == null)
            {
                _main = new MainWindow(_server!, _server!.BaseUrl);
                _main.Show();
            }
            else
            {
                MessageBox.Show(
                    $"DeepSeek 启动失败：{error}",
                    "DeepSeek",
                    MessageBoxButton.OK,
                    MessageBoxImage.Error);
                Shutdown(1);
            }
        });
    }

    protected override void OnExit(ExitEventArgs e)
    {
        _server?.Shutdown();
        base.OnExit(e);
    }
}
