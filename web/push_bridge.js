(function () {
  const isIOS = /iPad|iPhone|iPod/.test(navigator.userAgent) ||
    (navigator.platform === "MacIntel" && navigator.maxTouchPoints > 1);
  const standalone = window.matchMedia("(display-mode: standalone)").matches ||
    window.navigator.standalone === true;

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
    requestPermission() {
      return Notification.requestPermission();
    },
    async subscribe(applicationServerKey) {
      const registration = await navigator.serviceWorker.ready;
      let subscription = await registration.pushManager.getSubscription();
      if (!subscription) {
        const padding = "=".repeat((4 - applicationServerKey.length % 4) % 4);
        const raw = atob((applicationServerKey + padding)
          .replace(/-/g, "+").replace(/_/g, "/"));
        const bytes = Uint8Array.from(raw, (character) => character.charCodeAt(0));
        subscription = await registration.pushManager.subscribe({
          userVisibleOnly: true,
          applicationServerKey: bytes,
        });
      }
      return JSON.stringify(subscription.toJSON());
    },
    async unsubscribe() {
      const registration = await navigator.serviceWorker.ready;
      const subscription = await registration.pushManager.getSubscription();
      return subscription ? subscription.unsubscribe() : true;
    },
  };
})();
