-- =====================================================================
-- BlockerBetting – Migration 007: Spiele (Beta) – Blackjack
-- Im Supabase SQL Editor ausführen, NACH 001–006.
--
-- Regeln: 6 Decks, pro Runde frisch gemischt (kryptografischer Zufall).
-- Dealer zieht bis 16 und steht ab 17 (auch Soft 17). Blackjack zahlt 3:2,
-- Gewinn 1:1, Unentschieden = Einsatz zurück. Verdoppeln auf die ersten
-- zwei Karten (genau eine weitere Karte). Kein Split, keine Versicherung.
--
-- Das Deck liegt nur in der Datenbank. Tabelle blackjack_hands hat RLS
-- ohne Lese-Policy – Clients sehen ausschließlich, was die RPCs zurückgeben
-- (die verdeckte Dealer-Karte erst nach Rundenende).
--
-- Karten: 0–51, Rang = code % 13 (0 = Ass, 1–9 = 2–10, 10–12 = B/D/K),
--         Farbe = code / 13 (0 Pik, 1 Herz, 2 Karo, 3 Kreuz). -1 = verdeckt.
-- =====================================================================

create extension if not exists pgcrypto with schema extensions;

create table if not exists public.blackjack_hands (
    id          uuid primary key default gen_random_uuid(),
    user_id     uuid        not null references public.profiles (id) on delete cascade,
    bet         bigint      not null check (bet > 0),
    deck        int[]       not null,
    player      int[]       not null,
    dealer      int[]       not null,
    doubled     boolean     not null default false,
    status      text        not null default 'playing' check (status in ('playing', 'finished')),
    outcome     text        check (outcome in ('blackjack', 'win', 'push', 'lose')),
    payout      bigint      not null default 0,
    created_at  timestamptz not null default now(),
    finished_at timestamptz
);

-- Höchstens eine laufende Hand pro Spieler.
create unique index if not exists blackjack_one_active on public.blackjack_hands (user_id) where status = 'playing';
create index if not exists blackjack_user_idx on public.blackjack_hands (user_id, created_at desc);

-- Keine Policies: Lesen und Schreiben nur über die RPCs unten.
alter table public.blackjack_hands enable row level security;

-- ---------------------------------------------------------------------
-- Hilfsfunktionen
-- ---------------------------------------------------------------------

-- Bester Kartenwert (Asse zählen 11, solange es nicht über 21 geht).
create or replace function public._bj_total(p_cards int[])
returns int
language plpgsql immutable
as $$
declare
    v_total int := 0;
    v_aces  int := 0;
    v_card  int;
    v_rank  int;
begin
    foreach v_card in array coalesce(p_cards, '{}'::int[]) loop
        v_rank := v_card % 13;
        if v_rank = 0 then
            v_aces := v_aces + 1;
            v_total := v_total + 1;
        elsif v_rank >= 9 then
            v_total := v_total + 10;
        else
            v_total := v_total + v_rank + 1;
        end if;
    end loop;
    if v_aces > 0 and v_total + 10 <= 21 then
        v_total := v_total + 10;
    end if;
    return v_total;
end;
$$;

-- Frisch gemischter Schlitten aus p_decks Decks (Fisher-Yates mit kryptografischem Zufall).
create or replace function public._bj_new_deck(p_decks int default 6)
returns int[]
language plpgsql volatile set search_path = public, extensions
as $$
declare
    v_n    int := 52 * p_decks;
    v_deck int[];
    v_i    int;
    v_j    int;
    v_tmp  int;
begin
    select array_agg(g % 52 order by g) into v_deck from generate_series(0, v_n - 1) as g;
    for v_i in reverse v_n .. 2 loop
        v_j := 1 + (('x' || encode(extensions.gen_random_bytes(3), 'hex'))::bit(24)::int % v_i);
        v_tmp := v_deck[v_i];
        v_deck[v_i] := v_deck[v_j];
        v_deck[v_j] := v_tmp;
    end loop;
    return v_deck;
end;
$$;

-- Für den Client sichtbarer Zustand (verdeckte Dealer-Karte als -1, kein Deck).
create or replace function public._bj_state(p_hand_id uuid)
returns jsonb
language plpgsql stable security definer set search_path = public
as $$
declare
    h       public.blackjack_hands;
    v_coins bigint;
