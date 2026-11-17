// Supabase Edge Function: sends Web Push notifications for bet requests.
//
// Called by the database (migration 005, pg_net) with
//   POST { "type": "request_created" | "request_reviewed", "request_id": "<uuid>" }
//   Header x-webhook-secret: <PUSH_WEBHOOK_SECRET>
//
// Secrets (supabase secrets set ...):
//   VAPID_PUBLIC_KEY, VAPID_PRIVATE_KEY, VAPID_SUBJECT (e.g. mailto:admin@example.com), PUSH_WEBHOOK_SECRET
// SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are provided by Supabase automatically.
//
// Deploy without JWT verification (the shared secret protects it):
//   supabase functions deploy send-push --no-verify-jwt

import { createClient } from "npm:@supabase/supabase-js@2.45.4";
import webpush from "npm:web-push@3.6.7";

type Payload = { title: string; body: string; url: string; tag: string };

const env = (name: string) => {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`Missing secret ${name}`);
  return value;
};

webpush.setVapidDetails(env("VAPID_SUBJECT"), env("VAPID_PUBLIC_KEY"), env("VAPID_PRIVATE_KEY"));

const supabase = createClient(env("SUPABASE_URL"), env("SUPABASE_SERVICE_ROLE_KEY"), {
  auth: { persistSession: false },
});

Deno.serve(async (req) => {
  if (req.method !== "POST") return new Response("Method not allowed", { status: 405 });
  if (req.headers.get("x-webhook-secret") !== env("PUSH_WEBHOOK_SECRET")) {
    return new Response("Unauthorized", { status: 401 });
  }

  let type: string, requestId: string;
  try {
    ({ type, request_id: requestId } = await req.json());
  } catch {
    return new Response("Invalid JSON", { status: 400 });
  }

  const { data: request, error } = await supabase
    .from("bet_requests")
    .select("id, title, status, admin_note, event_id, requested_by")
    .eq("id", requestId)
    .single();
  if (error || !request) return json({ sent: 0, reason: "request not found" }, 404);

  let recipients: string[] = [];
  let payload: Payload;

  if (type === "request_created") {
    const { data: requester } = await supabase
      .from("profiles").select("display_name").eq("id", request.requested_by).single();
    const { data: admins } = await supabase.from("profiles").select("id").eq("is_admin", true);
    recipients = (admins ?? []).map((a) => a.id).filter((id) => id !== request.requested_by);
    payload = {
      title: "Neue Wett-Anfrage",
      body: `${requester?.display_name ?? "Jemand"} schlägt vor: „${request.title}“`,
      url: `admin/requests/${request.id}`,
      tag: `request-${request.id}`,
    };
  } else if (type === "request_reviewed" && (request.status === "approved" || request.status === "rejected")) {
    recipients = [request.requested_by];
    payload = request.status === "approved"
      ? {
        title: "Dein Vorschlag wurde angenommen 🎉",
        body: `„${request.title}“ ist jetzt online.`,
        url: request.event_id ? `events/${request.event_id}` : "requests",
        tag: `request-${request.id}`,
      }
      : {
        title: "Dein Vorschlag wurde abgelehnt",
        body: request.admin_note ? `„${request.title}“ – ${request.admin_note}` : `„${request.title}“ wurde nicht freigegeben.`,
        url: "requests",
        tag: `request-${request.id}`,
      };
  } else {
    return json({ sent: 0, reason: "nothing to send" });
  }

  if (recipients.length === 0) return json({ sent: 0, reason: "no recipients" });

  const { data: subscriptions } = await supabase
    .from("push_subscriptions")
    .select("id, endpoint, p256dh, auth")
    .in("user_id", recipients);

  let sent = 0;
  const expired: string[] = [];
  await Promise.all((subscriptions ?? []).map(async (s) => {
    try {
      await webpush.sendNotification(
        { endpoint: s.endpoint, keys: { p256dh: s.p256dh, auth: s.auth } },
        JSON.stringify(payload),
        { TTL: 60 * 60 * 24, urgency: "normal" },
      );
      sent++;
    } catch (e) {
      const status = (e as { statusCode?: number }).statusCode;
      // 404/410: the browser revoked the subscription – forget the device.
      if (status === 404 || status === 410) expired.push(s.id);
      else console.error("Push failed", status, (e as Error).message);
    }
  }));

  if (expired.length > 0) await supabase.from("push_subscriptions").delete().in("id", expired);

  return json({ sent, expired: expired.length });
});

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}
