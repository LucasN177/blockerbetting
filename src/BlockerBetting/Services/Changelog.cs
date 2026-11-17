using System.Net;
using System.Text.RegularExpressions;

namespace BlockerBetting.Services;

/// <summary>
/// Parses the repository CHANGELOG.md (embedded into the assembly) into releases.
/// Supported: "## version – date", "### section", "- item", other lines as notes, **bold** and `code`.
/// </summary>
public static partial class Changelog
{
    public record Section(string Title, List<string> Items);

    public record Release(string Version, string? Date, List<Section> Sections, List<string> Notes);

    /// <summary>The changelog shipped with this build.</summary>
    public static List<Release> Load()
    {
        using var stream = typeof(Changelog).Assembly.GetManifestResourceStream("CHANGELOG.md")
                           ?? throw new InvalidOperationException("CHANGELOG.md ist nicht in die App eingebettet.");
        using var reader = new StreamReader(stream);
        return Parse(reader.ReadToEnd());
    }

    public static List<Release> Parse(string markdown)
    {
        var releases = new List<Release>();
        Release? current = null;
        Section? section = null;

        foreach (var raw in markdown.Replace("\r\n", "\n").Split('\n'))
        {
            var line = raw.Trim();
            if (line.StartsWith("## "))
            {
                var parts = line[3..].Split(['–', '—'], 2, StringSplitOptions.TrimEntries);
                current = new Release(parts[0], parts.Length > 1 ? parts[1] : null, [], []);
                releases.Add(current);
                section = null;
            }
            else if (current is null || line.Length == 0)
            {
                // Intro text before the first release and blank lines are skipped.
            }
            else if (line.StartsWith("### "))
            {
                section = new Section(line[4..].Trim(), []);
                current.Sections.Add(section);
            }
            else if (line.StartsWith("- ") || line.StartsWith("* "))
            {
                if (section is null)
                {
                    section = new Section("", []);
                    current.Sections.Add(section);
                }
                section.Items.Add(Inline(line[2..]));
            }
            else
            {
                current.Notes.Add(Inline(line));
                section = null;
            }
        }
        return releases;
    }

    /// <summary>HTML-encodes the text first, then applies **bold** and `code` – so the result is safe markup.</summary>
    private static string Inline(string text)
    {
        var html = WebUtility.HtmlEncode(text);
        html = Bold().Replace(html, "<b>$1</b>");
        return Code().Replace(html, "<code>$1</code>");
    }

    [GeneratedRegex(@"\*\*(.+?)\*\*")]
    private static partial Regex Bold();

    [GeneratedRegex(@"`(.+?)`")]
    private static partial Regex Code();
}
