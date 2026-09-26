{{flutter_js}}
{{flutter_build_config}}

_flutter.loader.load({
  config: { canvasKitBaseUrl: "/canvaskit/" },
  onEntrypointLoaded: async function (engineInitializer) {
    const appRunner = await engineInitializer.initializeEngine();
    await appRunner.runApp();
    if ("serviceWorker" in navigator) {
      try {
        const registration = await navigator.serviceWorker.register("/service-worker.js", {
          scope: "/",
        });
        const offerUpdate = (worker) => {
          if (!worker || document.getElementById("forett-update")) return;
          const button = document.createElement("button");
          button.id = "forett-update";
          button.textContent = "Update available · Update";
          button.style.cssText = "position:fixed;left:16px;right:16px;bottom:80px;z-index:9999;padding:14px;border:0;border-radius:12px;background:#355f8a;color:white;font:600 16px system-ui;box-shadow:0 4px 16px #0005";
          button.addEventListener("click", () => worker.postMessage("SKIP_WAITING"));
          document.body.appendChild(button);
        };
        if (registration.waiting) offerUpdate(registration.waiting);
        registration.addEventListener("updatefound", () => {
          const worker = registration.installing;
          worker?.addEventListener("statechange", () => {
            if (worker.state === "installed" && navigator.serviceWorker.controller) {
              offerUpdate(worker);
            }
          });
        });
        navigator.serviceWorker.addEventListener("controllerchange", () => {
          window.location.reload();
        });
      } catch (error) {
        console.warn("Offline and push service worker registration failed");
      }
    }
  },
});
