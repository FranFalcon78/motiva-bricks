import { AdBridge } from "./ad-bridge.js";
import { AudioEngine } from "./audio.js";
import { MotivaBricksGame } from "./game.js";
import { generateLevelBricks } from "./level-generator.js";
import { LevelRepository } from "./level-loader.js";
import { formatScore } from "./utils.js";

const ui = {
  canvas: document.querySelector("#gameCanvas"),
  menuButton: document.querySelector("#menuButton"),
  pauseButton: document.querySelector("#pauseButton"),
  menuScreen: document.querySelector("#menuScreen"),
  pauseScreen: document.querySelector("#pauseScreen"),
  resultScreen: document.querySelector("#resultScreen"),
  adInterstitial: document.querySelector("#adInterstitial"),
  closeAdButton: document.querySelector("#closeAdButton"),
  adCountdown: document.querySelector("#adCountdown"),
  bannerAd: document.querySelector("#bannerAd"),
  levelGrid: document.querySelector("#levelGrid"),
  levelLabel: document.querySelector("#levelLabel"),
  levelSource: document.querySelector("#levelSource"),
  levelSourceDot: document.querySelector("#levelSourceDot"),
  livesDisplay: document.querySelector("#livesDisplay"),
  scoreDisplay: document.querySelector("#scoreDisplay"),
  brickCounter: document.querySelector("#brickCounter"),
  statusText: document.querySelector("#statusText"),
  progressFill: document.querySelector("#progressFill"),
  toast: document.querySelector("#toast"),
  resumeButton: document.querySelector("#resumeButton"),
  restartFromPauseButton: document.querySelector("#restartFromPauseButton"),
  menuFromPauseButton: document.querySelector("#menuFromPauseButton"),
  resultEyebrow: document.querySelector("#resultEyebrow"),
  resultTitle: document.querySelector("#resultTitle"),
  resultScore: document.querySelector("#resultScore"),
  resultStars: document.querySelector("#resultStars"),
  nextLevelButton: document.querySelector("#nextLevelButton"),
  retryButton: document.querySelector("#retryButton"),
  menuFromResultButton: document.querySelector("#menuFromResultButton"),
};

const audio = new AudioEngine();
const repository = new LevelRepository();
let adBridge = null;
let selectedLevel = null;
let toastTimer = null;
let endFlowRunning = false;

function setOverlayVisible(element, visible) {
  element.classList.toggle("hidden", !visible);
  element.setAttribute("aria-hidden", visible ? "false" : "true");
}

function showToast(message, duration = 1900) {
  window.clearTimeout(toastTimer);
  ui.toast.textContent = message;
  ui.toast.classList.remove("hidden");
  toastTimer = window.setTimeout(() => ui.toast.classList.add("hidden"), duration);
}

function renderLives(count) {
  const safeCount = Math.max(0, Math.min(5, Number(count) || 0));
  const full = "❤️".repeat(safeCount);
  const empty = "♡".repeat(Math.max(0, 3 - safeCount));
  ui.livesDisplay.textContent = `${full}${empty}`;
}

function updateHud(hud) {
  ui.levelLabel.textContent = hud.levelName || "Motiva Bricks";
  renderLives(hud.lives);
  ui.scoreDisplay.textContent = hud.formattedScore;
  ui.brickCounter.textContent = `${hud.destroyed} / ${hud.total}`;
  ui.statusText.textContent = hud.status;
  ui.progressFill.style.width = `${Math.round(hud.progress * 100)}%`;
}

const game = new MotivaBricksGame(ui.canvas, audio, {
  onHud: updateHud,
  onToast: showToast,
  onPauseChanged: (paused) => {
    setOverlayVisible(ui.pauseScreen, paused);
  },
  onEnd: async (result) => {
    if (endFlowRunning) return;
    endFlowRunning = true;
    ui.pauseButton.classList.add("in-menu");
    saveBestScore(result.level.id, result.score);

    await adBridge?.showInterstitial();
    showResult(result);
    endFlowRunning = false;
  },
});

function saveBestScore(levelId, score) {
  try {
    const key = `motiva-bricks-best-${levelId}`;
    const previous = Number(localStorage.getItem(key) || 0);
    if (score > previous) localStorage.setItem(key, String(score));
  } catch {
    // El juego sigue funcionando aunque el navegador bloquee localStorage.
  }
}

function getBestScore(levelId) {
  try {
    return Number(localStorage.getItem(`motiva-bricks-best-${levelId}`) || 0);
  } catch {
    return 0;
  }
}

function createLevelButton(level, index) {
  const generated = generateLevelBricks(level);
  const button = document.createElement("button");
  button.type = "button";
  button.className = "level-button";
  button.setAttribute("aria-label", `Jugar ${level.name}`);

  const palette = level.theme?.palette ?? ["#ff4f87", "#ff9d32"];
  const swatchA = palette[0] ?? "#ff4f87";
  const swatchB = palette.at(-1) ?? "#ff9d32";
  const best = getBestScore(level.id);
  const detail = `${generated.totalCount} bloques · ${level.difficulty ?? "Demo"}${best ? ` · Record ${formatScore(best)}` : ""}`;

  button.innerHTML = `
    <span class="level-number">${String(index + 1).padStart(2, "0")}</span>
    <span class="level-name">${level.name}</span>
    <span class="level-detail">${detail}</span>
    <span class="level-swatch" aria-hidden="true"></span>
  `;
  const swatch = button.querySelector(".level-swatch");
  swatch.style.background = `linear-gradient(145deg, ${swatchA}, ${swatchB})`;
  button.addEventListener("click", () => startLevel(level));
  return button;
}

