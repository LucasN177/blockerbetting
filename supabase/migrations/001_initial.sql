-- =====================================================================
-- BlockerBetting – Migration 001: Grundschema
-- Run this once in the Supabase SQL editor. It is idempotent where
-- practical (create ... if not exists / create or replace).
-- =====================================================================

-- ---------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------

create table if not exists public.profiles (
    id           uuid primary key references auth.users (id) on delete cascade,
    display_name text        not null,
    coins        bigint      not null default 1000 check (coins >= 0),
    is_admin     boolean     not null default false,
    created_at   timestamptz not null default now()
);

create table if not exists public.events (
    id                uuid primary key default gen_random_uuid(),
    title             text        not null check (char_length(title) between 3 and 200),
    description       text,
    status            text        not null default 'open'
                      check (status in ('open', 'locked', 'resolved', 'cancelled')),
    closes_at         timestamptz,
    winning_option_id uuid,
    created_by        uuid references public.profiles (id) on delete set null,
    created_at        timestamptz not null default now(),
    resolved_at       timestamptz
);

create table if not exists public.event_options (
    id         uuid primary key default gen_random_uuid(),
    event_id   uuid not null references public.events (id) on delete cascade,
    label      text not null check (char_length(label) between 1 and 100),
    sort_order int  not null default 0
);

do $$
begin
    if not exists (select 1 from pg_constraint where conname = 'events_winning_option_fk') then
        alter table public.events
            add constraint events_winning_option_fk
            foreign key (winning_option_id) references public.event_options (id) on delete set null;
    end if;
end $$;

create table if not exists public.bets (
    id         uuid primary key default gen_random_uuid(),
    user_id    uuid   not null references public.profiles (id) on delete cascade,
    event_id   uuid   not null references public.events (id) on delete cascade,
    option_id  uuid   not null references public.event_options (id) on delete cascade,
    amount     bigint not null check (amount > 0),
    payout     bigint,
    created_at timestamptz not null default now()
);

create index if not exists bets_event_idx  on public.bets (event_id);
create index if not exists bets_user_idx   on public.bets (user_id);
create index if not exists options_event_idx on public.event_options (event_id);

-- Aggregated pool per option (used for odds)
create or replace view public.event_option_pools
with (security_invoker = true) as
select o.id                         as option_id,
       o.event_id,
       coalesce(sum(b.amount), 0)::bigint as total_amount,
       count(b.id)::int             as bet_count
from public.event_options o
left join public.bets b on b.option_id = o.id
group by o.id, o.event_id;

-- ---------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------

create or replace function public.is_admin()
returns boolean
language sql stable security definer set search_path = public
as $$
    select coalesce((select is_admin from public.profiles where id = auth.uid()), false);
$$;

-- Create a profile automatically for every new auth user
create or replace function public.handle_new_user()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
    insert into public.profiles (id, display_name)
    values (
        new.id,
        coalesce(nullif(trim(new.raw_user_meta_data ->> 'display_name'), ''), split_part(new.email, '@', 1))
    )
    on conflict (id) do nothing;
    return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
    after insert on auth.users
    for each row execute function public.handle_new_user();

-- ---------------------------------------------------------------------
-- Row Level Security
-- Reads: every signed-in user sees everything (internal platform).
-- Writes: only through the security-definer RPCs below, except a user
-- may rename themselves.
-- ---------------------------------------------------------------------

alter table public.profiles      enable row level security;
alter table public.events        enable row level security;
alter table public.event_options enable row level security;
alter table public.bets          enable row level security;

drop policy if exists "profiles readable" on public.profiles;
create policy "profiles readable" on public.profiles
    for select to authenticated using (true);

drop policy if exists "profiles update own" on public.profiles;
create policy "profiles update own" on public.profiles
    for update to authenticated using (id = auth.uid()) with check (id = auth.uid());

-- Only display_name may be changed by the user itself
revoke update on public.profiles from authenticated, anon;
grant update (display_name) on public.profiles to authenticated;

drop policy if exists "events readable" on public.events;
create policy "events readable" on public.events
    for select to authenticated using (true);

drop policy if exists "options readable" on public.event_options;
create policy "options readable" on public.event_options
    for select to authenticated using (true);

drop policy if exists "bets readable" on public.bets;
create policy "bets readable" on public.bets
    for select to authenticated using (true);

-- ---------------------------------------------------------------------
-- RPCs
-- ---------------------------------------------------------------------

