import { normalizeHexColor } from "./utils.js";

const DEFAULT_PALETTE = ["#ff4f2f", "#ff8a2b", "#ffe75b", "#28dfff", "#a855f7"];

const HASH_MODULUS = 2147483647;
const HASH_MULTIPLIER = 48271;

function cellRandom(seed, x, y, salt) {
  let value = Math.abs(Math.trunc(Number(seed))) % HASH_MODULUS;
  value = (value + (x + 1) * 73856093 + (y + 1) * 19349663 + (salt + 1) * 83492791) % HASH_MODULUS;
  value = (value * HASH_MULTIPLIER + 1) % HASH_MODULUS;
  value = (value * HASH_MULTIPLIER + 1) % HASH_MODULUS;
  return value / HASH_MODULUS;
}

function isNear(value, target, tolerance) {
  return Math.abs(value - target) <= tolerance;
}

function patternNeonGates(x, y, cols, rows, randomValue) {
  const topBand = y <= 4;
  const outerWall = (x <= 1 || x >= cols - 2) && y >= 8;
  const lowerRail = y >= rows - 3;
  const columnWidth = 3;
  const columnStride = 7;
  const inColumn = y >= 9 && y <= rows - 7 && (x % columnStride) < columnWidth;
  const middleBridge = y >= Math.floor(rows * 0.46) && y <= Math.floor(rows * 0.46) + 2 && x > 5 && x < cols - 6;
  const deliberateGap = (Math.floor(x / columnStride) + Math.floor(y / 8)) % 5 === 0 && randomValue < 0.34;
  return (topBand || outerWall || lowerRail || inColumn || middleBridge) && !deliberateGap;
}

function patternConcentric(x, y, cols, rows, randomValue) {
  const distance = Math.min(x, cols - 1 - x, y, rows - 1 - y);
  const ring = distance % 5;
  const ringBrick = ring <= 1;
  const centerX = (cols - 1) / 2;
  const centerY = (rows - 1) / 2;
  const cross = (Math.abs(x - centerX) <= 1 || Math.abs(y - centerY) <= 1) && distance > 5;
  const gate = (
    (Math.abs(x - centerX) <= 2 && y < rows * 0.19) ||
    (Math.abs(y - centerY) <= 1 && x > cols * 0.78)
  );
  const texture = randomValue < 0.045 && distance > 3;
  return (ringBrick || cross || texture) && !gate;
}

function patternGuardian(x, y, cols, rows, randomValue) {
  const nx = x / (cols - 1);
  const ny = y / (rows - 1);
  const symmetryX = Math.abs(nx - 0.5);

  const helmet = ny < 0.17 && symmetryX < 0.46;
  const sideFrame = ny >= 0.14 && ny < 0.83 && symmetryX > 0.38 && symmetryX < 0.47;
  const faceFrame = ny > 0.17 && ny < 0.75 && symmetryX > 0.25 && symmetryX < 0.34;
  const eyeLeft = nx > 0.25 && nx < 0.42 && ny > 0.27 && ny < 0.43;
  const eyeRight = nx > 0.58 && nx < 0.75 && ny > 0.27 && ny < 0.43;
  const eyeCutLeft = nx > 0.30 && nx < 0.38 && ny > 0.31 && ny < 0.39;
  const eyeCutRight = nx > 0.62 && nx < 0.70 && ny > 0.31 && ny < 0.39;
  const nose = symmetryX < 0.08 && ny > 0.42 && ny < 0.61;
  const mouthFrame = nx > 0.25 && nx < 0.75 && ny > 0.56 && ny < 0.75;
  const mouthCut = nx > 0.34 && nx < 0.66 && ny > 0.61 && ny < 0.68;
  const jaw = ny > 0.72 && ny < 0.82 && symmetryX < 0.34;
  const circuit = ny > 0.18 && ny < 0.78 && ((x + y * 2) % 11 === 0) && randomValue > 0.25;

  return helmet || sideFrame || faceFrame ||
    ((eyeLeft && !eyeCutLeft) || (eyeRight && !eyeCutRight)) ||
    nose || (mouthFrame && !mouthCut) || jaw || circuit;
}

function patternCircuitMaze(x, y, cols, rows, randomValue) {
  const border = x <= 1 || x >= cols - 2 || y <= 1 || y >= rows - 2;
  const verticalTrack = x % 6 <= 1;
  const horizontalTrack = y % 7 <= 1;
  const checkerBlock = ((Math.floor(x / 6) + Math.floor(y / 7)) % 2 === 0);
  const track = (verticalTrack && checkerBlock) || (horizontalTrack && !checkerBlock);
  const gateChance = randomValue;
  const openGate = (verticalTrack || horizontalTrack) && gateChance < 0.12;
  const node = x % 6 <= 1 && y % 7 <= 1;
  return border || node || (track && !openGate);
}

function patternReactor(x, y, cols, rows, randomValue) {
  const cx = (cols - 1) / 2;
  const cy = (rows - 1) / 2;
  const dx = (x - cx) / (cols * 0.5);
  const dy = (y - cy) / (rows * 0.5);
  const radius = Math.sqrt(dx * dx + dy * dy);
  const angle = Math.atan2(dy, dx);
  const ringIndex = Math.floor(radius * 28);
  const ring = ringIndex % 4 <= 1 && radius < 0.96 && radius > 0.09;
  const spokePhase = Math.abs(Math.sin(angle * 6));
  const spoke = spokePhase < 0.16 && radius > 0.17 && radius < 0.9;
  const core = radius < 0.18 && (x + y) % 2 === 0;
  const fracture = randomValue < 0.035 && radius > 0.3;
  return ring || spoke || core || fracture;
}

