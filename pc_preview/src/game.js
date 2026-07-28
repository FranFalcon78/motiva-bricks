import { generateLevelBricks } from "./level-generator.js";
import {
  clamp,
  circleIntersectsRect,
  createSeededRandom,
  formatScore,
  lerp,
  resolveCircleRectCollision,
  rotateVector,
  roundRectPath,
  rgba,
  weightedChoice,
} from "./utils.js";

const WORLD = Object.freeze({ width: 720, height: 1040 });
const PADDLE_Y = 947;
const SHIELD_Y = 1015;
const MAX_BALLS = 30;

export class MotivaBricksGame {
  constructor(canvas, audio, callbacks = {}) {
    this.canvas = canvas;
    this.context = canvas.getContext("2d", { alpha: false, desynchronized: true });
    this.audio = audio;
    this.callbacks = {
      onHud: () => {},
      onToast: () => {},
      onEnd: () => {},
      onPauseChanged: () => {},
      ...callbacks,
    };

    this.world = WORLD;
    this.level = null;
    this.state = "menu";
    this.lastFrameTime = performance.now();
    this.animationFrame = null;
    this.gameClock = 0;
    this.score = 0;
    this.lives = 3;
    this.totalDestructible = 0;
    this.remainingDestructible = 0;
    this.bricks = [];
    this.balls = [];
    this.powerups = [];
    this.particles = [];
    this.backgroundStars = [];
    this.gameRandom = createSeededRandom(1);
    this.backgroundGradient = null;
    this.endTriggered = false;
    this.lastHudAt = 0;
    this.keys = { left: false, right: false };
    this.effects = { wideUntil: 0, shieldUntil: 0 };
    this.paddle = {
      x: WORLD.width / 2 - 76,
      y: PADDLE_Y,
      w: 152,
      h: 18,
      baseW: 152,
      targetW: 152,
      targetX: WORLD.width / 2,
      previousCenter: WORLD.width / 2,
      velocity: 0,
    };

    this.installInputHandlers();
    this.startLoop();
  }

  installInputHandlers() {
    const pointerToWorld = (event) => {
      const rect = this.canvas.getBoundingClientRect();
      return {
        x: ((event.clientX - rect.left) / rect.width) * this.world.width,
        y: ((event.clientY - rect.top) / rect.height) * this.world.height,
      };
    };

    this.canvas.addEventListener("pointerdown", (event) => {
      if (!this.level || this.state === "menu" || this.state === "ended" || this.state === "paused") return;
      this.audio?.ensureContext();
      const point = pointerToWorld(event);
      this.setPaddleTarget(point.x);
      this.launch();
      this.canvas.setPointerCapture?.(event.pointerId);
    });

    this.canvas.addEventListener("pointermove", (event) => {
      if (!this.level || this.state === "menu" || this.state === "ended") return;
      if (event.pointerType === "mouse" || event.buttons > 0 || event.pressure > 0) {
        const point = pointerToWorld(event);
        this.setPaddleTarget(point.x);
      }
    });

    window.addEventListener("keydown", (event) => {
      const key = event.key.toLowerCase();
      if (["arrowleft", "arrowright", " ", "a", "d", "p", "r"].includes(key)) {
        event.preventDefault();
      }
      if (key === "arrowleft" || key === "a") this.keys.left = true;
      if (key === "arrowright" || key === "d") this.keys.right = true;
      if (key === " ") {
        this.audio?.ensureContext();
        this.launch();
      }
      if (key === "p") this.togglePause();
      if (key === "r" && this.level && this.state !== "menu") this.restartLevel();
    }, { passive: false });

    window.addEventListener("keyup", (event) => {
      const key = event.key.toLowerCase();
      if (key === "arrowleft" || key === "a") this.keys.left = false;
      if (key === "arrowright" || key === "d") this.keys.right = false;
    });

    document.addEventListener("visibilitychange", () => {
      if (document.hidden && (this.state === "running" || this.state === "ready")) {
        this.pause();
      }
    });
  }

