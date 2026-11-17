using BlockerBetting.Models;
using System.Text.Json;
using Supabase.Gotrue;
using static Supabase.Postgrest.Constants;

namespace BlockerBetting.Services;

/// <summary>All data access for the betting platform. Coin-changing operations go through RPCs.</summary>
public class BettingService(Supabase.Client client)
{
    public Profile? CurrentProfile { get; private set; }

    /// <summary>Raised whenever <see cref="CurrentProfile"/> changes (e.g. coins after a bet).</summary>
    public event Action? ProfileChanged;

    /// <summary>Raised after a bet was resolved, so the winner ticker can refresh.</summary>
    public event Action? WinnersChanged;

    public Guid? CurrentUserId =>
        Guid.TryParse(client.Auth.CurrentUser?.Id, out var id) ? id : null;

    // ---------- Auth ----------

    public async Task SignInAsync(string email, string password)
    {
        await client.Auth.SignIn(email, password);
        await RefreshProfileAsync();
    }

    /// <returns>true if the user is signed in right away, false if an e-mail confirmation is pending.</returns>
    public async Task<bool> SignUpAsync(string email, string password, string displayName)
    {
        var state = await client.Auth.SignUpAsync(Constants.SignUpType.Email, email, password, new SignUpOptions
        {
            Data = new Dictionary<string, object> { ["display_name"] = displayName },
        });
        if (state.Session?.AccessToken is null) return false;
        await RefreshProfileAsync();
        return true;
    }

    public async Task SignOutAsync()
    {
        await client.Auth.SignOut();
        CurrentProfile = null;
        ProfileChanged?.Invoke();
    }

    // ---------- Profiles ----------

    public async Task RefreshProfileAsync()
    {
        var uid = CurrentUserId;
        CurrentProfile = uid is null
            ? null
            : await client.From<Profile>().Filter("id", Operator.Equals, uid.ToString()).Single();
        ProfileChanged?.Invoke();
    }

    public async Task UpdateDisplayNameAsync(string displayName)
    {
        var uid = CurrentUserId ?? throw new InvalidOperationException("Nicht angemeldet.");
        await client.From<Profile>()
            .Filter("id", Operator.Equals, uid.ToString())
            .Set(p => p.DisplayName, displayName)
            .Update();
        await RefreshProfileAsync();
    }

    public async Task<List<Profile>> GetLeaderboardAsync() =>
        (await client.From<Profile>().Order("coins", Ordering.Descending).Get()).Models;

    /// <summary>
    /// Winners of the most recently resolved bet (payout summed per player, highest first).
    /// Returns null when no bet has been resolved yet.
    /// </summary>
    public async Task<LatestWinners?> GetLatestWinnersAsync()
    {
        var latest = (await client.From<BetEvent>()
            .Filter("status", Operator.Equals, EventStatus.Resolved)
            .Order("resolved_at", Ordering.Descending, NullPosition.Last)
            .Limit(1)
            .Get()).Models.FirstOrDefault();
        if (latest is null) return null;

        var winningBets = (await client.From<Bet>()
            .Filter("event_id", Operator.Equals, latest.Id.ToString())
            .Filter("payout", Operator.GreaterThan, "0")
            .Get()).Models;
        var names = (await client.From<Profile>().Get()).Models.ToDictionary(p => p.Id, p => p.DisplayName);

        var winners = winningBets
            .GroupBy(b => b.UserId)
            .Select(g => new Winner(names.GetValueOrDefault(g.Key, "Unbekannt"), g.Sum(b => b.Payout ?? 0)))
            .OrderByDescending(w => w.Payout)
            .ToList();
        return new LatestWinners(latest, winners);
    }

    // ---------- Events ----------

