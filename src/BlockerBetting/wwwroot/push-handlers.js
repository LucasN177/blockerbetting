// Push notification handlers, shared by service-worker.js (dev) and service-worker.published.js.
// Payload (from supabase/functions/send-push): { title, body, url, tag }

self.addEventListener('push', event => {
    let data = {};
    try {
        data = event.data ? event.data.json() : {};
    } catch {
        data = { body: event.data ? event.data.text() : '' };
    }

    event.waitUntil(self.registration.showNotification(data.title || 'BlockerBetting', {
        body: data.body || '',
        icon: 'icon-192.png',
        tag: data.tag,
        renotify: !!data.tag,
        data: { url: data.url || './' },
    }));
});

// Tapping a notification focuses an open app window (and navigates it) or opens a new one.
self.addEventListener('notificationclick', event => {
    event.notification.close();
    const target = new URL((event.notification.data && event.notification.data.url) || './', self.registration.scope).href;

    event.waitUntil((async () => {
        const windows = await self.clients.matchAll({ type: 'window', includeUncontrolled: true });
        for (const client of windows) {
            if (client.url.startsWith(self.registration.scope) && 'focus' in client) {
                await client.focus();
                if ('navigate' in client) {
                    try { await client.navigate(target); } catch { /* uncontrolled window – just focus it */ }
                }
                return;
            }
        }
        await self.clients.openWindow(target);
    })());
});