begin
    select * into h from public.blackjack_hands where id = p_hand_id;
    if not found then
        return null;
    end if;
    select coins into v_coins from public.profiles where id = h.user_id;

    return jsonb_build_object(
        'id', h.id,
        'status', h.status,
        'bet', h.bet,
        'doubled', h.doubled,
        'player', to_jsonb(h.player),
        'player_total', public._bj_total(h.player),
        'dealer', case when h.status = 'playing' then jsonb_build_array(h.dealer[1], -1) else to_jsonb(h.dealer) end,
        'dealer_total', case when h.status = 'playing' then public._bj_total(array[h.dealer[1]]) else public._bj_total(h.dealer) end,
        'outcome', h.outcome,
        'payout', h.payout,
        'can_double', h.status = 'playing' and array_length(h.player, 1) = 2 and not h.doubled and v_coins >= h.bet,
        'coins', v_coins
    );
end;
$$;

-- Dealer spielt aus, Ergebnis wird verbucht.
create or replace function public._bj_finish(p_hand_id uuid)
returns void
language plpgsql security definer set search_path = public
as $$
declare
    h         public.blackjack_hands;
    v_player  int;
    v_dealer  int;
    v_outcome text;
    v_payout  bigint := 0;
begin
    select * into h from public.blackjack_hands where id = p_hand_id and status = 'playing' for update;
    if not found then
        return;
    end if;

    v_player := public._bj_total(h.player);
    if v_player > 21 then
        v_outcome := 'lose';                      -- überkauft, Dealer muss nicht ziehen
    else
        while public._bj_total(h.dealer) < 17 loop
            h.dealer := h.dealer || h.deck[1];
            h.deck := h.deck[2:];
        end loop;
        v_dealer := public._bj_total(h.dealer);
        if v_dealer > 21 or v_player > v_dealer then
            v_outcome := 'win';
            v_payout := h.bet * 2;
        elsif v_player = v_dealer then
            v_outcome := 'push';
            v_payout := h.bet;
        else
            v_outcome := 'lose';
        end if;
    end if;

    update public.blackjack_hands
    set dealer = h.dealer, deck = h.deck, status = 'finished', outcome = v_outcome,
        payout = v_payout, finished_at = now()
    where id = h.id;

    if v_payout > 0 then
        update public.profiles set coins = coins + v_payout where id = h.user_id;
    end if;
end;
$$;

-- Laufende Hand des Spielers (gesperrt) oder Fehler.
create or replace function public._bj_active(p_hand_id uuid)
returns public.blackjack_hands
language plpgsql security definer set search_path = public
as $$
declare
    h public.blackjack_hands;
begin
    select * into h from public.blackjack_hands
    where id = p_hand_id and user_id = auth.uid() and status = 'playing'
    for update;
    if not found then
        raise exception 'Keine laufende Runde gefunden.';
    end if;
    return h;
end;
$$;

-- ---------------------------------------------------------------------
-- RPCs
-- ---------------------------------------------------------------------

-- Laufende Runde (zum Fortsetzen nach Neuladen) oder null.
create or replace function public.blackjack_current()
returns jsonb
language sql security definer set search_path = public
as $$
    select public._bj_state(id) from public.blackjack_hands
    where user_id = auth.uid() and status = 'playing'
    limit 1;
$$;

-- Neue Runde: Einsatz abbuchen, austeilen, Blackjacks sofort auswerten.
-- Läuft schon eine Runde, wird diese zurückgegeben.
create or replace function public.blackjack_start(p_bet bigint)
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
    v_uid    uuid := auth.uid();
    v_id     uuid;
    v_coins  bigint;
    v_deck   int[];
    v_player int[];
    v_dealer int[];
    v_pnat   boolean;
    v_dnat   boolean;
    v_payout bigint;
    v_outcome text;
begin
    if v_uid is null then
        raise exception 'Nicht angemeldet.';
    end if;

    select id into v_id from public.blackjack_hands where user_id = v_uid and status = 'playing';
    if found then
        return public._bj_state(v_id);
    end if;

    if p_bet is null or p_bet <= 0 then
        raise exception 'Der Einsatz muss größer als 0 sein.';
    end if;
    select coins into v_coins from public.profiles where id = v_uid for update;
    if v_coins is null then
        raise exception 'Profil nicht gefunden.';
    end if;
    if v_coins < p_bet then
        raise exception 'Nicht genug Coins (verfügbar: %).', v_coins;
    end if;

    update public.profiles set coins = coins - p_bet where id = v_uid;

    v_deck := public._bj_new_deck(6);
    v_player := array[v_deck[1], v_deck[3]];
    v_dealer := array[v_deck[2], v_deck[4]];
    v_deck := v_deck[5:];

    insert into public.blackjack_hands (user_id, bet, deck, player, dealer)
    values (v_uid, p_bet, v_deck, v_player, v_dealer)
    returning id into v_id;

    v_pnat := public._bj_total(v_player) = 21;
    v_dnat := public._bj_total(v_dealer) = 21;
    if v_pnat or v_dnat then
        if v_pnat and v_dnat then
            v_outcome := 'push';  v_payout := p_bet;
        elsif v_pnat then
            v_outcome := 'blackjack';  v_payout := p_bet + (p_bet * 3) / 2;
        else
            v_outcome := 'lose';  v_payout := 0;
        end if;
        update public.blackjack_hands
        set status = 'finished', outcome = v_outcome, payout = v_payout, finished_at = now()
        where id = v_id;
        if v_payout > 0 then
            update public.profiles set coins = coins + v_payout where id = v_uid;
        end if;
    end if;

    return public._bj_state(v_id);
