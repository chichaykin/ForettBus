(function () {
  const isIOS = /iPad|iPhone|iPod/.test(navigator.userAgent) ||
    (navigator.platform === "MacIntel" && navigator.maxTouchPoints > 1);
  const standalone = window.matchMedia("(display-mode: standalone)").matches ||
    window.navigator.standalone === true;
  let activeRegistration = null;
  let registrationPromise = null;
  let existingSubscription = null;

  function withTimeout(promise, milliseconds, action) {
    let timer;
    return Promise.race([
      promise,
      new Promise((_, reject) => {
        timer = setTimeout(() => reject(new Error(`${action} timed out`)), milliseconds);
      }),
    ]).finally(() => clearTimeout(timer));
  }

  function readyRegistration() {
    if (!registrationPromise) {
      registrationPromise = withTimeout(
        navigator.serviceWorker.register("/service-worker.js", { scope: "/" }),
        12000,
        "Service worker registration",
      ).then((registration) => registration.active
        ? registration
        : withTimeout(navigator.serviceWorker.ready, 60000, "Service worker activation"))
        .then((registration) => {
          activeRegistration = registration;
          return registration;
        })
        .catch((error) => {
          registrationPromise = null;
          throw error;
        });
    }
    return registrationPromise;
  }

  // Prepare the registration before a user taps a notification control. WebKit
  // requires pushManager.subscribe() itself to start during that gesture.
  if ("serviceWorker" in navigator) readyRegistration().catch(() => {});

  window.forettPush = {
    isSupported() {
      return window.isSecureContext &&
        "serviceWorker" in navigator &&
        "PushManager" in window &&
        "Notification" in window;
    },
    isInstallRequired() {
      return isIOS && !standalone;
    },
    permission() {
      return "Notification" in window ? Notification.permission : "denied";
    },
    isWorkerReady() {
      return activeRegistration !== null;
    },
    async existingSubscription() {
      const registration = await readyRegistration();
      existingSubscription = await withTimeout(
        registration.pushManager.getSubscription(), 12000, "Push subscription lookup");
      return existingSubscription ? JSON.stringify(existingSubscription.toJSON()) : "";
    },
    subscribe(applicationServerKey) {
      if (!activeRegistration) {
        return Promise.reject(new Error("Push service is still starting"));
      }
      if (existingSubscription) {
        return Promise.resolve(JSON.stringify(existingSubscription.toJSON()));
      }
      const padding = "=".repeat((4 - applicationServerKey.length % 4) % 4);
      const raw = atob((applicationServerKey + padding)
        .replace(/-/g, "+").replace(/_/g, "/"));
      const bytes = Uint8Array.from(raw, (character) => character.charCodeAt(0));
      // Keep this call synchronous with the Flutter button tap. Awaiting a
      // network request or service worker Promise first loses iOS activation.
      return withTimeout(activeRegistration.pushManager.subscribe({
        userVisibleOnly: true,
        applicationServerKey: bytes,
      }), 25000, "Push subscription").then((subscription) => {
        existingSubscription = subscription;
        return JSON.stringify(subscription.toJSON());
      });
    },
    async unsubscribe() {
      const registration = await readyRegistration();
      const subscription = await withTimeout(
        registration.pushManager.getSubscription(), 12000, "Push subscription lookup");
      const removed = subscription
        ? withTimeout(subscription.unsubscribe(), 12000, "Push unsubscribe")
        : true;
      existingSubscription = null;
      return removed;
    },
  };
})();
