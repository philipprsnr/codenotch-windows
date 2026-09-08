# Windows port — decisions

Choices that could reasonably have gone the other way, and what settled them
(rule E3). Not a log of everything.

---

## 2026-09-08 — M0

### The tray icon is WinForms `NotifyIcon`

WPF has no notification-area icon. The three options were a `Shell_NotifyIcon`
P/Invoke in `Codenotch.Platform.Windows`, the `Hardcodet.NotifyIcon.Wpf`
package, or `System.Windows.Forms.NotifyIcon` behind `UseWindowsForms=true`.

WinForms won on risk. The package is a dependency, and dependencies are the
maintainer's call (rule E1) — not something to spend on a placeholder icon. The
P/Invoke is a hand-laid-out `NOTIFYICONDATAW` and a message-only window written
in a session that cannot compile or run either, which is exactly the kind of
code rule C1 exists to distrust. `NotifyIcon` is fifteen lines that have worked
for twenty years.

The cost is one collision: WinForms and WPF both define `Application`,
`MessageBox` and `Clipboard`, and the WinForms implicit global using makes every
one of them ambiguous. `Codenotch.App.csproj` removes that using; `TrayIcon.cs`
names the namespace itself.

Revisit at M6, when the tray menu has to match the Fluent presentation and a
WinForms `ContextMenuStrip` may start to look out of place.

### Tests are xunit.v3 on Microsoft.Testing.Platform

xunit.v3 carries its own runner rather than going through VSTest, and the .NET
10 SDK refuses to drive an MTP test project through the VSTest path at all — the
error is explicit about it. So there is no `Microsoft.NET.Test.Sdk` and no
`xunit.runner.visualstudio` in `Directory.Packages.props`.

Two consequences worth knowing before they surprise someone: `dotnet test` needs
the opt-in in `windows/global.json`, and every test project needs
`<OutputType>Exe</OutputType>` because the runner lives in the test assembly.
`dotnet test` also wants `--project <csproj>` now; a bare path is rejected.

The alternative was xunit v2 on VSTest, which still works but is the path the
SDK is walking away from.

### The purity guard ignores the base shared framework

`WindowsBase` and `Microsoft.Win32.Registry` are on the forbidden list and also
ship as facades inside the `Microsoft.NETCore.App` targeting pack, so a
name-only check fails every clean build. The guard therefore skips references
carrying `FrameworkReferenceName == Microsoft.NETCore.App`.

That leaves a theoretical hole — Core could call `Registry.CurrentUser` through
the facade. It is closed by CA1416, which is on by default and an error here
because `TreatWarningsAsErrors` is on. Checked: the call is refused with
*"'Registry.CurrentUser' is only supported on: 'windows'"*.

### `EnableWindowsTargeting=true` for everything under `windows/`

Without it the SDK refuses to even restore a `net10.0-windows` project off
Windows (NETSDK1100), which would mean no Linux session could run
`dotnet restore Codenotch.sln`. It is a no-op on Windows.

Unexpected side effect, recorded because it will be noticed: with it, the .NET
10 SDK compiles the whole solution on Linux, WPF project included. That is
useful — it catches C# mistakes in the session that writes them — and it changes
nothing about rule C1. A compiled WPF project has still never had a window on
screen.

### Classic `.sln`, not `.slnx`

`dotnet new sln` produces `.slnx` by default on the .NET 10 SDK. The plan says
`Codenotch.sln`, and the classic format is read by every version of Visual
Studio and Rider rather than only recent ones. Created with
`dotnet new sln --format sln`.

### `Codenotch.Platform.Windows/SystemIntegration/`, not `System/`

[`01-ARCHITECTURE.md`](01-ARCHITECTURE.md) §2 names the folder `System/`. A
namespace ending in `.System` shadows the real `System` namespace inside its own
files, so `System.Text.Json` starts resolving to the wrong place. Renamed rather
than left as a trap for the first file that needs a `System.*` type.
