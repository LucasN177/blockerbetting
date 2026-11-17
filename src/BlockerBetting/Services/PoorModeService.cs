using Microsoft.JSInterop;

namespace BlockerBetting.Services;

/// <summary>
/// "Poor Mode" for the games: while enabled, a coin spawns somewhere on the screen every
/// <see cref="Interval"/> and can be collected (server-side rate limit in claim_poor_mode_coin).
/// The on/off setting is stored per device.
/// </summary>
public class PoorModeService(IJSRuntime js)
{
    private const string StorageKey = "blockerbetting.poorMode";

    public static readonly TimeSpan Interval = TimeSpan.FromSeconds(60);

    private IJSInProcessRuntime Js => (IJSInProcessRuntime)js;

    public event Action? Changed;

    public bool Enabled { get; private set; }

    /// <summary>When the next coin appears (UTC). Set when the mode is switched on or a coin was collected.</summary>
    public DateTime NextSpawnAt { get; private set; } = DateTime.UtcNow + Interval;

    public void Initialize() => Enabled = Js.Invoke<string?>("localStorage.getItem", StorageKey) == "true";

    public void Toggle()
    {
        Enabled = !Enabled;
        Js.InvokeVoid("localStorage.setItem", StorageKey, Enabled ? "true" : "false");
        if (Enabled) ScheduleNext();
        Changed?.Invoke();
    }

    public void ScheduleNext()
    {
        NextSpawnAt = DateTime.UtcNow + Interval;
        Changed?.Invoke();
    }
}
