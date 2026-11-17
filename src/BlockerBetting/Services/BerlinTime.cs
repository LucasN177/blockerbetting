namespace BlockerBetting.Services;

/// <summary>
/// Central time handling: everything is stored and compared in UTC, everything the user sees or
/// enters is in German time (Europe/Berlin) – independent of the device's time zone.
/// </summary>
public static class BerlinTime
{
    public static readonly TimeZoneInfo Zone = TimeZoneInfo.FindSystemTimeZoneById("Europe/Berlin");

    /// <summary>
    /// Normalizes a value to UTC. Supabase returns timestamps with an offset, which .NET turns into
    /// <see cref="DateTimeKind.Local"/> (device time) – comparing those with <see cref="DateTime.UtcNow"/>
    /// would be off by the device's UTC offset.
    /// </summary>
    public static DateTime ToUtc(DateTime value) => value.Kind switch
    {
        DateTimeKind.Utc => value,
        DateTimeKind.Local => value.ToUniversalTime(),
        _ => DateTime.SpecifyKind(value, DateTimeKind.Utc),
    };

    public static DateTime? ToUtc(DateTime? value) => value is null ? null : ToUtc(value.Value);

    /// <summary>Wall-clock time in Berlin for a point in time.</summary>
    public static DateTime ToBerlin(DateTime value) => TimeZoneInfo.ConvertTimeFromUtc(ToUtc(value), Zone);

    public static DateTime Now => ToBerlin(DateTime.UtcNow);

    /// <summary>Interprets a date and time of day entered by the user as Berlin time and returns UTC.</summary>
    public static DateTime FromBerlin(DateTime date, TimeSpan timeOfDay)
    {
        var wallClock = DateTime.SpecifyKind(date.Date + timeOfDay, DateTimeKind.Unspecified);
        // Times skipped by the switch to summer time (02:00–02:59 on the last Sunday in March) do not exist.
        if (Zone.IsInvalidTime(wallClock)) wallClock = wallClock.AddHours(1);
        return TimeZoneInfo.ConvertTimeToUtc(wallClock, Zone);
    }
}