  startLoop() {
    if (this.animationFrame) return;
    const frame = (time) => {
      const deltaMs = Math.min(40, Math.max(0, time - this.lastFrameTime));
      this.lastFrameTime = time;
      const frameScale = deltaMs / (1000 / 60);

      if (this.state === "running" || this.state === "ready") {
        this.update(frameScale, deltaMs / 1000);
      } else {
        this.updateVisualOnly(frameScale);
      }
      this.draw();
      this.animationFrame = requestAnimationFrame(frame);
    };
    this.animationFrame = requestAnimationFrame(frame);
  }

  loadLevel(level) {
    this.level = level;
    const generated = generateLevelBricks(level, this.world);
    this.bricks = generated.bricks;
    this.totalDestructible = generated.destructibleCount;
    this.remainingDestructible = generated.destructibleCount;
    this.gameRandom = createSeededRandom(Number(level.seed ?? 1) ^ 0x51f15e);
    this.score = 0;
    this.lives = Math.max(1, Math.round(level.rules?.lives ?? 3));
    this.gameClock = 0;
    this.endTriggered = false;
    this.powerups = [];
    this.particles = [];
    this.effects = { wideUntil: 0, shieldUntil: 0 };
    this.paddle.baseW = Math.max(100, Math.min(210, Number(level.physics?.paddleWidth ?? 152)));
    this.paddle.w = this.paddle.baseW;
    this.paddle.targetW = this.paddle.baseW;
    this.paddle.x = this.world.width / 2 - this.paddle.w / 2;
    this.paddle.targetX = this.world.width / 2;
    this.buildBackground();
    this.resetServe();
    this.state = "ready";
    this.emitHud(true);
  }

  buildBackground() {
    const theme = this.level?.theme ?? {};
    const top = theme.backgroundTop ?? "#190035";
    const bottom = theme.backgroundBottom ?? "#080015";
    const gradient = this.context.createLinearGradient(0, 0, 0, this.world.height);
    gradient.addColorStop(0, top);
    gradient.addColorStop(1, bottom);
    this.backgroundGradient = gradient;

    const random = createSeededRandom(Number(this.level?.seed ?? 1) ^ 0xa51c2);
    this.backgroundStars = Array.from({ length: 70 }, () => ({
      x: random() * this.world.width,
      y: random() * this.world.height,
      r: 0.5 + random() * 1.7,
      a: 0.08 + random() * 0.25,
      phase: random() * Math.PI * 2,
    }));
  }

  resetServe() {
    const radius = Math.max(6, Math.min(11, Number(this.level?.physics?.ballRadius ?? 8)));
    const speed = Math.max(5.5, Math.min(14, Number(this.level?.physics?.ballSpeed ?? 8.7)));
    this.balls = [{
      id: crypto.randomUUID?.() ?? `${Date.now()}-${Math.random()}`,
      x: this.paddle.x + this.paddle.w / 2,
      y: this.paddle.y - radius - 3,
      r: radius,
      vx: speed * 0.38,
      vy: -Math.sqrt(Math.max(1, speed * speed - (speed * 0.38) ** 2)),
      speed,
      attached: true,
      dead: false,
      trail: [],
    }];
    this.state = "ready";
  }

  restartLevel() {
    if (!this.level) return;
    this.loadLevel(this.level);
  }

  enterMenu() {
    this.state = "menu";
    this.keys.left = false;
    this.keys.right = false;
    this.callbacks.onPauseChanged(false);
    this.emitHud(true);
  }

  launch() {
    if (!this.level || this.state === "menu" || this.state === "paused" || this.state === "ended") return;
    const attachedBalls = this.balls.filter((ball) => ball.attached);
    if (!attachedBalls.length) return;
    attachedBalls.forEach((ball, index) => {
      ball.attached = false;
      const spread = (index - (attachedBalls.length - 1) / 2) * 0.08;
      const rotated = rotateVector(ball.vx, ball.vy, spread);
      ball.vx = rotated.x;
      ball.vy = -Math.abs(rotated.y);
    });
    this.state = "running";
    this.callbacks.onToast("Partida iniciada");
    this.emitHud(true);
  }

  setPaddleTarget(worldX) {
    this.paddle.targetX = clamp(worldX, this.paddle.w / 2 + 5, this.world.width - this.paddle.w / 2 - 5);
  }

  pause() {
    if (this.state !== "running" && this.state !== "ready") return;
    this.state = "paused";
    this.callbacks.onPauseChanged(true);
    this.emitHud(true);
  }

