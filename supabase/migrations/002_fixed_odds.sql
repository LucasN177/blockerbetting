-- =====================================================================
-- BlockerBetting – Migration 002: feste Quoten (manuell vom Admin)
-- Im Supabase SQL Editor ausführen, NACH supabase/schema.sql.
--
-- * Jede Option hat eine feste Quote (odds), die Admins pflegen.
-- * Jede Wette speichert die Quote zum Zeitpunkt der Abgabe.
-- * Auszahlung bei Gewinn: floor(Einsatz × gespeicherte Quote).
-- =====================================================================

alter table public.event_options
    add column if not exists odds numeric(8, 2) not null default 2.00;

do $$
begin
    if not exists (select 1 from pg_constraint where conname = 'event_options_odds_check') then
        alter table public.event_options
            add constraint event_options_odds_check check (odds >= 1.01 and odds <= 1000);
    end if;
end $$;

alter table public.bets
    add column if not exists odds numeric(8, 2);

-- Bestehende Wetten erhalten die aktuelle Quote ihrer Option
update public.bets b
set odds = o.odds
from public.event_options o
where o.id = b.option_id and b.odds is null;

alter table public.bets alter column odds set not null;

-- ---------------------------------------------------------------------
-- Helper: Optionen aus JSON validieren
-- Format: [{"id": "<uuid|null>", "label": "Ja", "odds": 1.8}, ...]
-- ---------------------------------------------------------------------
create or replace function public._validate_options(p_options jsonb)
returns void
language plpgsql immutable
as $$
declare
    v_opt jsonb;
    v_count int := 0;
begin
    if p_options is null or jsonb_typeof(p_options) <> 'array' then
        raise exception 'Optionen fehlen.';
    end if;
    for v_opt in select * from jsonb_array_elements(p_options) loop
        if nullif(trim(v_opt ->> 'label'), '') is null then
            raise exception 'Jede Option braucht eine Bezeichnung.';
        end if;
        if (v_opt ->> 'odds') is null or (v_opt ->> 'odds')::numeric < 1.01 then
            raise exception 'Quote für „%“ muss mindestens 1,01 sein.', v_opt ->> 'label';
        end if;
        v_count := v_count + 1;
    end loop;
    if v_count < 2 then
        raise exception 'Eine Wette braucht mindestens zwei Optionen.';
    end if;
end;
$$;

-- ---------------------------------------------------------------------
-- place_bet: speichert die aktuelle Quote mit
-- ---------------------------------------------------------------------
create or replace function public.place_bet(p_option_id uuid, p_amount bigint)
returns public.bets
language plpgsql security definer set search_path = public
as $$
declare
    v_uid   uuid := auth.uid();
    v_event public.events;
    v_odds  numeric(8, 2);
    v_coins bigint;
    v_bet   public.bets;
begin
    if v_uid is null then
        raise exception 'Nicht angemeldet.';
    end if;
    if p_amount is null or p_amount <= 0 then
        raise exception 'Der Einsatz muss größer als 0 sein.';
    end if;

    select e.* into v_event
    from public.events e
    join public.event_options o on o.event_id = e.id
    where o.id = p_option_id
    for update of e;

    if not found then
        raise exception 'Option nicht gefunden.';
    end if;
    if v_event.status <> 'open' or (v_event.closes_at is not null and v_event.closes_at <= now()) then
        raise exception 'Für dieses Event werden keine Wetten mehr angenommen.';
    end if;

    select odds into v_odds from public.event_options where id = p_option_id;

    select coins into v_coins from public.profiles where id = v_uid for update;
    if v_coins is null then
        raise exception 'Profil nicht gefunden.';
    end if;
    if v_coins < p_amount then
        raise exception 'Nicht genug Coins (verfügbar: %).', v_coins;
    end if;

    update public.profiles set coins = coins - p_amount where id = v_uid;

    insert into public.bets (user_id, event_id, option_id, amount, odds)
    values (v_uid, v_event.id, p_option_id, p_amount, v_odds)
    returning * into v_bet;

    return v_bet;
end;
$$;

-- ---------------------------------------------------------------------
-- create_event: Optionen inkl. Quoten als JSON
-- ---------------------------------------------------------------------
drop function if exists public.create_event(text, text, timestamptz, text[]);

create or replace function public.create_event(
    p_title       text,
    p_description text,
    p_closes_at   timestamptz,
    p_options     jsonb
)
returns uuid
language plpgsql security definer set search_path = public
as $$
declare
    v_event_id uuid;
    v_opt      jsonb;
    v_i        int := 0;
begin
    if not public.is_admin() then
        raise exception 'Nur Admins dürfen Wetten anlegen.';
    end if;
    perform public._validate_options(p_options);

    insert into public.events (title, description, closes_at, created_by)
    values (trim(p_title), nullif(trim(p_description), ''), p_closes_at, auth.uid())
    returning id into v_event_id;

    for v_opt in select * from jsonb_array_elements(p_options) loop
        insert into public.event_options (event_id, label, odds, sort_order)
        values (v_event_id, trim(v_opt ->> 'label'), (v_opt ->> 'odds')::numeric, v_i);
        v_i := v_i + 1;
    end loop;

    return v_event_id;
end;
$$;

