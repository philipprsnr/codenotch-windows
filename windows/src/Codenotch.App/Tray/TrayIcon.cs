using System.Drawing;
using System.Windows.Forms;

namespace Codenotch.App.Tray;

/// <summary>
/// The notification-area icon and its menu.
/// </summary>
/// <remarks>
/// WinForms' <see cref="NotifyIcon"/> rather than WPF, because WPF has none:
/// see docs/windows/DECISIONS.md. The menu is WinForms too for now; M6 decides
/// whether the real menu is worth rendering in WPF for the Fluent presentation.
/// </remarks>
public sealed class TrayIcon : IDisposable
{
    private readonly NotifyIcon _icon;

    public event EventHandler? QuitRequested;

    public TrayIcon()
    {
        var menu = new ContextMenuStrip();
        menu.Items.Add("Quit Codenotch", null, (_, _) => QuitRequested?.Invoke(this, EventArgs.Empty));

        _icon = new NotifyIcon
        {
            // A real icon arrives with the rest of the packaging assets in M9.
            Icon = SystemIcons.Application,
            ContextMenuStrip = menu,
            Visible = false,
        };
    }

    public void Show(string tooltip)
    {
        // Win32 truncates the tooltip at 127 characters and silently drops the
        // whole NOTIFYICONDATA on some builds if it is longer.
        _icon.Text = tooltip.Length <= 127 ? tooltip : tooltip[..127];
        _icon.Visible = true;
    }

    public void Dispose()
    {
        _icon.Visible = false;
        _icon.ContextMenuStrip?.Dispose();
        _icon.Dispose();
    }
}
