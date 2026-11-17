using Microsoft.JSInterop;
using MudBlazor;

namespace BlockerBetting.Services;

/// <summary>App-wide theme and light/dark mode (persisted in localStorage, defaults to the OS setting).</summary>
public class ThemeService(IJSRuntime js)
{
    private const string StorageKey = "blockerbetting.darkMode";

    private IJSInProcessRuntime Js => (IJSInProcessRuntime)js;

    public event Action? Changed;

    public bool IsDarkMode { get; private set; }

    public void Initialize()
    {
        var stored = Js.Invoke<string?>("localStorage.getItem", StorageKey);
        IsDarkMode = stored is not null ? stored == "true" : Js.Invoke<bool>("bb.prefersDark");
    }

    public void Toggle()
    {
        IsDarkMode = !IsDarkMode;
        Js.InvokeVoid("localStorage.setItem", StorageKey, IsDarkMode ? "true" : "false");
        Changed?.Invoke();
    }

    private static readonly string[] FontStack = ["Inter", "system-ui", "-apple-system", "Segoe UI", "Roboto", "sans-serif"];

    public MudTheme Theme { get; } = new()
    {
        PaletteLight = new PaletteLight
        {
            Primary = "#4f46e5",
            PrimaryDarken = "#4338ca",
            PrimaryLighten = "#6366f1",
            Secondary = "#f59e0b",
            Tertiary = "#0ea5e9",
            Success = "#10b981",
            Warning = "#f59e0b",
            Error = "#ef4444",
            Info = "#3b82f6",
            Background = "#f5f6fb",
            BackgroundGray = "#eef0f7",
            Surface = "#ffffff",
            AppbarBackground = "rgba(245,246,251,0.78)",
            AppbarText = "#0f172a",
            DrawerBackground = "#f5f6fb",
            DrawerText = "#334155",
            DrawerIcon = "#64748b",
            TextPrimary = "#0f172a",
            TextSecondary = "#64748b",
            ActionDefault = "#64748b",
            LinesDefault = "#e6e8f0",
            TableLines = "#eef0f6",
            Divider = "#e6e8f0",
        },
        PaletteDark = new PaletteDark
        {
            Primary = "#818cf8",
            PrimaryDarken = "#6366f1",
            PrimaryLighten = "#a5b4fc",
            Secondary = "#fbbf24",
            Tertiary = "#38bdf8",
            Success = "#34d399",
            Warning = "#fbbf24",
            Error = "#f87171",
            Info = "#60a5fa",
            Background = "#0a0f1e",
            BackgroundGray = "#0f172a",
            Surface = "#111a2e",
            AppbarBackground = "rgba(10,15,30,0.72)",
            AppbarText = "#e2e8f0",
            DrawerBackground = "#0a0f1e",
            DrawerText = "#cbd5e1",
            DrawerIcon = "#94a3b8",
            TextPrimary = "#e2e8f0",
            TextSecondary = "#94a3b8",
            ActionDefault = "#94a3b8",
            LinesDefault = "rgba(148,163,184,0.14)",
            TableLines = "rgba(148,163,184,0.10)",
            Divider = "rgba(148,163,184,0.14)",
        },
        LayoutProperties = new LayoutProperties
        {
            DefaultBorderRadius = "14px",
            DrawerWidthLeft = "264px",
            AppbarHeight = "68px",
        },
        Typography = new Typography
        {
            Default = new DefaultTypography { FontFamily = FontStack, LetterSpacing = "-0.005em" },
            H3 = new H3Typography { FontFamily = FontStack, FontWeight = "800", LetterSpacing = "-0.03em" },
            H4 = new H4Typography { FontFamily = FontStack, FontWeight = "800", LetterSpacing = "-0.025em", FontSize = "2rem" },
            H5 = new H5Typography { FontFamily = FontStack, FontWeight = "700", LetterSpacing = "-0.02em" },
            H6 = new H6Typography { FontFamily = FontStack, FontWeight = "700", LetterSpacing = "-0.015em" },
            Subtitle1 = new Subtitle1Typography { FontFamily = FontStack, FontWeight = "600" },
            Subtitle2 = new Subtitle2Typography { FontFamily = FontStack, FontWeight = "600" },
            Button = new ButtonTypography { FontFamily = FontStack, FontWeight = "600", TextTransform = "none", LetterSpacing = "0" },
            Caption = new CaptionTypography { FontFamily = FontStack, LetterSpacing = "0" },
        },
    };
}
