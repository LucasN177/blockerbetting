using System.Text.Json.Serialization;
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
    [Column("created_at", ignoreOnInsert: true, ignoreOnUpdate: true)] public DateTime CreatedAt { get; set; }
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
    [Column("closes_at")] public DateTime? ClosesAt { get; set; }
    [Column("winning_option_id")] public Guid? WinningOptionId { get; set; }
    [Column("created_by")] public Guid? CreatedBy { get; set; }
    [Column("created_at")] public DateTime CreatedAt { get; set; }
    [Column("resolved_at")] public DateTime? ResolvedAt { get; set; }

    [JsonIgnore]
    public bool AcceptsBets => Status == EventStatus.Open && (ClosesAt is null || ClosesAt > DateTime.UtcNow);
}

[Table("event_options")]
public class EventOption : BaseModel
{
    [PrimaryKey("id")] public Guid Id { get; set; }
    [Column("event_id")] public Guid EventId { get; set; }
    [Column("label")] public string Label { get; set; } = "";
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
    [Column("payout")] public long? Payout { get; set; }
    [Column("created_at")] public DateTime CreatedAt { get; set; }
}

/// <summary>An event together with its options and current pools.</summary>
public record EventOverview(BetEvent Event, IReadOnlyList<EventOption> Options, IReadOnlyDictionary<Guid, OptionPool> Pools)
{
    public long TotalPool => Pools.Values.Sum(p => p.TotalAmount);

    public long PoolFor(Guid optionId) => Pools.TryGetValue(optionId, out var p) ? p.TotalAmount : 0;

    /// <summary>Current pari-mutuel multiplier for an option (payout per coin), null if nobody bet on it yet.</summary>
    public double? OddsFor(Guid optionId)
    {
        var pool = PoolFor(optionId);
        return pool == 0 ? null : (double)TotalPool / pool;
    }
}
