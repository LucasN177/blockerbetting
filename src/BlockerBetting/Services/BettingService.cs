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

    public async Task<Guid> CreateEventAsync(string title, string? description, DateTime? closesAtUtc, IEnumerable<string> options)
    {
        var response = await client.Rpc("create_event", new Dictionary<string, object?>
        {
            ["p_title"] = title,
            ["p_description"] = description,
            ["p_closes_at"] = closesAtUtc,
            ["p_options"] = options.ToArray(),
        });
        return Guid.Parse(response.Content!.Trim().Trim('"'));
    }

    public Task LockEventAsync(Guid eventId) =>
        client.Rpc("lock_event", new Dictionary<string, object> { ["p_event_id"] = eventId });

    public async Task ResolveEventAsync(Guid eventId, Guid winningOptionId)
    {
        await client.Rpc("resolve_event", new Dictionary<string, object>
        {
            ["p_event_id"] = eventId, ["p_winning_option_id"] = winningOptionId,
        });
        await RefreshProfileAsync();
    }

    public async Task CancelEventAsync(Guid eventId)
    {
        await client.Rpc("cancel_event", new Dictionary<string, object> { ["p_event_id"] = eventId });
        await RefreshProfileAsync();
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
