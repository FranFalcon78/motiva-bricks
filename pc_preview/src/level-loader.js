const DEFAULT_CONFIG = {
  gameName: "Motiva Bricks",
  localLevelIndexUrl: "./levels/index.json",
  remoteLevelIndexUrl: "",
  preferRemote: true,
  requestTimeoutMs: 4000,
  ads: {
    desktopSimulation: true,
    interstitialSeconds: 3,
  },
};

async function fetchJson(url, timeoutMs = 4000) {
  const controller = new AbortController();
  const timer = window.setTimeout(() => controller.abort(), timeoutMs);
  try {
    const response = await fetch(url, {
      method: "GET",
      cache: "no-store",
      signal: controller.signal,
      headers: { Accept: "application/json" },
    });
    if (!response.ok) {
      throw new Error(`HTTP ${response.status} al cargar ${url}`);
    }
    return await response.json();
  } finally {
    window.clearTimeout(timer);
  }
}

function mergeConfig(config) {
  return {
    ...DEFAULT_CONFIG,
    ...(config ?? {}),
    ads: {
      ...DEFAULT_CONFIG.ads,
      ...(config?.ads ?? {}),
    },
  };
}

function resolveUrl(candidate, base = window.location.href) {
  return new URL(candidate, base).href;
}

function normalizeIndex(indexData) {
  if (!indexData || !Array.isArray(indexData.levels)) {
    throw new Error("El indice de niveles no contiene una lista 'levels' valida.");
  }
  return indexData;
}

async function resolveLevels(indexData, indexUrl, timeoutMs) {
  const normalized = normalizeIndex(indexData);
  const entries = normalized.levels;
  const levels = [];

  for (const entry of entries) {
    if (entry && typeof entry === "object" && entry.generator) {
      levels.push(entry);
      continue;
    }

    const path = typeof entry === "string" ? entry : entry?.path;
    if (!path) continue;
    const levelUrl = resolveUrl(path, indexUrl);
    const level = await fetchJson(levelUrl, timeoutMs);
    levels.push({ ...level, _sourceUrl: levelUrl });
  }

  if (!levels.length) {
    throw new Error("No se encontro ningun nivel valido.");
  }

  return levels
    .filter((level) => level && level.id && level.generator)
    .sort((a, b) => Number(a.order ?? 0) - Number(b.order ?? 0));
}

export class LevelRepository {
  constructor(configUrl = "./config/game-config.json") {
    this.configUrl = configUrl;
    this.config = mergeConfig(null);
    this.levels = [];
    this.source = "local";
    this.sourceUrl = "";
    this.lastError = null;
  }

  async load() {
    try {
      const loadedConfig = await fetchJson(resolveUrl(this.configUrl), DEFAULT_CONFIG.requestTimeoutMs);
      this.config = mergeConfig(loadedConfig);
    } catch (error) {
      console.warn("No se pudo cargar game-config.json; se usara la configuracion integrada.", error);
      this.config = mergeConfig(null);
    }

    const queryIndex = new URLSearchParams(window.location.search).get("levels");
    const remoteCandidate = queryIndex || this.config.remoteLevelIndexUrl;
    const candidates = [];

    if (remoteCandidate && this.config.preferRemote) {
      candidates.push({ type: "remote", url: resolveUrl(remoteCandidate) });
    }
    candidates.push({ type: "local", url: resolveUrl(this.config.localLevelIndexUrl) });
    if (remoteCandidate && !this.config.preferRemote) {
      candidates.push({ type: "remote", url: resolveUrl(remoteCandidate) });
    }

    const errors = [];
    for (const candidate of candidates) {
      try {
        const indexData = await fetchJson(candidate.url, this.config.requestTimeoutMs);
        const levels = await resolveLevels(indexData, candidate.url, this.config.requestTimeoutMs);
        this.levels = levels;
        this.source = candidate.type;
        this.sourceUrl = candidate.url;
        this.lastError = null;
        return this;
      } catch (error) {
        errors.push(`${candidate.type}: ${error.message}`);
      }
    }

    this.lastError = new Error(errors.join(" | "));
    throw this.lastError;
  }

  getLevelById(id) {
    return this.levels.find((level) => level.id === id) ?? null;
  }

  getLevelAt(index) {
    if (!this.levels.length) return null;
    const normalized = ((index % this.levels.length) + this.levels.length) % this.levels.length;
    return this.levels[normalized];
  }

  getNextLevel(currentId) {
    const index = this.levels.findIndex((level) => level.id === currentId);
    return this.getLevelAt(index < 0 ? 0 : index + 1);
  }
}
