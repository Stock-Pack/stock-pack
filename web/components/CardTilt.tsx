"use client";

import { useEffect, useRef, type ReactNode } from "react";

const MAX_TILT = 9; // degrees
const LERP = 0.14; // per-frame approach; low enough to read as weight, not lag
const HOVER_SCALE = 1.04;
const PRESS_SCALE = 0.985;

/**
 * Gives the card artwork physical behaviour: it tilts toward the pointer, carries a
 * specular highlight that tracks the cursor, and presses in on click.
 *
 * The tilt is interpolated toward the pointer rather than bound to it. Mapping a
 * transform straight to mouse position feels artificial because it has no mass —
 * the card arrives before the hand does. A per-frame lerp gives it momentum and,
 * unlike a keyframed animation, it retargets smoothly when the pointer changes
 * direction mid-motion.
 *
 * Only transform and opacity are animated, so this stays off the layout and paint
 * paths. Attached only for fine pointers: a touch device fires hover on tap and
 * would leave the card tilted after the finger lifts.
 */
export function CardTilt({ children, className = "" }: { children: ReactNode; className?: string }) {
  const wrap = useRef<HTMLDivElement>(null);
  const inner = useRef<HTMLDivElement>(null);
  const sheen = useRef<HTMLDivElement>(null);

  // target vs current: the gap between them is what produces the sense of weight
  const target = useRef({ rx: 0, ry: 0, s: 1, mx: 50, my: 50, glow: 0 });

  useEffect(() => {
    const el = wrap.current;
    if (!el) return;
    // Both gates matter: no tilt for coarse pointers, none for reduced motion.
    if (!window.matchMedia("(hover: hover) and (pointer: fine)").matches) return;
    if (window.matchMedia("(prefers-reduced-motion: reduce)").matches) return;

    const current = { rx: 0, ry: 0, s: 1, mx: 50, my: 50, glow: 0 };
    let raf: number | null = null;

    // The loop lives inside the effect so it can reference itself without the
    // hook-ordering gymnastics a self-referential useCallback would need.
    const tick = () => {
      let moving = false;
      for (const k of ["rx", "ry", "s", "mx", "my", "glow"] as const) {
        const d = target.current[k] - current[k];
        if (Math.abs(d) > 0.001) {
          current[k] += d * LERP;
          moving = true;
        } else {
          current[k] = target.current[k];
        }
      }
      if (inner.current) {
        // full transform string, not discrete props: this is the form the compositor
        // can hand to the GPU without a main-thread round trip each frame
        inner.current.style.transform =
          `perspective(900px) rotateX(${current.rx.toFixed(3)}deg) rotateY(${current.ry.toFixed(3)}deg) scale(${current.s.toFixed(4)})`;
      }
      if (sheen.current) {
        sheen.current.style.opacity = current.glow.toFixed(3);
        sheen.current.style.background =
          `radial-gradient(circle at ${current.mx.toFixed(1)}% ${current.my.toFixed(1)}%, rgba(255,255,255,0.22), rgba(255,255,255,0.04) 38%, transparent 62%)`;
      }
      raf = moving ? requestAnimationFrame(tick) : null;
    };
    const start = () => {
      if (raf == null) raf = requestAnimationFrame(tick);
    };

    const onMove = (e: PointerEvent) => {
      const r = el.getBoundingClientRect();
      const nx = (e.clientX - r.left) / r.width;
      const ny = (e.clientY - r.top) / r.height;
      const t = target.current;
      t.ry = (nx - 0.5) * 2 * MAX_TILT;
      t.rx = -(ny - 0.5) * 2 * MAX_TILT;
      t.mx = nx * 100;
      t.my = ny * 100;
      t.glow = 1;
      start();
    };
    const onEnter = () => {
      target.current.s = HOVER_SCALE;
      start();
    };
    const onLeave = () => {
      Object.assign(target.current, { rx: 0, ry: 0, s: 1, glow: 0 });
      start();
    };
    const onDown = () => {
      target.current.s = PRESS_SCALE;
      start();
    };
    const onUp = () => {
      target.current.s = HOVER_SCALE;
      start();
    };

    el.addEventListener("pointerenter", onEnter);
    el.addEventListener("pointermove", onMove);
    el.addEventListener("pointerleave", onLeave);
    el.addEventListener("pointerdown", onDown);
    el.addEventListener("pointerup", onUp);
    return () => {
      el.removeEventListener("pointerenter", onEnter);
      el.removeEventListener("pointermove", onMove);
      el.removeEventListener("pointerleave", onLeave);
      el.removeEventListener("pointerdown", onDown);
      el.removeEventListener("pointerup", onUp);
      if (raf != null) cancelAnimationFrame(raf);
    };
  }, []);

  return (
    <div ref={wrap} className={`tilt-wrap ${className}`}>
      <div ref={inner} className="tilt-inner">
        {children}
        <div ref={sheen} aria-hidden className="tilt-sheen" />
      </div>
    </div>
  );
}