    public async Task<List<EventOverview>> GetEventsAsync()
    {
        var events = (await client.From<BetEvent>().Order("created_at", Ordering.Descending).Get()).Models;
        var options = (await client.From<EventOption>().Order("sort_order", Ordering.Ascending).Get()).Models;
        var pools = (await client.From<OptionPool>().Get()).Models;

        return events.Select(e => new EventOverview(
                e,
                options.Where(o => o.EventId == e.Id).ToList(),
                pools.Where(p => p.EventId == e.Id).ToDictionary(p => p.OptionId)))
            .ToList();
    }

    public async Task<EventOverview?> GetEventAsync(Guid eventId)
    {
        var id = eventId.ToString();
        var ev = await client.From<BetEvent>().Filter("id", Operator.Equals, id).Single();
        if (ev is null) return null;
        var options = (await client.From<EventOption>().Filter("event_id", Operator.Equals, id)
            .Order("sort_order", Ordering.Ascending).Get()).Models;
        var pools = (await client.From<OptionPool>().Filter("event_id", Operator.Equals, id).Get()).Models;
        return new EventOverview(ev, options, pools.ToDictionary(p => p.OptionId));
    }

    public async Task<List<Bet>> GetMyBetsAsync(Guid? eventId = null)
    {
        var uid = CurrentUserId;
        if (uid is null) return [];
        var query = client.From<Bet>().Filter("user_id", Operator.Equals, uid.ToString());
        if (eventId is not null) query = query.Filter("event_id", Operator.Equals, eventId.ToString());
        return (await query.Order("created_at", Ordering.Descending).Get()).Models;
    }

    // ---------- RPCs ----------

    public async Task PlaceBetAsync(Guid optionId, long amount)
    {
        await client.Rpc("place_bet", new Dictionary<string, object>
        {
            ["p_option_id"] = optionId, ["p_amount"] = amount,
        });
        await RefreshProfileAsync();
    }

    public async Task<Guid> CreateEventAsync(string title, string? description, DateTime? closesAtUtc, IEnumerable<OptionInput> options)
    {
        var response = await client.Rpc("create_event", new Dictionary<string, object?>
        {
            ["p_title"] = title,
            ["p_description"] = description,
            ["p_closes_at"] = closesAtUtc,
            ["p_options"] = ToJson(options),
        });
        return Guid.Parse(response.Content!.Trim().Trim('"'));
    }

    public Task UpdateEventAsync(Guid eventId, string title, string? description, DateTime? closesAtUtc, IEnumerable<OptionInput> options) =>
        client.Rpc("update_event", new Dictionary<string, object?>
        {
            ["p_event_id"] = eventId,
            ["p_title"] = title,
            ["p_description"] = description,
            ["p_closes_at"] = closesAtUtc,
            ["p_options"] = ToJson(options),
        });

    private static List<Dictionary<string, object?>> ToJson(IEnumerable<OptionInput> options) =>
        options.Select(o => new Dictionary<string, object?>
        {
            ["id"] = o.Id, ["label"] = o.Label, ["odds"] = o.Odds,
        }).ToList();

    public Task LockEventAsync(Guid eventId) =>
        client.Rpc("lock_event", new Dictionary<string, object> { ["p_event_id"] = eventId });

    public Task ReopenEventAsync(Guid eventId) =>
        client.Rpc("reopen_event", new Dictionary<string, object> { ["p_event_id"] = eventId });

    public async Task ResolveEventAsync(Guid eventId, Guid winningOptionId)
    {
        await client.Rpc("resolve_event", new Dictionary<string, object>
        {
            ["p_event_id"] = eventId, ["p_winning_option_id"] = winningOptionId,
        });
        await RefreshProfileAsync();
        WinnersChanged?.Invoke();
    }

    public async Task CancelEventAsync(Guid eventId)
    {
        await client.Rpc("cancel_event", new Dictionary<string, object> { ["p_event_id"] = eventId });
        await RefreshProfileAsync();
    }

