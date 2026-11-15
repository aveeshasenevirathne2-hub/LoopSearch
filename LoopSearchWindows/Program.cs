using Avalonia;

namespace LoopSearch;

internal static class Program
{
    private static Mutex? _singleInstanceMutex;

    [STAThread]
    public static void Main(string[] args)
    {
        _singleInstanceMutex = new Mutex(true, @"Local\LoopSearch_Windows_SingleInstance", out bool createdNew);
        if (!createdNew)
        {
            return;
        }

        try
        {
            BuildAvaloniaApp().StartWithClassicDesktopLifetime(args);
        }
        finally
        {
            _singleInstanceMutex?.ReleaseMutex();
            _singleInstanceMutex?.Dispose();
        }
    }

    public static AppBuilder BuildAvaloniaApp()
        => AppBuilder.Configure<LoopSearchApp>()
            .UsePlatformDetect()
            .LogToTrace();
}
