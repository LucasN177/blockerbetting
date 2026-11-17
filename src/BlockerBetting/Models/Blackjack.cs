using System.Text.Json.Serialization;

namespace BlockerBetting.Models;

/// <summary>Visible state of a blackjack hand as returned by the blackjack_* RPCs (the deck never leaves the server).</summary>
public record BlackjackState(
    [property: JsonPropertyName("id")] Guid Id,
    [property: JsonPropertyName("status")] string Status,
    [property: JsonPropertyName("bet")] long Bet,
    [property: JsonPropertyName("doubled")] bool Doubled,
    [property: JsonPropertyName("player")] int[] Player,
    [property: JsonPropertyName("player_total")] int PlayerTotal,
    [property: JsonPropertyName("dealer")] int[] Dealer,
    [property: JsonPropertyName("dealer_total")] int DealerTotal,
    [property: JsonPropertyName("outcome")] string? Outcome,
    [property: JsonPropertyName("payout")] long Payout,
    [property: JsonPropertyName("can_double")] bool CanDouble,
    [property: JsonPropertyName("coins")] long Coins)
{
    public bool IsPlaying => Status == "playing";

    public long Net => Payout - Bet;
}

public record BlackjackHistoryEntry(
    [property: JsonPropertyName("finished_at")] DateTime FinishedAt,
    [property: JsonPropertyName("bet")] long Bet,
    [property: JsonPropertyName("outcome")] string Outcome,
    [property: JsonPropertyName("payout")] long Payout,
    [property: JsonPropertyName("player_total")] int PlayerTotal,
    [property: JsonPropertyName("dealer_total")] int DealerTotal);

/// <summary>Card codes 0–51: rank = code % 13 (0 = Ass … 12 = König), suit = code / 13. -1 = face down.</summary>
public static class Cards
{
    private static readonly string[] Ranks = ["A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "B", "D", "K"];
    private static readonly string[] Suits = ["♠", "♥", "♦", "♣"];

    public static string Rank(int code) => Ranks[code % 13];

    public static string Suit(int code) => Suits[code / 13 % 4];

    public static bool IsRed(int code) => code / 13 % 4 is 1 or 2;

    public static string Name(int code) => code < 0 ? "verdeckte Karte" : $"{Rank(code)} {Suit(code)}";

    /// <summary>Same rules as _bj_total in SQL: aces count 11 while that does not bust.</summary>
    public static int Total(IEnumerable<int> cards)
    {
        int total = 0, aces = 0;
        foreach (var c in cards.Where(c => c >= 0))
        {
            var r = c % 13;
            if (r == 0) { aces++; total += 1; }
            else total += r >= 9 ? 10 : r + 1;
        }
        return aces > 0 && total + 10 <= 21 ? total + 10 : total;
    }

    /// <summary>"soft": an ace currently counts as 11.</summary>
    public static bool IsSoft(IEnumerable<int> cards)
    {
        var list = cards.Where(c => c >= 0).ToList();
        var hard = list.Sum(c => c % 13 == 0 ? 1 : c % 13 >= 9 ? 10 : c % 13 + 1);
        return list.Any(c => c % 13 == 0) && hard + 10 <= 21;
    }
}
