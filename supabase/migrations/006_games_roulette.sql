-- =====================================================================
-- BlockerBetting – Migration 006: Spiele (Beta) – Roulette
-- Im Supabase SQL Editor ausführen, NACH 001–005.
--
-- Europäisches Roulette (0–36, eine Null). Die Zahl wird serverseitig mit
-- einem kryptografischen Zufallsgenerator gezogen; Einsatz und Gewinn
-- werden in derselben Transaktion verbucht. Der Browser zeigt nur an.
--
-- Wett-Arten (Auszahlung inkl. Einsatz):
--   straight (0–36) 36x · dozen (1–3) / column (1–3) 3x
--   red, black, odd, even, low (1–18), high (19–36) 2x
-- =====================================================================

create extension if not exists pgcrypto with schema extensions;

create table if not exists public.game_rounds (
    id          uuid primary key default gen_random_uuid(),
    user_id     uuid        not null references public.profiles (id) on delete cascade,
    game        text        not null check (game in ('roulette')),
    bets        jsonb       not null,
    total_stake bigint      not null check (total_stake > 0),
    result      int         not null,
    payout      bigint      not null check (payout >= 0),
    created_at  timestamptz not null default now()
);

create index if not exists game_rounds_user_idx on public.game_rounds (user_id, created_at desc);

alter table public.game_rounds enable row level security;

drop policy if exists "game_rounds own" on public.game_rounds;
create policy "game_rounds own" on public.game_rounds
    for select to authenticated using (user_id = auth.uid());

-- Gleichverteilte Zahl 0..36 aus kryptografischen Zufallsbytes (Rejection Sampling).
create or replace function public._roulette_number()
returns int
language plpgsql volatile set search_path = public, extensions
as $$
declare
    v_byte int;
begin
    loop
        v_byte := get_byte(extensions.gen_random_bytes(1), 0);
        if v_byte < 222 then          -- 222 = 6 * 37, damit jede Zahl gleich wahrscheinlich ist
            return v_byte % 37;
        end if;
    end loop;
end;
$$;

create or replace function public._roulette_is_red(p_number int)
returns boolean
language sql immutable
as $$
    select p_number = any (array[1,3,5,7,9,12,14,16,18,19,21,23,25,27,30,32,34,36]);
$$;

-- Auszahlungsfaktor (inkl. Einsatz) einer Wette für das Ergebnis, 0 = verloren.
create or replace function public._roulette_factor(p_type text, p_value int, p_result int)
returns int
language plpgsql immutable
as $$
begin
    return case p_type
        when 'straight' then case when p_value = p_result then 36 else 0 end
        when 'dozen'    then case when p_result between (p_value - 1) * 12 + 1 and p_value * 12 then 3 else 0 end
        when 'column'   then case when p_result > 0 and (p_result - 1) % 3 = p_value - 1 then 3 else 0 end
        when 'red'      then case when public._roulette_is_red(p_result) then 2 else 0 end
        when 'black'    then case when p_result > 0 and not public._roulette_is_red(p_result) then 2 else 0 end
        when 'odd'      then case when p_result > 0 and p_result % 2 = 1 then 2 else 0 end
        when 'even'     then case when p_result > 0 and p_result % 2 = 0 then 2 else 0 end
        when 'low'      then case when p_result between 1 and 18 then 2 else 0 end
        when 'high'     then case when p_result between 19 and 36 then 2 else 0 end
        else 0
    end;
end;
$$;

-- Eine Runde spielen.
-- p_bets: [{"type": "straight", "value": 17, "amount": 10}, {"type": "red", "amount": 5}, ...]
create or replace function public.play_roulette(p_bets jsonb)
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
    v_uid    uuid := auth.uid();
    v_bet    jsonb;
    v_type   text;
    v_value  int;
    v_amount bigint;
    v_total  bigint := 0;
    v_payout bigint := 0;
    v_coins  bigint;
    v_result int;
begin
    if v_uid is null then
        raise exception 'Nicht angemeldet.';
    end if;
    if p_bets is null or jsonb_typeof(p_bets) <> 'array' or jsonb_array_length(p_bets) = 0 then
        raise exception 'Bitte mindestens einen Einsatz platzieren.';
    end if;
    if jsonb_array_length(p_bets) > 60 then
        raise exception 'Zu viele Einsätze in einer Runde.';
    end if;

    -- Einsätze prüfen
    for v_bet in select * from jsonb_array_elements(p_bets) loop
        v_type   := v_bet ->> 'type';
        v_value  := (v_bet ->> 'value')::int;
        v_amount := (v_bet ->> 'amount')::bigint;
        if v_amount is null or v_amount <= 0 then
            raise exception 'Ungültiger Einsatz.';
        end if;
        if not (
               (v_type = 'straight' and v_value between 0 and 36)
            or (v_type in ('dozen', 'column') and v_value between 1 and 3)
            or (v_type in ('red', 'black', 'odd', 'even', 'low', 'high'))
        ) then
            raise exception 'Ungültige Wette: %', v_bet;
        end if;
        v_total := v_total + v_amount;
    end loop;

    select coins into v_coins from public.profiles where id = v_uid for update;
    if v_coins is null then
        raise exception 'Profil nicht gefunden.';
    end if;
    if v_coins < v_total then
        raise exception 'Nicht genug Coins (verfügbar: %).', v_coins;
    end if;

    v_result := public._roulette_number();

    for v_bet in select * from jsonb_array_elements(p_bets) loop
        v_payout := v_payout + (v_bet ->> 'amount')::bigint
                    * public._roulette_factor(v_bet ->> 'type', (v_bet ->> 'value')::int, v_result);
    end loop;

    update public.profiles set coins = coins - v_total + v_payout where id = v_uid
    returning coins into v_coins;

    insert into public.game_rounds (user_id, game, bets, total_stake, result, payout)
    values (v_uid, 'roulette', p_bets, v_total, v_result, v_payout);

    return jsonb_build_object('result', v_result, 'total_stake', v_total, 'payout', v_payout, 'coins', v_coins);
end;
$$;

revoke execute on function public._roulette_number()                from public, anon, authenticated;
revoke execute on function public.play_roulette(jsonb)              from public, anon;
grant  execute on function public.play_roulette(jsonb)              to authenticated;

notify pgrst, 'reload schema';