  resume() {
    if (this.state !== "paused") return;
    this.state = this.balls.some((ball) => ball.attached) ? "ready" : "running";
    this.lastFrameTime = performance.now();
    this.callbacks.onPauseChanged(false);
    this.emitHud(true);
  }

  togglePause() {
    if (this.state === "paused") this.resume();
    else this.pause();
  }

  update(frameScale, deltaSeconds) {
    if (!this.level) return;
    this.updatePaddle(frameScale);
    this.updateEffectTimers();
    this.updateParticles(frameScale);

    if (this.state === "ready") {
      this.balls.forEach((ball) => {
        if (ball.attached) {
          ball.x = this.paddle.x + this.paddle.w / 2;
          ball.y = this.paddle.y - ball.r - 3;
        }
      });
      this.emitHud();
      return;
    }

    this.gameClock += deltaSeconds;
    this.updateBalls(frameScale);
    this.updatePowerups(frameScale);
    this.updateBricksVisual(frameScale);
    this.emitHud();
  }

  updateVisualOnly(frameScale) {
    this.updateParticles(frameScale * 0.45);
    this.updateBricksVisual(frameScale * 0.35);
  }

  updatePaddle(frameScale) {
    const keyboardSpeed = 12.5 * frameScale;
    if (this.keys.left) this.paddle.targetX -= keyboardSpeed;
    if (this.keys.right) this.paddle.targetX += keyboardSpeed;

    this.paddle.targetW = this.effects.wideUntil > this.gameClock
      ? this.paddle.baseW * Number(this.level?.powerups?.wideMultiplier ?? 1.62)
      : this.paddle.baseW;
    this.paddle.targetW = clamp(this.paddle.targetW, 90, 285);
    this.paddle.w = lerp(this.paddle.w, this.paddle.targetW, Math.min(1, 0.16 * frameScale));
    this.paddle.targetX = clamp(this.paddle.targetX, this.paddle.w / 2 + 5, this.world.width - this.paddle.w / 2 - 5);

    const oldCenter = this.paddle.x + this.paddle.w / 2;
    const newCenter = lerp(oldCenter, this.paddle.targetX, Math.min(1, 0.22 * frameScale));
    this.paddle.x = clamp(newCenter - this.paddle.w / 2, 5, this.world.width - this.paddle.w - 5);
    const actualCenter = this.paddle.x + this.paddle.w / 2;
    this.paddle.velocity = actualCenter - this.paddle.previousCenter;
    this.paddle.previousCenter = actualCenter;
  }

  updateEffectTimers() {
    if (this.effects.wideUntil && this.effects.wideUntil <= this.gameClock) {
      this.effects.wideUntil = 0;
    }
    if (this.effects.shieldUntil && this.effects.shieldUntil <= this.gameClock) {
      this.effects.shieldUntil = 0;
    }
  }

  updateBalls(frameScale) {
    const activeBalls = this.balls.filter((ball) => !ball.dead);

    for (const ball of activeBalls) {
      ball.trail.unshift({ x: ball.x, y: ball.y });
      if (ball.trail.length > 9) ball.trail.length = 9;

      const distance = Math.hypot(ball.vx, ball.vy) * frameScale;
      const steps = clamp(Math.ceil(distance / Math.max(4, ball.r * 0.75)), 1, 6);
      const stepScale = frameScale / steps;

      for (let step = 0; step < steps && !ball.dead; step += 1) {
        ball.x += ball.vx * stepScale;
        ball.y += ball.vy * stepScale;
        this.resolveWorldCollision(ball);
        if (ball.dead) break;
        this.resolvePaddleCollision(ball);
        this.resolveBrickCollision(ball);
      }
    }

    this.balls = this.balls.filter((ball) => !ball.dead);

    if (!this.balls.length && this.state === "running" && !this.endTriggered) {
      this.lives -= 1;
      this.audio?.lifeLost();
      if (this.lives <= 0) {
        this.finish(false);
      } else {
        this.callbacks.onToast(`Bola perdida. Quedan ${this.lives} vidas`);
        this.powerups = [];
        this.effects.wideUntil = 0;
        this.effects.shieldUntil = 0;
        this.resetServe();
      }
      this.emitHud(true);
    }
  }

