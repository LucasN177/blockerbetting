using System.Reflection;

namespace BlockerBetting.Services;

public static class AppInfo
{
    public const string Author = "Lucas Nagelsmann";

    /// <summary>The project &lt;Version&gt; (e.g. "1.1.0").</summary>
    public static string Version { get; } =
        typeof(AppInfo).Assembly.GetCustomAttribute<AssemblyInformationalVersionAttribute>()?.InformationalVersion.Split('+')[0]
        ?? "dev";
}
