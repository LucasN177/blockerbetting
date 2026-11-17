-- =====================================================================
-- BlockerBetting – Migration 004: Täglicher Coin-Bonus
-- Im Supabase SQL Editor ausführen, NACH 001–003.
--
-- Jeden Morgen um 8:00 Uhr (Europe/Berlin) erhält jeder Spieler 20 Coins.
--
-- pg_cron plant in UTC. 8:00 Uhr in Berlin ist im Winter 07:00 UTC und
-- im Sommer 06:00 UTC – der Job läuft daher um beide Zeiten und bucht nur,
-- wenn es in Berlin gerade 8 Uhr ist. Die Tabelle daily_bonus_runs stellt
-- sicher, dass pro Tag höchstens einmal gebucht wird.
-- =====================================================================

-- In Supabase alternativ unter Database → Extensions aktivierbar.
create extension if not exists pg_cron with schema pg_catalog;

create table if not exists public.daily_bonus_runs (
    day               date primary key,
    amount            int         not null,
    credited_profiles int         not null default 0,
    created_at        timestamptz not null default now()
);

-- Nur intern – keine Policies, Clients sehen die Tabelle nicht.
alter table public.daily_bonus_runs enable row level security;

create or replace function public.grant_daily_bonus(p_amount int default 20, p_force boolean default false)
returns int
language plpgsql security definer set search_path = public
as $$
declare
    v_local_now timestamp := now() at time zone 'Europe/Berlin';
    v_day       date      := v_local_now::date;
    v_count     int;
begin
    -- Nur um 8 Uhr deutscher Zeit (außer bei manuellem Nachholen mit p_force).
    if not p_force and extract(hour from v_local_now) <> 8 then
        return 0;
    end if;

    -- Höchstens einmal pro Tag.
    insert into public.daily_bonus_runs (day, amount) values (v_day, p_amount)
    on conflict (day) do nothing;
    if not found then
        return 0;
    end if;

    -- "where true": explizit alle Spieler (Supabase blockiert je nach Einstellung UPDATE ohne WHERE).
    update public.profiles set coins = coins + p_amount where true;
    get diagnostics v_count = row_count;

    update public.daily_bonus_runs set credited_profiles = v_count where day = v_day;
    return v_count;
end;
$$;

-- Nur der Datenbank-Job (bzw. ein Admin im SQL Editor) darf den Bonus auslösen.
revoke execute on function public.grant_daily_bonus(int, boolean) from public, anon, authenticated;

-- Job anlegen bzw. aktualisieren (gleicher Name überschreibt den bestehenden Job).
select cron.schedule('daily-bonus', '0 6,7 * * *', $$select public.grant_daily_bonus()$$);

-- Prüfen:     select * from cron.job where jobname = 'daily-bonus';
-- Verlauf:    select * from public.daily_bonus_runs order by day desc;
-- Nachholen:  select public.grant_daily_bonus(20, true);   -- bucht nur, wenn heute noch nichts gebucht wurde
-- Entfernen:  select cron.unschedule('daily-bonus');