  resolveWorldCollision(ball) {
    if (ball.x - ball.r <= 0 && ball.vx < 0) {
      ball.x = ball.r + 0.5;
      ball.vx = Math.abs(ball.vx);
      this.audio?.wall();
    } else if (ball.x + ball.r >= this.world.width && ball.vx > 0) {
      ball.x = this.world.width - ball.r - 0.5;
      ball.vx = -Math.abs(ball.vx);
      this.audio?.wall();
    }

    if (ball.y - ball.r <= 0 && ball.vy < 0) {
      ball.y = ball.r + 0.5;
      ball.vy = Math.abs(ball.vy);
      this.audio?.wall();
    }

    if (this.effects.shieldUntil > this.gameClock && ball.vy > 0 && ball.y + ball.r >= SHIELD_Y) {
      ball.y = SHIELD_Y - ball.r - 1;
      ball.vy = -Math.abs(ball.vy);
      ball.vx += (this.gameRandom() - 0.5) * 0.35;
      this.audio?.paddle();
      this.spawnParticles(ball.x, SHIELD_Y, "#28dfff", 9, 2.4);
    }

    if (ball.y - ball.r > this.world.height) {
      ball.dead = true;
    }
  }

  resolvePaddleCollision(ball) {
    if (ball.vy <= 0) return;
    if (!circleIntersectsRect(ball, this.paddle)) return;

    const center = this.paddle.x + this.paddle.w / 2;
    const relative = clamp((ball.x - center) / (this.paddle.w / 2), -1, 1);
    const maxAngle = Number(this.level?.physics?.maxBounceAngleDeg ?? 68) * (Math.PI / 180);
    const angle = relative * maxAngle;
    const speedBoost = 1 + Math.min(0.08, this.gameClock / 900);
    const targetSpeed = clamp(ball.speed * speedBoost, 5.5, 14.5);
    const paddleInfluence = clamp(this.paddle.velocity * 0.055, -1.3, 1.3);

    ball.x = clamp(ball.x, this.paddle.x + ball.r, this.paddle.x + this.paddle.w - ball.r);
    ball.y = this.paddle.y - ball.r - 1;
    ball.vx = Math.sin(angle) * targetSpeed + paddleInfluence;
    ball.vy = -Math.abs(Math.cos(angle) * targetSpeed);

    const minimumVertical = targetSpeed * 0.34;
    if (Math.abs(ball.vy) < minimumVertical) {
      ball.vy = -minimumVertical;
      const horizontalSign = Math.sign(ball.vx || relative || 1);
      ball.vx = horizontalSign * Math.sqrt(Math.max(1, targetSpeed ** 2 - minimumVertical ** 2));
    }

    this.audio?.paddle();
    this.spawnParticles(ball.x, this.paddle.y, "#ff9d32", 5, 1.8);
  }

  resolveBrickCollision(ball) {
    for (const brick of this.bricks) {
      if (brick.destroyed) continue;
      const collision = resolveCircleRectCollision(ball, brick);
      if (!collision) continue;

      if (collision.axis === "x") {
        ball.x = collision.normal < 0
          ? brick.x - ball.r - 0.6
          : brick.x + brick.w + ball.r + 0.6;
        ball.vx = collision.normal < 0 ? -Math.abs(ball.vx) : Math.abs(ball.vx);
      } else {
        ball.y = collision.normal < 0
          ? brick.y - ball.r - 0.6
          : brick.y + brick.h + ball.r + 0.6;
        ball.vy = collision.normal < 0 ? -Math.abs(ball.vy) : Math.abs(ball.vy);
      }

      brick.hitFlash = 1;
      this.audio?.brick(brick.indestructible);

      if (brick.indestructible) {
        this.score += 1;
        this.spawnParticles(ball.x, ball.y, "#aeb3c0", 2, 1.4);
        break;
      }

      brick.hp -= 1;
      this.score += 8 + brick.maxHp * 3;
      if (brick.hp <= 0) {
        brick.destroyed = true;
        this.remainingDestructible -= 1;
        this.score += 24 + brick.maxHp * 8;
        this.spawnParticles(brick.x + brick.w / 2, brick.y + brick.h / 2, brick.color, 7, 2.8);
        this.maybeDropPowerup(brick);

        if (this.remainingDestructible <= 0) {
          this.finish(true);
        }
      } else {
        this.spawnParticles(ball.x, ball.y, brick.color, 3, 1.8);
      }
      break;
    }
  }

