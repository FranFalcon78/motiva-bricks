export class AudioEngine {
  constructor() {
    this.context = null;
    this.enabled = true;
    this.lastBrickToneAt = 0;
  }

  ensureContext() {
    if (!this.enabled) return null;
    if (!this.context) {
      const AudioContextClass = window.AudioContext || window.webkitAudioContext;
      if (!AudioContextClass) return null;
      this.context = new AudioContextClass();
    }
    if (this.context.state === "suspended") {
      this.context.resume().catch(() => {});
    }
    return this.context;
  }

  tone(frequency = 440, duration = 0.05, volume = 0.03, type = "sine", delay = 0) {
    const context = this.ensureContext();
    if (!context) return;

    const start = context.currentTime + delay;
    const oscillator = context.createOscillator();
    const gain = context.createGain();
    oscillator.type = type;
    oscillator.frequency.setValueAtTime(frequency, start);
    gain.gain.setValueAtTime(0.0001, start);
    gain.gain.exponentialRampToValueAtTime(Math.max(0.0001, volume), start + 0.008);
    gain.gain.exponentialRampToValueAtTime(0.0001, start + duration);
    oscillator.connect(gain);
    gain.connect(context.destination);
    oscillator.start(start);
    oscillator.stop(start + duration + 0.02);
  }

  wall() {
    this.tone(260, 0.025, 0.018, "square");
  }

  paddle() {
    this.tone(420, 0.04, 0.028, "triangle");
  }

  brick(hard = false) {
    const now = performance.now();
    if (now - this.lastBrickToneAt < 22) return;
    this.lastBrickToneAt = now;
    this.tone(hard ? 185 : 540, hard ? 0.05 : 0.035, 0.022, hard ? "square" : "triangle");
  }

  powerup() {
    this.tone(660, 0.08, 0.035, "sine");
    this.tone(880, 0.1, 0.03, "sine", 0.06);
  }

  lifeLost() {
    this.tone(210, 0.15, 0.04, "sawtooth");
    this.tone(145, 0.2, 0.035, "sawtooth", 0.08);
  }

  win() {
    [523, 659, 784, 1047].forEach((frequency, index) => {
      this.tone(frequency, 0.18, 0.035, "triangle", index * 0.09);
    });
  }

  gameOver() {
    [330, 262, 196].forEach((frequency, index) => {
      this.tone(frequency, 0.22, 0.035, "sawtooth", index * 0.12);
    });
  }
}