function renderLevelMenu() {
  ui.levelGrid.replaceChildren();
  repository.levels.forEach((level, index) => {
    ui.levelGrid.append(createLevelButton(level, index));
  });

  const remote = repository.source === "remote";
  ui.levelSourceDot.classList.toggle("remote", remote);
  ui.levelSource.textContent = remote
    ? "Escenarios cargados desde el servidor remoto"
    : "5 escenarios locales de muestra (modo sin conexion)";
}

function startLevel(level) {
  selectedLevel = level;
  endFlowRunning = false;
  setOverlayVisible(ui.menuScreen, false);
  setOverlayVisible(ui.pauseScreen, false);
  setOverlayVisible(ui.resultScreen, false);
  ui.pauseButton.classList.remove("in-menu");
  game.loadLevel(level);
  showToast(`${level.name}: toca la pantalla para lanzar`, 2300);
}

function showMenu() {
  selectedLevel = null;
  endFlowRunning = false;
  game.enterMenu();
  setOverlayVisible(ui.menuScreen, true);
  setOverlayVisible(ui.pauseScreen, false);
  setOverlayVisible(ui.resultScreen, false);
  ui.pauseButton.classList.add("in-menu");
  ui.levelLabel.textContent = "Seleccion de escenarios";
  ui.statusText.textContent = "Preparado";
}

function showResult(result) {
  ui.resultEyebrow.textContent = result.won ? "NIVEL COMPLETADO" : "FIN DE LA PARTIDA";
  ui.resultTitle.textContent = result.won ? `${result.level.name} superado` : "El foso gano esta vez";
  ui.resultScore.textContent = formatScore(result.score);
  ui.resultStars.innerHTML = [1, 2, 3]
    .map((star) => `<span class="${star <= result.stars ? "" : "empty"}">★</span>`)
    .join(" ");
  ui.nextLevelButton.hidden = !result.won;
  setOverlayVisible(ui.resultScreen, true);
  renderLevelMenu();
}

function showLoadError(error) {
  ui.levelGrid.innerHTML = `
    <div class="dialog-card" style="grid-column:1/-1; padding:18px; text-align:left">
      <p class="eyebrow">NO SE PUDIERON CARGAR LOS NIVELES</p>
      <p style="color:var(--muted); line-height:1.5; font-size:13px; margin:0 0 12px">
        Abre el proyecto con <strong>start-windows.bat</strong> o ejecuta <strong>npm start</strong>. Los navegadores bloquean los JSON cuando se abre index.html directamente.
      </p>
      <code style="display:block; overflow-wrap:anywhere; color:var(--yellow); font-size:10px">${String(error.message ?? error)}</code>
    </div>
  `;
  ui.levelSource.textContent = "Servidor local no disponible";
  ui.levelSourceDot.classList.remove("remote");
}

ui.menuButton.addEventListener("click", showMenu);
ui.pauseButton.addEventListener("click", () => game.pause());
ui.resumeButton.addEventListener("click", () => game.resume());
ui.restartFromPauseButton.addEventListener("click", () => {
  setOverlayVisible(ui.pauseScreen, false);
  game.restartLevel();
  showToast("Nivel reiniciado");
});
ui.menuFromPauseButton.addEventListener("click", showMenu);
ui.retryButton.addEventListener("click", () => {
  if (selectedLevel) startLevel(selectedLevel);
});
ui.nextLevelButton.addEventListener("click", () => {
  const next = repository.getNextLevel(selectedLevel?.id);
  if (next) startLevel(next);
});
ui.menuFromResultButton.addEventListener("click", showMenu);

// Utilidades temporales para probar el prototipo desde la consola del navegador.
// Se pueden retirar antes de publicar la version de produccion.
window.MotivaBricksDev = Object.freeze({
  start(levelId) {
    const level = repository.getLevelById(levelId) ?? repository.getLevelAt(0);
    if (level) startLevel(level);
  },
  powerup(type) {
    if (["triple", "wide", "shield"].includes(type)) game.applyPowerup(type);
  },
  win() {
    if (game.level) game.finish(true);
  },
  lose() {
    if (game.level) game.finish(false);
  },
  stats() {
    return {
      state: game.state,
      level: game.level?.id ?? null,
      balls: game.balls.length,
      bricksRemaining: game.remainingDestructible,
      score: game.score,
    };
  },
});

async function bootstrap() {
  ui.pauseButton.classList.add("in-menu");
  try {
    await repository.load();
    adBridge = new AdBridge({
      overlay: ui.adInterstitial,
      closeButton: ui.closeAdButton,
      countdownLabel: ui.adCountdown,
      banner: ui.bannerAd,
      config: repository.config.ads,
    });
    adBridge.showBanner();
    renderLevelMenu();
    ui.levelLabel.textContent = "Seleccion de escenarios";

    const requestedLevelId = new URLSearchParams(window.location.search).get("level");
    const requestedLevel = requestedLevelId ? repository.getLevelById(requestedLevelId) : null;
    if (requestedLevel) startLevel(requestedLevel);
  } catch (error) {
    console.error(error);
    showLoadError(error);
  }

  if ("serviceWorker" in navigator) {
    const isLocalDevelopment = ["127.0.0.1", "localhost"].includes(window.location.hostname);
    if (isLocalDevelopment) {
      navigator.serviceWorker.getRegistrations().then((registrations) => {
        registrations.forEach((registration) => registration.unregister());
      }).catch(() => {});
    } else if (window.location.protocol === "https:") {
      navigator.serviceWorker.register("./service-worker.js").catch((error) => {
        console.warn("Service worker no registrado", error);
      });
    }
  }
}

bootstrap();