  updateBricksVisual(frameScale) {
    for (const brick of this.bricks) {
      if (brick.hitFlash > 0) {
        brick.hitFlash = Math.max(0, brick.hitFlash - 0.12 * frameScale);
      }
    }
  }

  maybeDropPowerup(brick) {
    const config = this.level?.powerups ?? {};
    const dropRate = clamp(Number(config.dropRate ?? 0.105), 0, 0.45);
    if (this.gameRandom() > dropRate) return;

    const type = weightedChoice(this.gameRandom, [
      { value: "triple", weight: Number(config.weights?.triple ?? 0.34) },
      { value: "wide", weight: Number(config.weights?.wide ?? 0.34) },
      { value: "shield", weight: Number(config.weights?.shield ?? 0.32) },
    ]);

    this.powerups.push({
      id: crypto.randomUUID?.() ?? `${Date.now()}-${Math.random()}`,
      type,
      x: brick.x + brick.w / 2,
      y: brick.y + brick.h / 2,
      r: 16,
      vy: 3.05 + this.gameRandom() * 0.7,
      rotation: this.gameRandom() * Math.PI * 2,
      dead: false,
    });
  }

  updatePowerups(frameScale) {
    for (const powerup of this.powerups) {
      powerup.y += powerup.vy * frameScale;
      powerup.rotation += 0.045 * frameScale;

      if (circleIntersectsRect(powerup, this.paddle)) {
        powerup.dead = true;
        this.applyPowerup(powerup.type);
      } else if (powerup.y - powerup.r > this.world.height) {
        powerup.dead = true;
      }
    }
    this.powerups = this.powerups.filter((powerup) => !powerup.dead);
  }

  applyPowerup(type) {
    const config = this.level?.powerups ?? {};
    if (type === "triple") {
      const originals = [...this.balls].filter((ball) => !ball.dead && !ball.attached);
      const additions = [];
      for (const ball of originals) {
        for (const angle of [-0.23, 0.23]) {
          if (this.balls.length + additions.length >= MAX_BALLS) break;
          const velocity = rotateVector(ball.vx, ball.vy, angle);
          additions.push({
            ...ball,
            id: crypto.randomUUID?.() ?? `${Date.now()}-${Math.random()}`,
            x: ball.x + (angle < 0 ? -2 : 2),
            y: ball.y,
            vx: velocity.x,
            vy: velocity.y,
            trail: [],
          });
        }
      }
      this.balls.push(...additions);
      this.callbacks.onToast(`Multiplicador x3: ${this.balls.length} bolas activas`);
    } else if (type === "wide") {
      const duration = Number(config.wideSeconds ?? 16);
      this.effects.wideUntil = Math.max(this.effects.wideUntil, this.gameClock) + duration;
      this.callbacks.onToast(`Plataforma ampliada durante ${duration} s`);
    } else if (type === "shield") {
      const duration = Number(config.shieldSeconds ?? 13);
      this.effects.shieldUntil = Math.max(this.effects.shieldUntil, this.gameClock) + duration;
      this.callbacks.onToast(`Foso cerrado durante ${duration} s`);
    }

    this.score += 100;
    this.audio?.powerup();
    this.emitHud(true);
  }

  updateParticles(frameScale) {
    for (const particle of this.particles) {
      particle.x += particle.vx * frameScale;
      particle.y += particle.vy * frameScale;
      particle.vy += 0.035 * frameScale;
      particle.life -= 0.035 * frameScale;
    }
    this.particles = this.particles.filter((particle) => particle.life > 0);
  }

  spawnParticles(x, y, color, count = 5, force = 2) {
    for (let index = 0; index < count; index += 1) {
      const angle = this.gameRandom() * Math.PI * 2;
      const speed = (0.35 + this.gameRandom()) * force;
      this.particles.push({
        x,
        y,
        vx: Math.cos(angle) * speed,
        vy: Math.sin(angle) * speed,
        life: 0.35 + this.gameRandom() * 0.65,
        size: 1.5 + this.gameRandom() * 3.5,
        color,
      });
    }
    if (this.particles.length > 280) {
      this.particles.splice(0, this.particles.length - 280);
    }
  }

