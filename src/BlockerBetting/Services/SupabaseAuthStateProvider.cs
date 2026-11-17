using System.Security.Claims;
using Microsoft.AspNetCore.Components.Authorization;
using Supabase.Gotrue;
using Supabase.Gotrue.Interfaces;
using static Supabase.Gotrue.Constants;

namespace BlockerBetting.Services;

/// <summary>Bridges Supabase auth state into Blazor's authorization system.</summary>
public class SupabaseAuthStateProvider : AuthenticationStateProvider
{
    private readonly Supabase.Client _client;

    public SupabaseAuthStateProvider(Supabase.Client client)
    {
        _client = client;
        _client.Auth.AddStateChangedListener(OnAuthStateChanged);
    }

    private void OnAuthStateChanged(IGotrueClient<User, Session> sender, AuthState state)
    {
        if (state is AuthState.SignedIn or AuthState.SignedOut or AuthState.UserUpdated or AuthState.TokenRefreshed)
            NotifyAuthenticationStateChanged(GetAuthenticationStateAsync());
    }

    public override Task<AuthenticationState> GetAuthenticationStateAsync()
    {
        var user = _client.Auth.CurrentUser;
        if (user?.Id is null || _client.Auth.CurrentSession is null)
            return Task.FromResult(new AuthenticationState(new ClaimsPrincipal(new ClaimsIdentity())));

        var claims = new List<Claim>
        {
            new(ClaimTypes.NameIdentifier, user.Id),
            new(ClaimTypes.Email, user.Email ?? ""),
            new(ClaimTypes.Name, user.Email ?? user.Id),
        };
        var identity = new ClaimsIdentity(claims, "supabase");
        return Task.FromResult(new AuthenticationState(new ClaimsPrincipal(identity)));
    }
}
