namespace Codenotch.Core.Abstractions;

/// <summary>
/// The current instant, as seen by everything in Core that cares about time.
/// </summary>
/// <remarks>
/// Not decoration. Reset windows, elapsed-time copy, the poll schedule and the
/// back-off ladder are all time-dependent, and the Swift original threads a
/// <c>now: Date = Date()</c> parameter through every one of them so its tests
/// can pin the answer. Without this seam most of those tests cannot be ported.
/// UTC only — local time is a presentation concern, and the machine's time zone
/// can change under a running app.
/// </remarks>
public interface IClock
{
    DateTimeOffset UtcNow { get; }
}
