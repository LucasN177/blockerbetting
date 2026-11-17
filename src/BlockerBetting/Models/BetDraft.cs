namespace BlockerBetting.Models;

/// <summary>Editable state of a bet in a form (admin create/edit, player request, admin review).</summary>
public class BetDraft
{
    public string Title { get; set; } = "";
    public string? Description { get; set; }
    public DateTime? ClosesDate { get; set; }
    public TimeSpan? ClosesTime { get; set; } = new(18, 0, 0);
    public List<DraftOption> Options { get; set; } = [];

    public class DraftOption
    {
        public Guid? Id { get; init; }
        public string Label { get; set; } = "";
        public decimal Odds { get; set; } = 2.00m;
        /// <summary>Bets already placed on this option (it cannot be removed then).</summary>
        public int BetCount { get; init; }
    }

    public static BetDraft NewYesNo() => new()
    {
        Options = [new() { Label = "Ja", Odds = 1.80m }, new() { Label = "Nein", Odds = 2.00m }],
    };

    public static BetDraft From(EventOverview ev)
    {
        var draft = new BetDraft { Title = ev.Event.Title, Description = ev.Event.Description };
        draft.SetDeadline(ev.Event.ClosesAt);
        draft.Options = ev.Options.Select(o => new DraftOption
        {
            Id = o.Id, Label = o.Label, Odds = o.Odds, BetCount = ev.BetsFor(o.Id),
        }).ToList();
        return draft;
    }

    public static BetDraft From(BetRequest request)
    {
        var draft = new BetDraft { Title = request.Title, Description = request.Description };
        draft.SetDeadline(request.ClosesAt);
        draft.Options = request.Options.Select(o => new DraftOption { Label = o.Label, Odds = o.Odds }).ToList();
        return draft;
    }

    private void SetDeadline(DateTime? utc)
    {
        if (utc is null) return;
        var local = utc.Value.ToLocalTime();
        ClosesDate = local.Date;
        ClosesTime = local.TimeOfDay;
    }

    public DateTime? ClosesAtUtc => ClosesDate is { } date
        ? DateTime.SpecifyKind(date.Date + (ClosesTime ?? TimeSpan.Zero), DateTimeKind.Local).ToUniversalTime()
        : null;

    public List<OptionInput> ToOptionInputs() => Options
        .Select(o => new OptionInput(o.Id, o.Label.Trim(), Math.Round(o.Odds, 2)))
        .Where(o => o.Label.Length > 0)
        .ToList();

    /// <summary>Returns a user-facing error, or null when the draft is valid.</summary>
    public string? Validate(bool requireDeadline, bool deadlineInFuture)
    {
        if (string.IsNullOrWhiteSpace(Title) || Title.Trim().Length < 3) return "Bitte einen Titel mit mindestens 3 Zeichen angeben.";
        var options = ToOptionInputs();
        if (options.Count < 2 || options.Select(o => o.Label).Distinct(StringComparer.OrdinalIgnoreCase).Count() != options.Count)
            return "Bitte mindestens zwei Optionen mit unterschiedlichen Bezeichnungen angeben.";
        if (options.Any(o => o.Odds < 1.01m)) return "Quoten müssen mindestens 1,01 sein.";
        if (requireDeadline && ClosesAtUtc is null) return "Bitte einen Wettschluss angeben.";
        if (deadlineInFuture && ClosesAtUtc <= DateTime.UtcNow) return "Der Wettschluss muss in der Zukunft liegen.";
        return null;
    }
}