-- Place a bet: checks event state and balance, deducts coins atomically.
create or replace function public.place_bet(p_option_id uuid, p_amount bigint)
returns public.bets
language plpgsql security definer set search_path = public
as $$
declare
    v_uid   uuid := auth.uid();
    v_event public.events;
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

    select coins into v_coins from public.profiles where id = v_uid for update;
    if v_coins is null then
        raise exception 'Profil nicht gefunden.';
    end if;
    if v_coins < p_amount then
        raise exception 'Nicht genug Coins (verfügbar: %).', v_coins;
    end if;

    update public.profiles set coins = coins - p_amount where id = v_uid;

    insert into public.bets (user_id, event_id, option_id, amount)
    values (v_uid, v_event.id, p_option_id, p_amount)
    returning * into v_bet;

    return v_bet;
end;
$$;

-- Create an event with its options (admin only).
create or replace function public.create_event(
    p_title       text,
    p_description text,
    p_closes_at   timestamptz,
    p_options     text[]
)
returns uuid
language plpgsql security definer set search_path = public
as $$
declare
    v_event_id uuid;
    v_label    text;
    v_i        int := 0;
begin
    if not public.is_admin() then
        raise exception 'Nur Admins dürfen Events anlegen.';
    end if;
    if p_options is null or array_length(p_options, 1) < 2 then
        raise exception 'Ein Event braucht mindestens zwei Optionen.';
    end if;

    insert into public.events (title, description, closes_at, created_by)
    values (trim(p_title), nullif(trim(p_description), ''), p_closes_at, auth.uid())
    returning id into v_event_id;

    foreach v_label in array p_options loop
        if nullif(trim(v_label), '') is not null then
            insert into public.event_options (event_id, label, sort_order)
            values (v_event_id, trim(v_label), v_i);
            v_i := v_i + 1;
        end if;
    end loop;

    if v_i < 2 then
        raise exception 'Ein Event braucht mindestens zwei Optionen.';
    end if;

    return v_event_id;
end;
$$;

-- Stop accepting bets (admin only).
create or replace function public.lock_event(p_event_id uuid)
returns void
language plpgsql security definer set search_path = public
as $$
begin
    if not public.is_admin() then
        raise exception 'Nur Admins dürfen Events sperren.';
    end if;
    update public.events set status = 'locked'
    where id = p_event_id and status = 'open';
    if not found then
        raise exception 'Event nicht gefunden oder nicht offen.';
    end if;
end;
$$;

-- Resolve an event and pay out the pool (pari-mutuel). Admin only.
-- If nobody bet on the winning option, all stakes are refunded.
create or replace function public.resolve_event(p_event_id uuid, p_winning_option_id uuid)
returns void
language plpgsql security definer set search_path = public
as $$
declare
    v_status       text;
    v_total_pool   bigint;
    v_winning_pool bigint;
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

    select coalesce(sum(amount), 0) into v_total_pool   from public.bets where event_id = p_event_id;
    select coalesce(sum(amount), 0) into v_winning_pool from public.bets where option_id = p_winning_option_id;

    if v_winning_pool = 0 then
        update public.bets set payout = amount where event_id = p_event_id;
    else
        update public.bets
        set payout = case when option_id = p_winning_option_id
                          then floor(amount::numeric * v_total_pool / v_winning_pool)::bigint
                          else 0 end
        where event_id = p_event_id;
    end if;

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

-- Cancel an event and refund every stake. Admin only.
create or replace function public.cancel_event(p_event_id uuid)
returns void
language plpgsql security definer set search_path = public
as $$
declare
    v_status text;
begin
    if not public.is_admin() then
        raise exception 'Nur Admins dürfen Events abbrechen.';
    end if;

    select status into v_status from public.events where id = p_event_id for update;
    if v_status is null then
        raise exception 'Event nicht gefunden.';
    end if;
    if v_status not in ('open', 'locked') then
        raise exception 'Event ist bereits abgeschlossen.';
    end if;

    update public.bets set payout = amount where event_id = p_event_id;

    update public.profiles p
    set coins = p.coins + r.total
    from (
        select user_id, sum(amount) as total
        from public.bets
        where event_id = p_event_id
        group by user_id
    ) r
    where p.id = r.user_id;

    update public.events set status = 'cancelled', resolved_at = now() where id = p_event_id;
end;
$$;

-- Only signed-in users may call the RPCs
revoke execute on function public.place_bet(uuid, bigint)                         from public, anon;
revoke execute on function public.create_event(text, text, timestamptz, text[])   from public, anon;
revoke execute on function public.lock_event(uuid)                                from public, anon;
revoke execute on function public.resolve_event(uuid, uuid)                       from public, anon;
revoke execute on function public.cancel_event(uuid)                              from public, anon;
grant  execute on function public.place_bet(uuid, bigint)                         to authenticated;
grant  execute on function public.create_event(text, text, timestamptz, text[])   to authenticated;
grant  execute on function public.lock_event(uuid)                                to authenticated;
grant  execute on function public.resolve_event(uuid, uuid)                       to authenticated;
grant  execute on function public.cancel_event(uuid)                              to authenticated;
