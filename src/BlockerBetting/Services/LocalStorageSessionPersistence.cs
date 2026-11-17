using Microsoft.JSInterop;
using System.Text.Json;
using Supabase.Gotrue;
using Supabase.Gotrue.Interfaces;

namespace BlockerBetting.Services;

/// <summary>Persists the Supabase auth session in the browser's localStorage.</summary>
public class LocalStorageSessionPersistence(IJSRuntime js) : IGotrueSessionPersistence<Session>
{
    private const string Key = "blockerbetting.session";

    private IJSInProcessRuntime Js => (IJSInProcessRuntime)js;

    public void SaveSession(Session session) =>
        Js.InvokeVoid("localStorage.setItem", Key, JsonSerializer.Serialize(session));

    public void DestroySession() => Js.InvokeVoid("localStorage.removeItem", Key);

    public Session? LoadSession()
    {
        var json = Js.Invoke<string?>("localStorage.getItem", Key);
        if (string.IsNullOrEmpty(json)) return null;
        try { return JsonSerializer.Deserialize<Session>(json); }
        catch (JsonException) { DestroySession(); return null; }
    }

    public Task SaveSessionAsync(Session session, CancellationToken cancellationToken = default)
    {
        SaveSession(session);
        return Task.CompletedTask;
    }

    public Task DestroySessionAsync(CancellationToken cancellationToken = default)
    {
        DestroySession();
        return Task.CompletedTask;
    }

    public Task<Session?> LoadSessionAsync(CancellationToken cancellationToken = default) =>
        Task.FromResult(LoadSession());
}
