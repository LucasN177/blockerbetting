using System.Text.Json.Serialization;
using BlockerBetting.Services;
using Supabase.Postgrest.Attributes;
using Supabase.Postgrest.Models;

namespace BlockerBetting.Models;

[Table("profiles")]
public class Profile : BaseModel
{
    [PrimaryKey("id", true)] public Guid Id { get; set; }
    [Column("display_name")] public string DisplayName { get; set; } = "";
    [Column("coins", ignoreOnInsert: true, ignoreOnUpdate: true)] public long Coins { get; set; }
    [Column("is_admin", ignoreOnInsert: true, ignoreOnUpdate: true)] public bool IsAdmin { get; set; }
    [Column("created_at", ignoreOnInsert: true, ignoreOnUpdate: true)] public DateTime CreatedAt { get; set => field = BerlinTime.ToUtc(value); }
}

public static class EventStatus
{
    public const string Open = "open";
    public const string Locked = "locked";
    public const string Resolved = "resolved";
    public const string Cancelled = "cancelled";
}

[Table("events")]
public class BetEvent : BaseModel
{
    [PrimaryKey("id")] public Guid Id { get; set; }
    [Column("title")] public string Title { get; set; } = "";
    [Column("description")] public string? Description { get; set; }
    [Column("status")] public string Status { get; set; } = EventStatus.Open;
    [Column("closes_at")] public DateTime? ClosesAt { get; set => field = BerlinTime.ToUtc(value); }
    [Column("winning_option_id")] public Guid? WinningOptionId { get; set; }
    [Column("created_by")] public Guid? CreatedBy { get; set; }
    [Column("created_at")] public DateTime CreatedAt { get; set => field = BerlinTime.ToUtc(value); }
    [Column("resolved_at")] public DateTime? ResolvedAt { get; set => field = BerlinTime.ToUtc(value); }

    [JsonIgnore]
    public bool AcceptsBets => Status == EventStatus.Open && (ClosesAt is null || ClosesAt > DateTime.UtcNow);
}

[Table("event_options")]
public class EventOption : BaseModel
{
    [PrimaryKey("id")] public Guid Id { get; set; }
    [Column("event_id")] public Guid EventId { get; set; }
    [Column("label")] public string Label { get; set; } = "";
    [Column("odds")] public decimal Odds { get; set; }
    [Column("sort_order")] public int SortOrder { get; set; }
}

[Table("event_option_pools")]
public class OptionPool : BaseModel
{
    [PrimaryKey("option_id")] public Guid OptionId { get; set; }
    [Column("event_id")] public Guid EventId { get; set; }
    [Column("total_amount")] public long TotalAmount { get; set; }
    [Column("bet_count")] public int BetCount { get; set; }
}

[Table("bets")]
public class Bet : BaseModel
{
    [PrimaryKey("id")] public Guid Id { get; set; }
    [Column("user_id")] public Guid UserId { get; set; }
    [Column("event_id")] public Guid EventId { get; set; }
    [Column("option_id")] public Guid OptionId { get; set; }
    [Column("amount")] public long Amount { get; set; }
    [Column("odds")] public decimal Odds { get; set; }
    [Column("payout")] public long? Payout { get; set; }
    [Column("created_at")] public DateTime CreatedAt { get; set => field = BerlinTime.ToUtc(value); }

    /// <summary>Payout if this bet wins (fixed odds stored at bet time).</summary>
    [JsonIgnore]
    public long PotentialPayout => Payouts.For(Amount, Odds);
}

public static class Payouts
{
    /// <summary>Same rounding as the database: floor(amount × odds).</summary>
    public static long For(long amount, decimal odds) => (long)Math.Floor(amount * odds);
}

public static class RequestStatus
{
    public const string Pending = "pending";
    public const string Approved = "approved";
    public const string Rejected = "rejected";
    public const string Withdrawn = "withdrawn";
}

/// <summary>One proposed option inside a bet request (stored as jsonb).</summary>
public class RequestOption
{
    [JsonPropertyName("label")] public string Label { get; set; } = "";
    [JsonPropertyName("odds")] public decimal Odds { get; set; }
}

/// <summary>A bet proposed by a player, reviewed by an admin.</summary>
[Table("bet_requests")]
public class BetRequest : BaseModel
{
    [PrimaryKey("id")] public Guid Id { get; set; }
    [Column("requested_by")] public Guid RequestedBy { get; set; }
    [Column("title")] public string Title { get; set; } = "";
    [Column("description")] public string? Description { get; set; }
    [Column("closes_at")] public DateTime ClosesAt { get; set => field = BerlinTime.ToUtc(value); }
    [Column("options")] public List<RequestOption> Options { get; set; } = [];
    [Column("status")] public string Status { get; set; } = RequestStatus.Pending;
    [Column("admin_note")] public string? AdminNote { get; set; }
    [Column("event_id")] public Guid? EventId { get; set; }
    [Column("reviewed_by")] public Guid? ReviewedBy { get; set; }
    [Column("reviewed_at")] public DateTime? ReviewedAt { get; set => field = BerlinTime.ToUtc(value); }
    [Column("created_at")] public DateTime CreatedAt { get; set => field = BerlinTime.ToUtc(value); }
}

[Table("chat_messages")]
public class ChatMessage : BaseModel
{
    [PrimaryKey("id")] public Guid Id { get; set; }
    [Column("user_id")] public Guid UserId { get; set; }
    [Column("body")] public string Body { get; set; } = "";
    [Column("created_at")] public DateTime CreatedAt { get; set => field = BerlinTime.ToUtc(value); }
}

/// <summary>A chat message ready for display: author name and whether it is the own message.</summary>
public record ChatEntry(ChatMessage Message, string AuthorName, bool IsOwn);

public record Winner(string DisplayName, long Payout);

/// <summary>The most recently resolved bet and its winners.</summary>
public record LatestWinners(BetEvent Event, IReadOnlyList<Winner> Winners);

/// <summary>Option data sent to create_event / update_event.</summary>
public record OptionInput(Guid? Id, string Label, decimal Odds);

/// <summary>An event together with its options and current stake volume.</summary>
public record EventOverview(BetEvent Event, IReadOnlyList<EventOption> Options, IReadOnlyDictionary<Guid, OptionPool> Pools, string? CreatorName = null)
{
    public long TotalStake => Pools.Values.Sum(p => p.TotalAmount);

    public int TotalBets => Pools.Values.Sum(p => p.BetCount);

    public long StakeFor(Guid optionId) => Pools.TryGetValue(optionId, out var p) ? p.TotalAmount : 0;

    public int BetsFor(Guid optionId) => Pools.TryGetValue(optionId, out var p) ? p.BetCount : 0;
}
