using System.Globalization;
using BlockerBetting.Models;

namespace BlockerBetting.Services;

/// <summary>Formatting helpers shared by the UI.</summary>
public static class Fmt
{
    private static readonly CultureInfo De = CultureInfo.GetCultureInfo("de-DE");

    public static string Coins(long value) => value.ToString("N0", De);

    public static string Odds(decimal odds) => odds.ToString("0.00", De);

    public static string Date(DateTime utc) => utc.ToLocalTime().ToString("dd.MM.yyyy, HH:mm", De);

    public static string ShortDate(DateTime utc) => utc.ToLocalTime().ToString("dd.MM., HH:mm", De);

    /// <summary>"noch 2 T 4 Std", "noch 35 Min", or null when no deadline / already passed.</summary>
    public static string? TimeLeft(DateTime? closesAtUtc)
    {
        if (closesAtUtc is null) return null;
        var left = closesAtUtc.Value - DateTime.UtcNow;
        if (left <= TimeSpan.Zero) return null;
        if (left.TotalDays >= 1) return $"noch {(int)left.TotalDays} T {left.Hours} Std";
        if (left.TotalHours >= 1) return $"noch {(int)left.TotalHours} Std {left.Minutes} Min";
        return $"noch {Math.Max(1, (int)left.TotalMinutes)} Min";
    }

    public static string Initials(string? name)
    {
        var parts = (name ?? "").Split(' ', StringSplitOptions.RemoveEmptyEntries);
        return parts.Length switch
        {
            0 => "?",
            1 => parts[0][..Math.Min(2, parts[0].Length)].ToUpperInvariant(),
            _ => $"{char.ToUpperInvariant(parts[0][0])}{char.ToUpperInvariant(parts[^1][0])}",
        };
    }

    public static string Greeting()
    {
        var hour = DateTime.Now.Hour;
        return hour switch { < 11 => "Guten Morgen", < 18 => "Hallo", _ => "Guten Abend" };
    }

    public static (string Label, string Css) Status(BetRequest request) => request.Status switch
    {
        RequestStatus.Pending => ("In Prüfung", "bb-tint-warning bb-pill-live"),
        RequestStatus.Approved => ("Genehmigt", "bb-tint-success"),
        RequestStatus.Rejected => ("Abgelehnt", "bb-tint-error"),
        RequestStatus.Withdrawn => ("Zurückgezogen", "bb-pill-neutral"),
        _ => (request.Status, "bb-pill-neutral"),
    };

    public static (string Label, string Css) Status(BetEvent ev) => ev.Status switch
    {
        EventStatus.Open when ev.AcceptsBets => ("Live", "bb-tint-success bb-pill-live"),
        EventStatus.Open => ("Wettschluss", "bb-tint-warning"),
        EventStatus.Locked => ("Geschlossen", "bb-tint-warning"),
        EventStatus.Resolved => ("Entschieden", "bb-tint-info"),
        EventStatus.Cancelled => ("Abgebrochen", "bb-pill-neutral"),
        _ => (ev.Status, "bb-pill-neutral"),
    };
}
