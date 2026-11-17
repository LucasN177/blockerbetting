-- =====================================================================
-- BlockerBetting – Migration 003: Wett-Anfragen
-- Im Supabase SQL Editor ausführen, NACH 001 und 002.
--
-- * Jeder Spieler kann Wetten vorschlagen (bet_requests).
-- * Admins bearbeiten, genehmigen oder lehnen Anfragen ab.
-- * Bei Genehmigung entsteht ein Event mit created_by = Antragsteller.
-- * Der Ersteller eines Events darf es nach Wettschluss auflösen.
-- =====================================================================

create table if not exists public.bet_requests (
    id           uuid primary key default gen_random_uuid(),
    requested_by uuid        not null references public.profiles (id) on delete cascade,
    title        text        not null check (char_length(title) between 3 and 200),
    description  text,
    closes_at    timestamptz not null,
    options      jsonb       not null,
    status       text        not null default 'pending'
                 check (status in ('pending', 'approved', 'rejected', 'withdrawn')),
    admin_note   text,
    event_id     uuid references public.events (id) on delete set null,
    reviewed_by  uuid references public.profiles (id) on delete set null,
    reviewed_at  timestamptz,
    created_at   timestamptz not null default now()
);

create index if not exists bet_requests_status_idx on public.bet_requests (status, created_at desc);
create index if not exists bet_requests_user_idx   on public.bet_requests (requested_by);

alter table public.bet_requests enable row level security;

-- Spieler sehen ihre eigenen Anfragen, Admins alle. Schreiben nur über RPCs.
drop policy if exists "bet_requests readable" on public.bet_requests;
create policy "bet_requests readable" on public.bet_requests
    for select to authenticated using (requested_by = auth.uid() or public.is_admin());

-- ---------------------------------------------------------------------
-- Spieler: Anfrage stellen / zurückziehen
-- ---------------------------------------------------------------------
create or replace function public.submit_bet_request(
    p_title       text,
    p_description text,
    p_closes_at   timestamptz,
    p_options     jsonb
)
returns uuid
language plpgsql security definer set search_path = public
as $$
declare
    v_id uuid;
begin
    if auth.uid() is null then
        raise exception 'Nicht angemeldet.';
    end if;
    if p_closes_at is null or p_closes_at <= now() then
        raise exception 'Der Wettschluss muss in der Zukunft liegen.';
    end if;
    perform public._validate_options(p_options);

    insert into public.bet_requests (requested_by, title, description, closes_at, options)
    values (auth.uid(), trim(p_title), nullif(trim(p_description), ''), p_closes_at, p_options)
    returning id into v_id;

    return v_id;
end;
$$;

create or replace function public.withdraw_bet_request(p_request_id uuid)
returns void
language plpgsql security definer set search_path = public
as $$
begin
    update public.bet_requests set status = 'withdrawn'
    where id = p_request_id and requested_by = auth.uid() and status = 'pending';
    if not found then
        raise exception 'Anfrage nicht gefunden oder nicht mehr offen.';
    end if;
end;
$$;

-- ---------------------------------------------------------------------
-- Admin: genehmigen (mit optionalen Änderungen) / ablehnen
-- ---------------------------------------------------------------------
create or replace function public.approve_bet_request(
    p_request_id  uuid,
    p_title       text,
    p_description text,
    p_closes_at   timestamptz,
    p_options     jsonb
)
returns uuid
language plpgsql security definer set search_path = public
as $$
declare
    v_request  public.bet_requests;
    v_event_id uuid;
    v_opt      jsonb;
    v_i        int := 0;
begin
    if not public.is_admin() then
        raise exception 'Nur Admins dürfen Anfragen genehmigen.';
    end if;

    select * into v_request from public.bet_requests where id = p_request_id for update;
    if not found then
        raise exception 'Anfrage nicht gefunden.';
    end if;
    if v_request.status <> 'pending' then
        raise exception 'Diese Anfrage wurde bereits bearbeitet.';
    end if;
    if p_closes_at is null or p_closes_at <= now() then
        raise exception 'Der Wettschluss muss in der Zukunft liegen.';
    end if;
    perform public._validate_options(p_options);

    -- Der Antragsteller wird Ersteller des Events (und darf es später auflösen).
    insert into public.events (title, description, closes_at, created_by)
    values (trim(p_title), nullif(trim(p_description), ''), p_closes_at, v_request.requested_by)
    returning id into v_event_id;

    for v_opt in select * from jsonb_array_elements(p_options) loop
        insert into public.event_options (event_id, label, odds, sort_order)
        values (v_event_id, trim(v_opt ->> 'label'), (v_opt ->> 'odds')::numeric, v_i);
        v_i := v_i + 1;
    end loop;

    update public.bet_requests
    set status = 'approved', event_id = v_event_id, reviewed_by = auth.uid(), reviewed_at = now(),
        title = trim(p_title), description = nullif(trim(p_description), ''), closes_at = p_closes_at, options = p_options
    where id = p_request_id;

    return v_event_id;
end;
$$;

create or replace function public.reject_bet_request(p_request_id uuid, p_note text)
returns void
language plpgsql security definer set search_path = public
as $$
begin
    if not public.is_admin() then
        raise exception 'Nur Admins dürfen Anfragen ablehnen.';
    end if;
    update public.bet_requests
    set status = 'rejected', admin_note = nullif(trim(p_note), ''), reviewed_by = auth.uid(), reviewed_at = now()
    where id = p_request_id and status = 'pending';
    if not found then
        raise exception 'Anfrage nicht gefunden oder bereits bearbeitet.';
    end if;
end;
$$;

-- ---------------------------------------------------------------------
-- Auflösen: Admins jederzeit, Ersteller nach Wettschluss
-- ---------------------------------------------------------------------
create or replace function public.can_resolve_event(p_event_id uuid)
returns boolean
language sql stable security definer set search_path = public
as $$
    select public.is_admin() or exists (
        select 1 from public.events
        where id = p_event_id
          and created_by = auth.uid()
          and closes_at is not null
          and closes_at <= now()
    );
$$;

create or replace function public.resolve_event(p_event_id uuid, p_winning_option_id uuid)
returns void
language plpgsql security definer set search_path = public
as $$
declare
    v_status text;
begin
    if not public.can_resolve_event(p_event_id) then
        raise exception 'Nur Admins oder der Ersteller (nach Wettschluss) dürfen diese Wette auflösen.';
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
revoke execute on function public.submit_bet_request(text, text, timestamptz, jsonb)          from public, anon;
revoke execute on function public.withdraw_bet_request(uuid)                                  from public, anon;
revoke execute on function public.approve_bet_request(uuid, text, text, timestamptz, jsonb)   from public, anon;
revoke execute on function public.reject_bet_request(uuid, text)                              from public, anon;
revoke execute on function public.can_resolve_event(uuid)                                     from public, anon;
grant  execute on function public.submit_bet_request(text, text, timestamptz, jsonb)          to authenticated;
grant  execute on function public.withdraw_bet_request(uuid)                                  to authenticated;
grant  execute on function public.approve_bet_request(uuid, text, text, timestamptz, jsonb)   to authenticated;
grant  execute on function public.reject_bet_request(uuid, text)                              to authenticated;
grant  execute on function public.can_resolve_event(uuid)                                     to authenticated;

notify pgrst, 'reload schema';
