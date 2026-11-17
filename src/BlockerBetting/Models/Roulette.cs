using System.Text.Json.Serialization;
using BlockerBetting.Services;
using Supabase.Postgrest.Attributes;
using Supabase.Postgrest.Models;

namespace BlockerBetting.Models;

/// <summary>
/// European roulette rules (single zero). The server (play_roulette) draws the number and settles
/// the coins; these rules are only used to display odds and highlight winning bets.
/// </summary>
public static class Roulette
{
    /// <summary>Pocket order on a European wheel, clockwise starting at 0.</summary>
    public static readonly int[] WheelOrder =
    [
        0, 32, 15, 19, 4, 21, 2, 25, 17, 34, 6, 27, 13, 36, 11, 30, 8, 23, 10,
        5, 24, 16, 33, 1, 20, 14, 31, 9, 22, 18, 29, 7, 28, 12, 35, 3, 26,
    ];

    private static readonly HashSet<int> Red = [1, 3, 5, 7, 9, 12, 14, 16, 18, 19, 21, 23, 25, 27, 30, 32, 34, 36];

    public static bool IsRed(int n) => Red.Contains(n);

    /// <summary>"red", "black" or "green".</summary>
    public static string ColorOf(int n) => n == 0 ? "green" : IsRed(n) ? "red" : "black";

    public static string ColorName(int n) => n == 0 ? "Grün" : IsRed(n) ? "Rot" : "Schwarz";

    /// <summary>Payout factor including the stake (36, 3, 2) or 0 when the bet loses. Mirrors _roulette_factor in SQL.</summary>
    public static int Factor(string type, int? value, int result) => type switch
    {
        "straight" => value == result ? 36 : 0,
        "dozen" => value is { } d && result >= (d - 1) * 12 + 1 && result <= d * 12 ? 3 : 0,
        "column" => value is { } c && result > 0 && (result - 1) % 3 == c - 1 ? 3 : 0,
        "red" => IsRed(result) ? 2 : 0,
        "black" => result > 0 && !IsRed(result) ? 2 : 0,
        "odd" => result > 0 && result % 2 == 1 ? 2 : 0,
        "even" => result > 0 && result % 2 == 0 ? 2 : 0,
        "low" => result is >= 1 and <= 18 ? 2 : 0,
        "high" => result is >= 19 and <= 36 ? 2 : 0,
        _ => 0,
    };

    public static string Label(string type, int? value) => type switch
    {
        "straight" => $"Zahl {value}",
        "dozen" => value switch { 1 => "1–12", 2 => "13–24", _ => "25–36" },
        "column" => $"Kolonne {value}",
        "red" => "Rot",
        "black" => "Schwarz",
        "odd" => "Ungerade",
        "even" => "Gerade",
        "low" => "1–18",
        "high" => "19–36",
        _ => type,
    };

    public static string Key(string type, int? value) => value is null ? type : $"{type}:{value}";
}

/// <summary>One chip stack on the table.</summary>
public record RouletteBet(string Type, int? Value, long Amount)
{
    [JsonIgnore] public string Key => Roulette.Key(Type, Value);
}

public record SpinResult(int Result, long TotalStake, long Payout, long Coins)
{
    public long Net => Payout - TotalStake;
}

[Table("game_rounds")]
public class GameRound : BaseModel
{
    [PrimaryKey("id")] public Guid Id { get; set; }
    [Column("user_id")] public Guid UserId { get; set; }
    [Column("game")] public string Game { get; set; } = "";
    [Column("total_stake")] public long TotalStake { get; set; }
    [Column("result")] public int Result { get; set; }
    [Column("payout")] public long Payout { get; set; }
    [Column("created_at")] public DateTime CreatedAt { get; set => field = BerlinTime.ToUtc(value); }
}