  finish(won) {
    if (this.endTriggered) return;
    this.endTriggered = true;
    this.state = "ended";
    this.keys.left = false;
    this.keys.right = false;
    const timeBonus = won ? Math.max(0, Math.round(2500 - this.gameClock * 12)) : 0;
    const lifeBonus = won ? this.lives * 750 : 0;
    this.score += timeBonus + lifeBonus;
    const stars = won ? clamp(this.lives, 1, 3) : 0;

    if (won) this.audio?.win();
    else this.audio?.gameOver();

    this.emitHud(true);
    window.setTimeout(() => {
      this.callbacks.onEnd({
        won,
        score: Math.round(this.score),
        lives: this.lives,
        stars,
        timeSeconds: this.gameClock,
        level: this.level,
      });
    }, 450);
  }

  emitHud(force = false) {
    const now = performance.now();
    if (!force && now - this.lastHudAt < 120) return;
    this.lastHudAt = now;
    const destroyed = Math.max(0, this.totalDestructible - this.remainingDestructible);
    const progress = this.totalDestructible > 0 ? destroyed / this.totalDestructible : 0;
    let status = "Preparado";
    if (this.state === "running") status = `${this.balls.length} bola${this.balls.length === 1 ? "" : "s"} activa${this.balls.length === 1 ? "" : "s"}`;
    if (this.state === "paused") status = "En pausa";
    if (this.state === "ended") status = this.remainingDestructible <= 0 ? "Completado" : "Partida terminada";
    if (this.state === "menu") status = "Selecciona escenario";

    this.callbacks.onHud({
      levelName: this.level?.name ?? "Sin nivel",
      levelSubtitle: this.level?.subtitle ?? "",
      lives: this.lives,
      score: Math.round(this.score),
      total: this.totalDestructible,
      remaining: this.remainingDestructible,
      destroyed,
      progress,
      balls: this.balls.length,
      status,
      formattedScore: formatScore(this.score),
    });
  }

  draw() {
    const context = this.context;
    const width = this.world.width;
    const height = this.world.height;

    context.save();
    context.fillStyle = this.backgroundGradient ?? "#12002b";
    context.fillRect(0, 0, width, height);

    this.drawBackground(context);
    this.drawBricks(context);
    this.drawParticles(context);
    this.drawPowerups(context);
    this.drawShield(context);
    this.drawPaddle(context);
    this.drawBalls(context);
    this.drawEffectChips(context);
    this.drawLaunchHint(context);

    context.restore();
  }

  drawBackground(context) {
    context.save();
    const accent = this.level?.theme?.accent ?? "#ff4f87";
    for (const star of this.backgroundStars) {
      const twinkle = 0.55 + Math.sin(this.gameClock * 1.5 + star.phase) * 0.35;
      context.globalAlpha = star.a * twinkle;
      context.fillStyle = "#ffffff";
      context.beginPath();
      context.arc(star.x, star.y, star.r, 0, Math.PI * 2);
      context.fill();
    }

    context.globalAlpha = 0.08;
    context.strokeStyle = accent;
    context.lineWidth = 1;
    for (let x = 0; x <= this.world.width; x += 60) {
      context.beginPath();
      context.moveTo(x, 0);
      context.lineTo(x, this.world.height);
      context.stroke();
    }
    for (let y = 0; y <= this.world.height; y += 60) {
      context.beginPath();
      context.moveTo(0, y);
      context.lineTo(this.world.width, y);
      context.stroke();
    }

    context.globalAlpha = 0.32;
    context.strokeStyle = rgba(accent, 0.7);
    context.lineWidth = 3;
    context.strokeRect(8, 8, this.world.width - 16, this.world.height - 16);
    context.restore();
  }

