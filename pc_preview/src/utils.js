export const clamp = (value, min, max) => Math.min(max, Math.max(min, value));

export const lerp = (from, to, amount) => from + (to - from) * amount;

export const mapRange = (value, inMin, inMax, outMin, outMax) => {
  if (inMax === inMin) return outMin;
  const normalized = (value - inMin) / (inMax - inMin);
  return outMin + normalized * (outMax - outMin);
};

export const rotateVector = (x, y, radians) => ({
  x: x * Math.cos(radians) - y * Math.sin(radians),
  y: x * Math.sin(radians) + y * Math.cos(radians),
});

export function createSeededRandom(seedInput = 1) {
  let seed = Number(seedInput) >>> 0;
  if (!seed) seed = 1;

  return function random() {
    seed += 0x6D2B79F5;
    let value = seed;
    value = Math.imul(value ^ (value >>> 15), value | 1);
    value ^= value + Math.imul(value ^ (value >>> 7), value | 61);
    return ((value ^ (value >>> 14)) >>> 0) / 4294967296;
  };
}

export function hashString(text = "") {
  let hash = 2166136261;
  for (let index = 0; index < text.length; index += 1) {
    hash ^= text.charCodeAt(index);
    hash = Math.imul(hash, 16777619);
  }
  return hash >>> 0;
}

export function circleIntersectsRect(circle, rect) {
  const nearestX = clamp(circle.x, rect.x, rect.x + rect.w);
  const nearestY = clamp(circle.y, rect.y, rect.y + rect.h);
  const dx = circle.x - nearestX;
  const dy = circle.y - nearestY;
  return dx * dx + dy * dy <= circle.r * circle.r;
}

export function resolveCircleRectCollision(ball, rect) {
  if (!circleIntersectsRect(ball, rect)) return null;

  const leftPenetration = Math.abs((ball.x + ball.r) - rect.x);
  const rightPenetration = Math.abs((rect.x + rect.w) - (ball.x - ball.r));
  const topPenetration = Math.abs((ball.y + ball.r) - rect.y);
  const bottomPenetration = Math.abs((rect.y + rect.h) - (ball.y - ball.r));

  const minimum = Math.min(leftPenetration, rightPenetration, topPenetration, bottomPenetration);

  if (minimum === leftPenetration) {
    return { axis: "x", normal: -1, overlap: leftPenetration };
  }
  if (minimum === rightPenetration) {
    return { axis: "x", normal: 1, overlap: rightPenetration };
  }
  if (minimum === topPenetration) {
    return { axis: "y", normal: -1, overlap: topPenetration };
  }
  return { axis: "y", normal: 1, overlap: bottomPenetration };
}

export function formatScore(score) {
  return Math.max(0, Math.round(score)).toLocaleString("es-ES");
}

export function safeJsonParse(value, fallback = null) {
  try {
    return JSON.parse(value);
  } catch {
    return fallback;
  }
}

export function weightedChoice(random, weightedEntries) {
  const total = weightedEntries.reduce((sum, entry) => sum + Math.max(0, entry.weight), 0);
  if (total <= 0) return weightedEntries[0]?.value ?? null;
  let cursor = random() * total;
  for (const entry of weightedEntries) {
    cursor -= Math.max(0, entry.weight);
    if (cursor <= 0) return entry.value;
  }
  return weightedEntries.at(-1)?.value ?? null;
}

export function normalizeHexColor(color, fallback = "#ffffff") {
  if (typeof color !== "string") return fallback;
  return /^#[0-9a-f]{6}$/i.test(color.trim()) ? color.trim() : fallback;
}

export function hexToRgb(hex) {
  const normalized = normalizeHexColor(hex).slice(1);
  return {
    r: Number.parseInt(normalized.slice(0, 2), 16),
    g: Number.parseInt(normalized.slice(2, 4), 16),
    b: Number.parseInt(normalized.slice(4, 6), 16),
  };
}

export function rgba(hex, alpha = 1) {
  const { r, g, b } = hexToRgb(hex);
  return `rgba(${r}, ${g}, ${b}, ${alpha})`;
}

export function roundRectPath(context, x, y, width, height, radius = 4) {
  const safeRadius = Math.min(radius, width / 2, height / 2);
  context.beginPath();
  context.moveTo(x + safeRadius, y);
  context.arcTo(x + width, y, x + width, y + height, safeRadius);
  context.arcTo(x + width, y + height, x, y + height, safeRadius);
  context.arcTo(x, y + height, x, y, safeRadius);
  context.arcTo(x, y, x + width, y, safeRadius);
  context.closePath();
}
