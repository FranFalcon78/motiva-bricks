export class AdBridge {
  constructor({ overlay, closeButton, countdownLabel, banner, config = {} }) {
    this.overlay = overlay;
    this.closeButton = closeButton;
    this.countdownLabel = countdownLabel;
    this.banner = banner;
    this.config = {
      desktopSimulation: true,
      interstitialSeconds: 3,
      ...config,
    };
    this.pendingResolve = null;
    this.timer = null;

    this.closeButton?.addEventListener("click", () => this.closeInterstitial());
  }

  showBanner() {
    if (!this.banner) return;
    this.banner.hidden = false;
  }

  hideBanner() {
    if (!this.banner) return;
    this.banner.hidden = true;
  }

  async showInterstitial() {
    // Punto de sustitucion para Android:
    // al integrar Capacitor + AdMob, esta funcion llamara al anuncio nativo real.
    if (!this.config.desktopSimulation || !this.overlay) return;
    if (this.pendingResolve) return;

    const seconds = Math.max(1, Math.round(this.config.interstitialSeconds ?? 3));
    let remaining = seconds;
    this.overlay.classList.remove("hidden");
    this.overlay.setAttribute("aria-hidden", "false");
    this.closeButton.disabled = true;
    this.countdownLabel.textContent = String(remaining);

    return new Promise((resolve) => {
      this.pendingResolve = resolve;
      this.timer = window.setInterval(() => {
        remaining -= 1;
        if (remaining <= 0) {
          window.clearInterval(this.timer);
          this.timer = null;
          this.closeButton.disabled = false;
          this.closeButton.innerHTML = "Continuar";
        } else {
          this.countdownLabel.textContent = String(remaining);
        }
      }, 1000);
    });
  }

  closeInterstitial() {
    if (!this.pendingResolve || this.closeButton?.disabled) return;
    this.overlay.classList.add("hidden");
    this.overlay.setAttribute("aria-hidden", "true");
    this.closeButton.innerHTML = 'Continuar en <span id="adCountdown">3</span>';
    this.countdownLabel = this.closeButton.querySelector("span");
    const resolve = this.pendingResolve;
    this.pendingResolve = null;
    resolve();
  }
}
