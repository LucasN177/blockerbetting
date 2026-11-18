-- =====================================================================
-- BlockerBetting – Migration 009: Öffentlicher Chat
-- Im Supabase SQL Editor ausführen, NACH 001–008.
--
-- Ein einziger, öffentlicher Chatraum für alle angemeldeten Spieler.
-- Lesen dürfen alle angemeldeten Spieler direkt; geschrieben wird nur über
-- die Funktion post_chat_message, die Absender und Länge serverseitig festlegt.
-- (Noch kein Realtime – die App lädt neue Nachrichten per Aktualisieren.)
-- =====================================================================

create table if not exists public.chat_messages (
    id         uuid        primary key default gen_random_uuid(),
    user_id    uuid        not null references public.profiles(id) on delete cascade,
    body       text        not null check (char_length(body) between 1 and 500),
    created_at timestamptz not null default now()
);

create index if not exists chat_messages_created_at_idx on public.chat_messages (created_at desc);

alter table public.chat_messages enable row level security;

drop policy if exists "chat readable by players" on public.chat_messages;
create policy "chat readable by players" on public.chat_messages
    for select to authenticated using (true);

-- Keine Insert/Update/Delete-Policies: Schreiben nur über die Funktion unten.

create or replace function public.post_chat_message(p_body text)
returns uuid
language plpgsql security definer set search_path = public
as $$
declare
    v_body text := btrim(coalesce(p_body, ''));
    v_id   uuid;
begin
    if auth.uid() is null then
        raise exception 'Nicht angemeldet.';
    end if;
    if char_length(v_body) = 0 then
        raise exception 'Die Nachricht ist leer.';
    end if;
    if char_length(v_body) > 500 then
        raise exception 'Nachrichten dürfen höchstens 500 Zeichen lang sein.';
    end if;

    insert into public.chat_messages (user_id, body) values (auth.uid(), v_body)
    returning id into v_id;
    return v_id;
end;
$$;

revoke execute on function public.post_chat_message(text) from public, anon;
grant  execute on function public.post_chat_message(text) to authenticated;

notify pgrst, 'reload schema';
