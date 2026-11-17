using BlockerBetting;
using BlockerBetting.Services;
using Microsoft.AspNetCore.Components.Authorization;
using Microsoft.AspNetCore.Components.Web;
using Microsoft.AspNetCore.Components.WebAssembly.Hosting;
using MudBlazor.Services;

var builder = WebAssemblyHostBuilder.CreateDefault(args);
builder.RootComponents.Add<App>("#app");
builder.RootComponents.Add<HeadOutlet>("head::after");

var supabaseUrl = builder.Configuration["Supabase:Url"];
var supabaseKey = builder.Configuration["Supabase:Key"];
if (string.IsNullOrWhiteSpace(supabaseUrl) || string.IsNullOrWhiteSpace(supabaseKey))
    throw new InvalidOperationException(
        "Supabase ist nicht konfiguriert. Bitte 'Supabase:Url' und 'Supabase:Key' in wwwroot/appsettings(.Development).json setzen.");

builder.Services.AddMudServices();
builder.Services.AddSingleton<LocalStorageSessionPersistence>();
builder.Services.AddSingleton(sp => new Supabase.Client(supabaseUrl, supabaseKey, new Supabase.SupabaseOptions
{
    AutoConnectRealtime = false,
    AutoRefreshToken = true,
    SessionHandler = sp.GetRequiredService<LocalStorageSessionPersistence>(),
}));
builder.Services.AddSingleton<BettingService>();
builder.Services.AddAuthorizationCore();
builder.Services.AddCascadingAuthenticationState();
builder.Services.AddSingleton<SupabaseAuthStateProvider>();
builder.Services.AddSingleton<AuthenticationStateProvider>(sp => sp.GetRequiredService<SupabaseAuthStateProvider>());

var host = builder.Build();

// Restore a persisted session (refreshes the token if needed).
var supabase = host.Services.GetRequiredService<Supabase.Client>();
try { await supabase.InitializeAsync(); }
catch (Exception ex) { Console.WriteLine($"Supabase-Session konnte nicht wiederhergestellt werden: {ex.Message}"); }

// Subscribe the auth provider before anything signs in/out, then load the profile.
host.Services.GetRequiredService<SupabaseAuthStateProvider>();
try { await host.Services.GetRequiredService<BettingService>().RefreshProfileAsync(); }
catch (Exception ex) { Console.WriteLine($"Profil konnte nicht geladen werden: {ex.Message}"); }

await host.RunAsync();
