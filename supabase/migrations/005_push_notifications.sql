-- =====================================================================
-- BlockerBetting – Migration 005: Push-Benachrichtigungen
-- Im Supabase SQL Editor ausführen, NACH 001–004.
--
-- * Browser-Push-Abos der Spieler (push_subscriptions).
-- * Neue Wett-Anfrage          → Push an alle Admins.
-- * Anfrage genehmigt/abgelehnt → Push an den Antragsteller.
--
-- Der Versand läuft über die Edge Function "send-push" (supabase/functions).
-- Die Datenbank ruft sie per pg_net auf. Dafür müssen zwei Werte im
-- Supabase Vault liegen (siehe README, Abschnitt Push-Benachrichtigungen):
--   project_url          z. B. https://abcdefgh.supabase.co
--   push_webhook_secret  beliebiges langes Geheimnis (gleich wie Function-Secret PUSH_WEBHOOK_SECRET)
-- Fehlen die Werte, passiert einfach nichts – Anfragen funktionieren trotzdem.
-- =====================================================================

create extension if not exists pg_net with schema extensions;

create table if not exists public.push_subscriptions (
    id         uuid primary key default gen_random_uuid(),
    user_id    uuid        not null references public.profiles (id) on delete cascade,
    endpoint   text        not null unique,
    p256dh     text        not null,
    auth       text        not null,
    user_agent text,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create index if not exists push_subscriptions_user_idx on public.push_subscriptions (user_id);

alter table public.push_subscriptions enable row level security;

-- Spieler sehen nur ihre eigenen Geräte; geschrieben wird nur über die RPCs unten.
drop policy if exists "push_subscriptions own" on public.push_subscriptions;
create policy "push_subscriptions own" on public.push_subscriptions
    for select to authenticated using (user_id = auth.uid());

-- ---------------------------------------------------------------------
-- Geräte an-/abmelden
-- ---------------------------------------------------------------------

-- Speichert das Push-Abo dieses Browsers für den angemeldeten Spieler.
-- Ein Gerät gehört immer dem zuletzt angemeldeten Spieler.
create or replace function public.save_push_subscription(p_endpoint text, p_p256dh text, p_auth text, p_user_agent text)
returns void
language plpgsql security definer set search_path = public
as $$
begin
    if auth.uid() is null then
        raise exception 'Nicht angemeldet.';
    end if;
    insert into public.push_subscriptions (user_id, endpoint, p256dh, auth, user_agent)
    values (auth.uid(), p_endpoint, p_p256dh, p_auth, left(p_user_agent, 300))
    on conflict (endpoint) do update
        set user_id = excluded.user_id, p256dh = excluded.p256dh, auth = excluded.auth,
            user_agent = excluded.user_agent, updated_at = now();
end;
$$;

create or replace function public.delete_push_subscription(p_endpoint text)
returns void
language sql security definer set search_path = public
as $$
    delete from public.push_subscriptions where endpoint = p_endpoint and user_id = auth.uid();
$$;

-- ---------------------------------------------------------------------
-- Edge Function aufrufen (asynchron, blockiert nie die eigentliche Aktion)
-- ---------------------------------------------------------------------
create or replace function public.notify_push(p_type text, p_request_id uuid)
returns void
language plpgsql security definer set search_path = public, extensions
as $$
declare
    v_url    text;
    v_secret text;
begin
    select decrypted_secret into v_url    from vault.decrypted_secrets where name = 'project_url';
    select decrypted_secret into v_secret from vault.decrypted_secrets where name = 'push_webhook_secret';
    if v_url is null or v_secret is null then
        return; -- Push nicht eingerichtet
    end if;

    perform net.http_post(
        url     := rtrim(v_url, '/') || '/functions/v1/send-push',
        headers := jsonb_build_object('Content-Type', 'application/json', 'x-webhook-secret', v_secret),
        body    := jsonb_build_object('type', p_type, 'request_id', p_request_id)
    );
exception when others then
    raise warning 'Push-Benachrichtigung konnte nicht ausgelöst werden: %', sqlerrm;
end;
$$;

-- ---------------------------------------------------------------------
-- Trigger auf bet_requests
-- ---------------------------------------------------------------------
create or replace function public.bet_requests_push_trigger()
returns trigger
language plpgsql security definer set search_path = public
as $$
begin
    if tg_op = 'INSERT' then
        perform public.notify_push('request_created', new.id);
    elsif old.status = 'pending' and new.status in ('approved', 'rejected') then
        perform public.notify_push('request_reviewed', new.id);
    end if;
    return new;
end;
$$;

drop trigger if exists bet_requests_push on public.bet_requests;
create trigger bet_requests_push
    after insert or update of status on public.bet_requests
    for each row execute function public.bet_requests_push_trigger();

-- ---------------------------------------------------------------------
-- Rechte
-- ---------------------------------------------------------------------
revoke execute on function public.save_push_subscription(text, text, text, text) from public, anon;
revoke execute on function public.delete_push_subscription(text)               from public, anon;
revoke execute on function public.notify_push(text, uuid)                       from public, anon, authenticated;
revoke execute on function public.bet_requests_push_trigger()                   from public, anon, authenticated;
grant  execute on function public.save_push_subscription(text, text, text, text) to authenticated;
grant  execute on function public.delete_push_subscription(text)               to authenticated;

notify pgrst, 'reload schema';
