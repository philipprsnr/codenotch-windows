using Codenotch.Core.Abstractions;

namespace Codenotch.Platform.Windows.SystemIntegration;

/// <summary>The real clock. Everything else in the app takes an <see cref="IClock"/>.</summary>
public sealed class SystemClock : IClock
{
    public DateTimeOffset UtcNow => DateTimeOffset.UtcNow;
}
