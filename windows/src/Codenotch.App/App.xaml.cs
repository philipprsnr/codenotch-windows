using System.Windows;
using Codenotch.App.Tray;
using Codenotch.Core.Abstractions;
using Codenotch.Platform.Windows.SystemIntegration;

namespace Codenotch.App;

/// <summary>
/// Composition root. Builds the Core objects, hands them the Windows
/// implementations of the seams, and owns the app's lifetime.
/// </summary>
/// <remarks>
/// There is deliberately no <c>StartupUri</c>: Codenotch has no main window.
/// The notch is its own window, created in M1; until then the tray icon is the
/// only thing the app puts on screen. <c>ShutdownMode.OnExplicitShutdown</c> in
/// App.xaml is what keeps a windowless app alive.
/// </remarks>
public partial class App : Application
{
    private TrayIcon? _tray;

    // Held so that the composition root reads as the composition root even
    // while it wires exactly one thing. The seams arrive in M4-M6.
    private readonly IClock _clock = new SystemClock();

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);

        _tray = new TrayIcon();
        _tray.QuitRequested += (_, _) => Shutdown();
        _tray.Show($"Codenotch — started {_clock.UtcNow:u}");
    }

    protected override void OnExit(ExitEventArgs e)
    {
        // The notification area keeps a dead icon around until something hovers
        // over it, so removing it explicitly is not optional.
        _tray?.Dispose();
        base.OnExit(e);
    }
}
