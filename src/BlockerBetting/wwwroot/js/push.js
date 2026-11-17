// Browser side of push notifications, used by Services/PushService.cs.
window.bbPush = (function () {
    function base64UrlToUint8Array(value) {
        const padding = '='.repeat((4 - (value.length % 4)) % 4);
        const raw = atob((value + padding).replace(/-/g, '+').replace(/_/g, '/'));
        return Uint8Array.from(raw, c => c.charCodeAt(0));
    }

    function toDto(subscription) {
        const json = subscription.toJSON();
        return { endpoint: json.endpoint, p256dh: json.keys.p256dh, auth: json.keys.auth };
    }

    async function registration() {
        return await navigator.serviceWorker.ready;
    }

    return {
        state: async function () {
            const supported = 'serviceWorker' in navigator && 'PushManager' in window && 'Notification' in window;
            const ua = navigator.userAgent;
            const isIos = /iPad|iPhone|iPod/.test(ua) || (navigator.platform === 'MacIntel' && navigator.maxTouchPoints > 1);
            const isStandalone = window.matchMedia('(display-mode: standalone)').matches || navigator.standalone === true;
            let subscribed = false;
            if (supported) {
                try { subscribed = !!(await (await registration()).pushManager.getSubscription()); } catch { /* ignore */ }
            }
            return {
                supported,
                isIos,
                isStandalone,
                permission: 'Notification' in window ? Notification.permission : 'unsupported',
                subscribed,
                userAgent: ua,
            };
        },

        // Must be called from a user gesture (button click).
        subscribe: async function (vapidPublicKey) {
            const permission = await Notification.requestPermission();
            if (permission !== 'granted') return null;
            const reg = await registration();
            let subscription = await reg.pushManager.getSubscription();
            if (!subscription) {
                subscription = await reg.pushManager.subscribe({
                    userVisibleOnly: true,
                    applicationServerKey: base64UrlToUint8Array(vapidPublicKey),
                });
            }
            return toDto(subscription);
        },

        current: async function () {
            const subscription = await (await registration()).pushManager.getSubscription();
            return subscription ? toDto(subscription) : null;
        },

        unsubscribe: async function () {
            const subscription = await (await registration()).pushManager.getSubscription();
            if (!subscription) return null;
            const endpoint = subscription.endpoint;
            await subscription.unsubscribe();
            return endpoint;
        },
    };
})();
