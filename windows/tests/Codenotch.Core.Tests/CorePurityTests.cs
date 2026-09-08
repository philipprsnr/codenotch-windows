using System.Reflection;
using System.Runtime.Versioning;
using Codenotch.Core.Abstractions;
using Xunit;

namespace Codenotch.Core.Tests;

/// <summary>
/// The first tests in the port, and not a placeholder: they assert the one
/// property that decides whether the rest of the port can be verified at all.
/// </summary>
/// <remarks>
/// The build guard in windows/Directory.Build.props is the real enforcement —
/// it sees every resolved reference, including the ones the compiler ends up
/// not needing. These two are the cheap second line: they fail in the test
/// output rather than in a build log, and they fail on the maintainer's machine
/// too, where a Windows-only reference would otherwise compile happily.
/// </remarks>
public class CorePurityTests
{
    private static readonly Assembly Core = typeof(IClock).Assembly;

    [Fact]
    public void CoreTargetsAFrameworkWithNoPlatform()
    {
        var framework = Core.GetCustomAttribute<TargetFrameworkAttribute>()?.FrameworkName;

        // ".NETCoreApp,Version=v10.0" — anything with a platform in it, such as
        // ",Profile=Windows", means Core has stopped building away from Windows.
        Assert.Equal(".NETCoreApp,Version=v10.0", framework);
    }

    [Fact]
    public void CoreReferencesNothingPlatformSpecific()
    {
        string[] forbidden =
        [
            "PresentationFramework",
            "PresentationCore",
            "WindowsBase",
            "System.Xaml",
            "System.Windows.Forms",
            "System.Drawing.Common",
            "System.Management",
            "Microsoft.Win32.Registry",
            "Microsoft.Win32.SystemEvents",
            "Microsoft.Windows.SDK.NET",
            "Codenotch.Platform.Windows",
            "Codenotch.App",
        ];

        var referenced = Core.GetReferencedAssemblies()
            .Select(a => a.Name)
            .OfType<string>()
            .ToArray();

        Assert.Empty(referenced.Intersect(forbidden, StringComparer.OrdinalIgnoreCase));
    }
}
