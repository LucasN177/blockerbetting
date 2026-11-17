-- =====================================================================
-- BlockerBetting – Migration 008: Poor Mode (Spiele)
-- Im Supabase SQL Editor ausführen, NACH 001–007.
--
-- Im Poor Mode erscheint bei den Spielen alle 60 Sekunden ein Coin, den man
-- anklicken und einsammeln kann. Timer und Spawn laufen im Browser; die
-- Datenbank schreibt nur den eingesammelten Coin gut.
-- Der Betrag ist hier fest vorgegeben (1 Coin) – der Browser kann keine
-- beliebigen Beträge buchen.
-- =====================================================================

create or replace function public.claim_poor_mode_coin()
returns jsonb
language plpgsql security definer set search_path = public
as $$
declare
    c_amount constant bigint := 1;
    v_coins  bigint;
begin
    if auth.uid() is null then
        raise exception 'Nicht angemeldet.';
    end if;

    update public.profiles set coins = coins + c_amount where id = auth.uid()
    returning coins into v_coins;

    return jsonb_build_object('amount', c_amount, 'coins', v_coins);
end;
$$;

revoke execute on function public.claim_poor_mode_coin() from public, anon;
grant  execute on function public.claim_poor_mode_coin() to authenticated;

notify pgrst, 'reload schema';