  drawBricks(context) {
    for (const brick of this.bricks) {
      if (brick.destroyed) continue;
      const damageRatio = brick.indestructible ? 1 : brick.hp / Math.max(1, brick.maxHp);
      context.save();
      context.globalAlpha = brick.indestructible ? 0.76 : 0.72 + damageRatio * 0.28;
      context.fillStyle = brick.hitFlash > 0.35 ? "#ffffff" : brick.color;
      roundRectPath(context, brick.x, brick.y, brick.w, brick.h, Math.min(3, brick.w * 0.22));
      context.fill();

      if (brick.w > 7 && brick.h > 7) {
        context.globalAlpha = 0.22;
        context.fillStyle = "#ffffff";
        roundRectPath(context, brick.x + 1, brick.y + 1, Math.max(1, brick.w - 2), Math.max(1, brick.h * 0.28), 1.5);
        context.fill();
      }

      if (brick.indestructible) {
        context.globalAlpha = 0.22;
        context.strokeStyle = "#ffffff";
        context.lineWidth = 1;
        context.beginPath();
        context.moveTo(brick.x + 1, brick.y + brick.h - 1);
        context.lineTo(brick.x + brick.w - 1, brick.y + 1);
        context.stroke();
      } else if (brick.maxHp > 1 && brick.w > 8) {
        context.globalAlpha = 0.5;
        context.fillStyle = "#14001f";
        const dots = brick.hp;
        const dotSize = Math.max(1.2, brick.w * 0.11);
        for (let index = 0; index < dots; index += 1) {
          context.beginPath();
          context.arc(brick.x + brick.w - 2.5 - index * (dotSize + 1.2), brick.y + brick.h - 2.5, dotSize, 0, Math.PI * 2);
          context.fill();
        }
      }
      context.restore();
    }
  }

  drawBalls(context) {
    for (const ball of this.balls) {
      context.save();
      for (let index = ball.trail.length - 1; index >= 0; index -= 1) {
        const point = ball.trail[index];
        const alpha = (1 - index / Math.max(1, ball.trail.length)) * 0.13;
        context.globalAlpha = alpha;
        context.fillStyle = this.level?.theme?.ball ?? "#ffffff";
        context.beginPath();
        context.arc(point.x, point.y, Math.max(1, ball.r * (1 - index * 0.07)), 0, Math.PI * 2);
        context.fill();
      }

      context.globalAlpha = 1;
      context.shadowColor = this.level?.theme?.ballGlow ?? "#ffffff";
      context.shadowBlur = 16;
      const ballGradient = context.createRadialGradient(
        ball.x - ball.r * 0.35,
        ball.y - ball.r * 0.4,
        1,
        ball.x,
        ball.y,
        ball.r * 1.2,
      );
      ballGradient.addColorStop(0, "#ffffff");
      ballGradient.addColorStop(0.55, this.level?.theme?.ball ?? "#ffffff");
      ballGradient.addColorStop(1, "#b9a7db");
      context.fillStyle = ballGradient;
      context.beginPath();
      context.arc(ball.x, ball.y, ball.r, 0, Math.PI * 2);
      context.fill();
      context.restore();
    }
  }

  drawPaddle(context) {
    context.save();
    context.shadowColor = this.level?.theme?.accent ?? "#ff765f";
    context.shadowBlur = 18;
    const gradient = context.createLinearGradient(this.paddle.x, this.paddle.y, this.paddle.x + this.paddle.w, this.paddle.y);
    gradient.addColorStop(0, this.level?.theme?.paddleStart ?? "#ff4f87");
    gradient.addColorStop(0.5, this.level?.theme?.paddleMiddle ?? "#ffe75b");
    gradient.addColorStop(1, this.level?.theme?.paddleEnd ?? "#ff765f");
    context.fillStyle = gradient;
    roundRectPath(context, this.paddle.x, this.paddle.y, this.paddle.w, this.paddle.h, 8);
    context.fill();

    context.shadowBlur = 0;
    context.globalAlpha = 0.48;
    context.fillStyle = "#ffffff";
    roundRectPath(context, this.paddle.x + 6, this.paddle.y + 3, Math.max(1, this.paddle.w - 12), 3, 2);
    context.fill();
    context.restore();
  }