-- ---------------------------------------------------------------------
-- update_event: Titel, Beschreibung, Wettschluss, Optionen & Quoten ändern.
-- Optionen mit "id" werden aktualisiert, ohne "id" neu angelegt, fehlende
-- gelöscht (nur möglich, wenn noch niemand darauf gesetzt hat).
-- Bereits abgegebene Wetten behalten ihre Quote.
-- ---------------------------------------------------------------------
create or replace function public.update_event(
    p_event_id    uuid,
    p_title       text,
    p_description text,
    p_closes_at   timestamptz,
    p_options     jsonb
)
returns void
language plpgsql security definer set search_path = public
as $$
declare
    v_status text;
    v_opt    jsonb;
    v_keep   uuid[] := '{}';
    v_id     uuid;
    v_i      int := 0;
begin
    if not public.is_admin() then
        raise exception 'Nur Admins dürfen Wetten bearbeiten.';
    end if;
    perform public._validate_options(p_options);

    select status into v_status from public.events where id = p_event_id for update;
    if v_status is null then
        raise exception 'Event nicht gefunden.';
    end if;
    if v_status not in ('open', 'locked') then
        raise exception 'Abgeschlossene Events können nicht mehr bearbeitet werden.';
    end if;

    update public.events
    set title = trim(p_title), description = nullif(trim(p_description), ''), closes_at = p_closes_at
    where id = p_event_id;

    for v_opt in select * from jsonb_array_elements(p_options) loop
        v_id := nullif(v_opt ->> 'id', '')::uuid;
        if v_id is not null then
            update public.event_options
            set label = trim(v_opt ->> 'label'), odds = (v_opt ->> 'odds')::numeric, sort_order = v_i
            where id = v_id and event_id = p_event_id;
            if not found then
                raise exception 'Option % gehört nicht zu diesem Event.', v_id;
            end if;
        else
            insert into public.event_options (event_id, label, odds, sort_order)
            values (p_event_id, trim(v_opt ->> 'label'), (v_opt ->> 'odds')::numeric, v_i)
            returning id into v_id;
        end if;
        v_keep := v_keep || v_id;
        v_i := v_i + 1;
    end loop;

    if exists (
        select 1 from public.bets
        where event_id = p_event_id and option_id <> all (v_keep)
    ) then
        raise exception 'Optionen, auf die bereits gesetzt wurde, können nicht gelöscht werden.';
    end if;

    delete from public.event_options
    where event_id = p_event_id and id <> all (v_keep);
end;
$$;

-- ---------------------------------------------------------------------
-- reopen_event: gesperrte Wette wieder öffnen
-- ---------------------------------------------------------------------
create or replace function public.reopen_event(p_event_id uuid)
returns void
language plpgsql security definer set search_path = public
as $$
begin
    if not public.is_admin() then
        raise exception 'Nur Admins dürfen Events öffnen.';
    end if;
    update public.events set status = 'open'
    where id = p_event_id and status = 'locked';
    if not found then
        raise exception 'Event nicht gefunden oder nicht gesperrt.';
    end if;
end;
$$;

-- ---------------------------------------------------------------------
-- resolve_event: Auszahlung = floor(Einsatz × gespeicherte Quote)
-- ---------------------------------------------------------------------
create or replace function public.resolve_event(p_event_id uuid, p_winning_option_id uuid)
returns void
language plpgsql security definer set search_path = public
as $$
declare
    v_status text;
begin
    if not public.is_admin() then
        raise exception 'Nur Admins dürfen Events auflösen.';
    end if;

    select status into v_status from public.events where id = p_event_id for update;
    if v_status is null then
        raise exception 'Event nicht gefunden.';
    end if;
    if v_status not in ('open', 'locked') then
        raise exception 'Event ist bereits abgeschlossen.';
    end if;
    if not exists (select 1 from public.event_options where id = p_winning_option_id and event_id = p_event_id) then
        raise exception 'Die Gewinner-Option gehört nicht zu diesem Event.';
    end if;

    update public.bets
    set payout = case when option_id = p_winning_option_id
                      then floor(amount * odds)::bigint
                      else 0 end
    where event_id = p_event_id;

    update public.profiles p
    set coins = p.coins + w.total
    from (
        select user_id, sum(payout) as total
        from public.bets
        where event_id = p_event_id and payout > 0
        group by user_id
    ) w
    where p.id = w.user_id;

    update public.events
    set status = 'resolved', winning_option_id = p_winning_option_id, resolved_at = now()
    where id = p_event_id;
end;
$$;

-- ---------------------------------------------------------------------
-- Rechte
-- ---------------------------------------------------------------------
revoke execute on function public._validate_options(jsonb)                                from public, anon, authenticated;
revoke execute on function public.create_event(text, text, timestamptz, jsonb)            from public, anon;
revoke execute on function public.update_event(uuid, text, text, timestamptz, jsonb)      from public, anon;
revoke execute on function public.reopen_event(uuid)                                      from public, anon;
grant  execute on function public.create_event(text, text, timestamptz, jsonb)            to authenticated;
grant  execute on function public.update_event(uuid, text, text, timestamptz, jsonb)      to authenticated;
grant  execute on function public.reopen_event(uuid)                                      to authenticated;

-- PostgREST-Schema-Cache neu laden, damit die neuen Signaturen sofort verfügbar sind
notify pgrst, 'reload schema';