end;
$$;

create or replace function public.blackjack_hit(p_hand_id uuid)
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
    h public.blackjack_hands;
begin
    h := public._bj_active(p_hand_id);
    h.player := h.player || h.deck[1];
    h.deck := h.deck[2:];
    update public.blackjack_hands set player = h.player, deck = h.deck where id = h.id;

    -- Überkauft oder 21: Runde automatisch beenden.
    if public._bj_total(h.player) >= 21 then
        perform public._bj_finish(h.id);
    end if;
    return public._bj_state(h.id);
end;
$$;

create or replace function public.blackjack_stand(p_hand_id uuid)
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
    h public.blackjack_hands;
begin
    h := public._bj_active(p_hand_id);
    perform public._bj_finish(h.id);
    return public._bj_state(h.id);
end;
$$;

create or replace function public.blackjack_double(p_hand_id uuid)
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
    h       public.blackjack_hands;
    v_coins bigint;
begin
    h := public._bj_active(p_hand_id);
    if array_length(h.player, 1) <> 2 or h.doubled then
        raise exception 'Verdoppeln ist nur mit den ersten zwei Karten möglich.';
    end if;
    select coins into v_coins from public.profiles where id = h.user_id for update;
    if v_coins < h.bet then
        raise exception 'Nicht genug Coins zum Verdoppeln (verfügbar: %).', v_coins;
    end if;

    update public.profiles set coins = coins - h.bet where id = h.user_id;
    h.player := h.player || h.deck[1];
    h.deck := h.deck[2:];
    update public.blackjack_hands
    set bet = h.bet * 2, doubled = true, player = h.player, deck = h.deck
    where id = h.id;

    perform public._bj_finish(h.id);
    return public._bj_state(h.id);
end;
$$;

-- Letzte abgeschlossene Runden des Spielers.
create or replace function public.blackjack_history(p_limit int default 10)
returns jsonb
language sql stable security definer set search_path = public
as $$
    select coalesce(jsonb_agg(r order by r.finished_at desc), '[]'::jsonb)
    from (
        select finished_at, bet, outcome, payout,
               public._bj_total(player) as player_total,
               public._bj_total(dealer) as dealer_total
        from public.blackjack_hands
        where user_id = auth.uid() and status = 'finished'
        order by finished_at desc
        limit least(greatest(p_limit, 1), 50)
    ) r;
$$;

-- ---------------------------------------------------------------------
-- Rechte
-- ---------------------------------------------------------------------
revoke execute on function public._bj_new_deck(int)        from public, anon, authenticated;
revoke execute on function public._bj_state(uuid)          from public, anon, authenticated;
revoke execute on function public._bj_finish(uuid)         from public, anon, authenticated;
revoke execute on function public._bj_active(uuid)         from public, anon, authenticated;
revoke execute on function public.blackjack_current()      from public, anon;
revoke execute on function public.blackjack_start(bigint)  from public, anon;
revoke execute on function public.blackjack_hit(uuid)      from public, anon;
revoke execute on function public.blackjack_stand(uuid)    from public, anon;
revoke execute on function public.blackjack_double(uuid)   from public, anon;
revoke execute on function public.blackjack_history(int)   from public, anon;
grant  execute on function public.blackjack_current()      to authenticated;
grant  execute on function public.blackjack_start(bigint)  to authenticated;
grant  execute on function public.blackjack_hit(uuid)      to authenticated;
grant  execute on function public.blackjack_stand(uuid)    to authenticated;
grant  execute on function public.blackjack_double(uuid)   to authenticated;
grant  execute on function public.blackjack_history(int)   to authenticated;

notify pgrst, 'reload schema';