    /// <summary>
    /// Mirrors the database rule (can_resolve_event): admins always, the creator once the deadline has passed.
    /// The server enforces it; this only decides what the UI offers.
    /// </summary>
    public bool CanResolve(BetEvent ev) =>
        ev.Status is EventStatus.Open or EventStatus.Locked
        && (CurrentProfile?.IsAdmin == true
            || (ev.CreatedBy == CurrentUserId && ev.ClosesAt is { } closes && closes <= DateTime.UtcNow));

    public bool IsCreator(BetEvent ev) => ev.CreatedBy is not null && ev.CreatedBy == CurrentUserId;

    // ---------- Bet requests ----------

    /// <summary>Raised when requests were submitted, approved, rejected or withdrawn (e.g. for the admin badge).</summary>
    public event Action? RequestsChanged;

    public async Task SubmitBetRequestAsync(string title, string? description, DateTime closesAtUtc, IEnumerable<OptionInput> options)
    {
        await client.Rpc("submit_bet_request", new Dictionary<string, object?>
        {
            ["p_title"] = title,
            ["p_description"] = description,
            ["p_closes_at"] = closesAtUtc,
            ["p_options"] = ToJson(options),
        });
        RequestsChanged?.Invoke();
    }

    public async Task WithdrawBetRequestAsync(Guid requestId)
    {
        await client.Rpc("withdraw_bet_request", new Dictionary<string, object> { ["p_request_id"] = requestId });
        RequestsChanged?.Invoke();
    }

    public async Task<List<BetRequest>> GetMyBetRequestsAsync()
    {
        var uid = CurrentUserId;
        if (uid is null) return [];
        return (await client.From<BetRequest>()
            .Filter("requested_by", Operator.Equals, uid.ToString())
            .Order("created_at", Ordering.Descending)
            .Get()).Models;
    }

    /// <summary>All requests (admins only – RLS returns just the own ones for players).</summary>
    public async Task<List<BetRequest>> GetAllBetRequestsAsync() =>
        (await client.From<BetRequest>().Order("created_at", Ordering.Descending).Get()).Models;

    public async Task<BetRequest?> GetBetRequestAsync(Guid requestId) =>
        await client.From<BetRequest>().Filter("id", Operator.Equals, requestId.ToString()).Single();

    public async Task<int> CountPendingBetRequestsAsync() =>
        (await client.From<BetRequest>().Filter("status", Operator.Equals, RequestStatus.Pending).Get()).Models.Count;

    public async Task<Dictionary<Guid, string>> GetDisplayNamesAsync() =>
        (await client.From<Profile>().Get()).Models.ToDictionary(p => p.Id, p => p.DisplayName);

    public async Task<Guid> ApproveBetRequestAsync(Guid requestId, string title, string? description, DateTime closesAtUtc, IEnumerable<OptionInput> options)
    {
        var response = await client.Rpc("approve_bet_request", new Dictionary<string, object?>
        {
            ["p_request_id"] = requestId,
            ["p_title"] = title,
            ["p_description"] = description,
            ["p_closes_at"] = closesAtUtc,
            ["p_options"] = ToJson(options),
        });
        RequestsChanged?.Invoke();
        return Guid.Parse(response.Content!.Trim().Trim('"'));
    }

    public async Task RejectBetRequestAsync(Guid requestId, string? note)
    {
        await client.Rpc("reject_bet_request", new Dictionary<string, object?>
        {
            ["p_request_id"] = requestId, ["p_note"] = note,
        });
        RequestsChanged?.Invoke();
    }

    /// <summary>Turns Supabase/Postgrest errors into a readable message.</summary>
    public static string ErrorMessage(Exception ex)
    {
        var raw = ex.Message;
        try
        {
            using var doc = JsonDocument.Parse(raw);
            foreach (var key in new[] { "message", "msg", "error_description" })
                if (doc.RootElement.TryGetProperty(key, out var value) && value.ValueKind == JsonValueKind.String)
                    return value.GetString()!;
        }
        catch (JsonException)
        {
        }
        return raw;
    }
}