function patternWaveTunnel(x, y, cols, rows, randomValue) {
  const nx = x / Math.max(1, cols - 1);
  const waveA = Math.sin(nx * Math.PI * 5.5) * 4 + rows * 0.27;
  const waveB = Math.cos(nx * Math.PI * 4.2) * 5 + rows * 0.54;
  const waveC = Math.sin(nx * Math.PI * 7.3 + 1.2) * 3 + rows * 0.76;
  const thickWave = isNear(y, waveA, 2) || isNear(y, waveB, 2) || isNear(y, waveC, 2);
  const ceiling = y < 3;
  const verticalSparks = x % 8 <= 1 && y > 4 && randomValue > 0.58;
  const edge = x <= 1 || x >= cols - 2;
  return ceiling || edge || thickWave || verticalSparks;
}

const PATTERNS = {
  "neon-gates": patternNeonGates,
  concentric: patternConcentric,
  guardian: patternGuardian,
  "circuit-maze": patternCircuitMaze,
  reactor: patternReactor,
  "wave-tunnel": patternWaveTunnel,
};

function choosePaletteColor(palette, x, y, cols, rows, patternType, maxHp) {
  const normalizedPalette = palette.length ? palette : DEFAULT_PALETTE;
  let index;

  if (patternType === "reactor") {
    const cx = (cols - 1) / 2;
    const cy = (rows - 1) / 2;
    const radius = Math.sqrt((x - cx) ** 2 + (y - cy) ** 2);
    index = Math.floor(radius / 3);
  } else if (patternType === "concentric") {
    index = Math.floor(Math.min(x, cols - 1 - x, y, rows - 1 - y) / 2);
  } else {
    index = Math.floor((x / cols) * normalizedPalette.length + (y / rows) * 2);
  }

  if (maxHp >= 3) index += 1;
  return normalizedPalette[Math.abs(index) % normalizedPalette.length];
}

export function generateLevelBricks(level, world = { width: 720, height: 1040 }) {
  const generator = level.generator ?? {};
  const cols = Math.max(18, Math.min(72, Math.round(generator.cols ?? 52)));
  const rows = Math.max(14, Math.min(56, Math.round(generator.rows ?? 38)));
  const gap = Math.max(1, Math.min(4, Number(generator.gap ?? 2)));
  const area = {
    x: Number(generator.x ?? 20),
    y: Number(generator.y ?? 25),
    width: Number(generator.width ?? (world.width - 40)),
    height: Number(generator.height ?? 610),
  };

  const cellWidth = area.width / cols;
  const cellHeight = Math.min(cellWidth, area.height / rows);
  const brickWidth = Math.max(4, cellWidth - gap);
  const brickHeight = Math.max(4, cellHeight - gap);
  const usedHeight = rows * cellHeight;
  const startY = area.y + Math.max(0, (area.height - usedHeight) * 0.08);
  const patternType = generator.pattern ?? "neon-gates";
  const pattern = PATTERNS[patternType] ?? PATTERNS["neon-gates"];
  const seed = Number(level.seed ?? generator.seed ?? 1);
  const palette = (level.theme?.palette ?? DEFAULT_PALETTE).map((color) => normalizeHexColor(color));
  const hardRate = Math.max(0, Math.min(0.6, Number(generator.hardRate ?? 0.16)));
  const veryHardRate = Math.max(0, Math.min(0.35, Number(generator.veryHardRate ?? 0.035)));
  const indestructibleRate = Math.max(0, Math.min(0.25, Number(generator.indestructibleRate ?? 0.025)));
  const structuralEvery = Math.max(0, Math.round(generator.structuralEvery ?? 0));
  const bricks = [];

  for (let y = 0; y < rows; y += 1) {
    for (let x = 0; x < cols; x += 1) {
      const patternRandom = cellRandom(seed, x, y, 0);
      if (!pattern(x, y, cols, rows, patternRandom)) continue;

      const roll = cellRandom(seed, x, y, 1);
      const isStructural = structuralEvery > 0 && ((x + y * cols) % structuralEvery === 0);
      const indestructible = isStructural || roll < indestructibleRate;
      let hp = 1;
      if (!indestructible) {
        const hpRoll = cellRandom(seed, x, y, 2);
        if (hpRoll < veryHardRate) hp = 3;
        else if (hpRoll < veryHardRate + hardRate) hp = 2;
      }

      const color = indestructible
        ? normalizeHexColor(level.theme?.indestructible ?? "#7f8491")
        : choosePaletteColor(palette, x, y, cols, rows, patternType, hp);

      bricks.push({
        id: `${level.id ?? "level"}-${x}-${y}`,
        gridX: x,
        gridY: y,
        x: area.x + x * cellWidth + gap / 2,
        y: startY + y * cellHeight + gap / 2,
        w: brickWidth,
        h: brickHeight,
        hp,
        maxHp: hp,
        indestructible,
        destroyed: false,
        color,
        hitFlash: 0,
      });
    }
  }

  return {
    bricks,
    columns: cols,
    rows,
    area,
    destructibleCount: bricks.filter((brick) => !brick.indestructible).length,
    totalCount: bricks.length,
  };
}

export function listSupportedPatterns() {
  return Object.keys(PATTERNS);
}