  drawShield(context) {
    if (this.effects.shieldUntil <= this.gameClock) return;
    const remaining = this.effects.shieldUntil - this.gameClock;
    const pulse = 0.65 + Math.sin(this.gameClock * 7) * 0.2;
    context.save();
    context.globalAlpha = pulse;
    context.strokeStyle = "#28dfff";
    context.lineWidth = 8;
    context.shadowColor = "#28dfff";
    context.shadowBlur = 22;
    context.beginPath();
    context.moveTo(18, SHIELD_Y);
    context.lineTo(this.world.width - 18, SHIELD_Y);
    context.stroke();
    context.shadowBlur = 0;
    context.globalAlpha = 0.82;
    context.fillStyle = "#d9faff";
    context.font = "700 13px system-ui";
    context.textAlign = "right";
    context.fillText(`${remaining.toFixed(1)} s`, this.world.width - 20, SHIELD_Y - 12);
    context.restore();
  }

  drawPowerups(context) {
    const visual = {
      triple: { label: "x3", color: "#9cef39", dark: "#183100" },
      wide: { label: "W", color: "#ff9d32", dark: "#401800" },
      shield: { label: "S", color: "#28dfff", dark: "#002c38" },
    };

    for (const powerup of this.powerups) {
      const style = visual[powerup.type] ?? visual.triple;
      context.save();
      context.translate(powerup.x, powerup.y);
      context.rotate(Math.sin(powerup.rotation) * 0.12);
      context.shadowColor = style.color;
      context.shadowBlur = 22;
      const gradient = context.createRadialGradient(-5, -6, 2, 0, 0, powerup.r);
      gradient.addColorStop(0, "#ffffff");
      gradient.addColorStop(0.24, style.color);
      gradient.addColorStop(1, style.dark);
      context.fillStyle = gradient;
      context.beginPath();
      context.arc(0, 0, powerup.r, 0, Math.PI * 2);
      context.fill();
      context.shadowBlur = 0;
      context.fillStyle = "#ffffff";
      context.font = "950 13px system-ui";
      context.textAlign = "center";
      context.textBaseline = "middle";
      context.fillText(style.label, 0, 1);
      context.restore();
    }
  }

  drawParticles(context) {
    context.save();
    for (const particle of this.particles) {
      context.globalAlpha = clamp(particle.life, 0, 1);
      context.fillStyle = particle.color;
      context.fillRect(particle.x - particle.size / 2, particle.y - particle.size / 2, particle.size, particle.size);
    }
    context.restore();
  }

  drawEffectChips(context) {
    const chips = [];
    if (this.effects.wideUntil > this.gameClock) {
      chips.push({ label: `PLATAFORMA ${Math.ceil(this.effects.wideUntil - this.gameClock)}s`, color: "#ff9d32" });
    }
    if (this.effects.shieldUntil > this.gameClock) {
      chips.push({ label: `ESCUDO ${Math.ceil(this.effects.shieldUntil - this.gameClock)}s`, color: "#28dfff" });
    }
    if (this.balls.length > 1) {
      chips.push({ label: `${this.balls.length} BOLAS`, color: "#9cef39" });
    }
    if (!chips.length) return;

    context.save();
    context.font = "800 12px system-ui";
    context.textBaseline = "middle";
    let x = 18;
    const y = 997;
    for (const chip of chips) {
      const width = context.measureText(chip.label).width + 22;
      context.fillStyle = rgba(chip.color, 0.17);
      context.strokeStyle = rgba(chip.color, 0.75);
      context.lineWidth = 1.5;
      roundRectPath(context, x, y - 14, width, 28, 10);
      context.fill();
      context.stroke();
      context.fillStyle = chip.color;
      context.fillText(chip.label, x + 11, y + 1);
      x += width + 8;
    }
    context.restore();
  }

  drawLaunchHint(context) {
    if (this.state !== "ready") return;
    const pulse = 0.72 + Math.sin(performance.now() / 260) * 0.22;
    context.save();
    context.globalAlpha = pulse;
    context.textAlign = "center";
    context.fillStyle = "#ffffff";
    context.font = "850 18px system-ui";
    context.fillText("TOCA O PULSA ESPACIO PARA LANZAR", this.world.width / 2, 895);
    context.fillStyle = "rgba(255,255,255,.55)";
    context.font = "600 13px system-ui";
    context.fillText("El punto de impacto en la plataforma cambia el angulo", this.world.width / 2, 920);
    context.restore();
  }
}
