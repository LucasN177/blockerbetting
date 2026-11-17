using Microsoft.JSInterop;

namespace BlockerBetting.Services;

/// <summary>Browser push notifications: subscribe this device and register it in Supabase.</summary>
public class PushService(IJSRuntime js, Supabase.Client client, IConfiguration config)
{
    public record PushState(bool Supported, bool IsIos, bool IsStandalone, string Permission, bool Subscribed, string UserAgent)
    {
        /// <summary>iPhone/iPad only allow push for apps added to the home screen.</summary>
        public bool NeedsHomeScreen => IsIos && !IsStandalone;

        public bool Blocked => Permission == "denied";
    }

    private record SubscriptionDto(string Endpoint, string P256dh, string Auth);

    private string? VapidPublicKey => config["Push:VapidPublicKey"];

    /// <summary>False when the deployment has no VAPID key – push UI is hidden then.</summary>
    public bool IsConfigured => !string.IsNullOrWhiteSpace(VapidPublicKey);

    public async Task<PushState> GetStateAsync() => await js.InvokeAsync<PushState>("bbPush.state");

    /// <summary>Asks for permission, subscribes this browser and stores it for the current user.</summary>
    /// <returns>false if the user did not grant permission.</returns>
    public async Task<bool> EnableAsync()
    {
        if (!IsConfigured) throw new InvalidOperationException("Push ist für diese Installation nicht eingerichtet.");
        var subscription = await js.InvokeAsync<SubscriptionDto?>("bbPush.subscribe", VapidPublicKey);
        if (subscription is null) return false;
        await SaveAsync(subscription);
        return true;
    }

    /// <summary>Unsubscribes this browser and removes it from the database.</summary>
    public async Task DisableAsync()
    {
        var endpoint = await js.InvokeAsync<string?>("bbPush.unsubscribe");
        if (endpoint is not null) await DeleteAsync(endpoint);
    }

    /// <summary>
    /// Re-registers an existing browser subscription for the signed-in user (e.g. after login or when
    /// the browser rotated the subscription). Does nothing without permission.
    /// </summary>
    public async Task SyncAsync()
    {
        if (!IsConfigured || client.Auth.CurrentUser is null) return;
        var state = await GetStateAsync();
        if (!state.Supported || state.Permission != "granted") return;
        var subscription = await js.InvokeAsync<SubscriptionDto?>("bbPush.current");
        if (subscription is not null) await SaveAsync(subscription);
    }

    /// <summary>On sign-out: stop sending this user's notifications to this device (keeps the browser permission).</summary>
    public async Task ForgetDeviceAsync()
    {
        if (!IsConfigured) return;
        var subscription = await js.InvokeAsync<SubscriptionDto?>("bbPush.current");
        if (subscription is not null) await DeleteAsync(subscription.Endpoint);
    }

    private async Task SaveAsync(SubscriptionDto subscription)
    {
        var state = await GetStateAsync();
        await client.Rpc("save_push_subscription", new Dictionary<string, object?>
        {
            ["p_endpoint"] = subscription.Endpoint,
            ["p_p256dh"] = subscription.P256dh,
            ["p_auth"] = subscription.Auth,
            ["p_user_agent"] = state.UserAgent,
        });
    }

    private Task DeleteAsync(string endpoint) =>
        client.Rpc("delete_push_subscription", new Dictionary<string, object> { ["p_endpoint"] = endpoint });
}
