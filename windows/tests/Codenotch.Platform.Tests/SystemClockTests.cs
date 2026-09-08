using Codenotch.Platform.Windows.SystemIntegration;
using Xunit;

namespace Codenotch.Platform.Tests;

public class SystemClockTests
{
    [Fact]
    public void UtcNowIsUtc()
    {
        // The whole point of the seam is that no part of the app reads local
        // time; a clock handing out an offset would leak the machine's time zone
        // into reset-window arithmetic.
        Assert.Equal(TimeSpan.Zero, new SystemClock().UtcNow.Offset);
    }
}
