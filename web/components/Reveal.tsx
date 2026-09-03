"use client";

import { useEffect, useRef, useState, type ReactNode } from "react";

/**
 * Reveals its children once they scroll into view. Used only on the marketing
 * sections below the fold: those are seen once per visit, which is the one
 * frequency band where a reveal earns its keep. Anything above the fold stays
 * instant — animating content the visitor is already looking at just delays it.
 *
 * Fires once and disconnects; a section that re-animates every time it scrolls
 * past becomes noise on the second pass.
 */
export function Reveal({
  children,
  delay = 0,
  className = "",
}: {
  children: ReactNode;
  delay?: number;
  className?: string;
}) {
  const ref = useRef<HTMLDivElement>(null);
  const [shown, setShown] = useState(false);

  useEffect(() => {
    const el = ref.current;
    if (!el) return;
    let done = false;

    const show = () => {
      if (done) return;
      done = true;
      setShown(true);
      io.disconnect();
      window.removeEventListener("scroll", check);
    };

    // Reveal once the block has entered the fold OR been scrolled past. The second
    // half matters: an instant jump — a deep anchor link, a restored scroll
    // position, scrollTo() — moves an element from below the viewport to above it
    // within a single frame. Both states are "not intersecting", so the observer
    // reports no threshold change and never fires, leaving that section stuck at
    // opacity 0 permanently. The observer alone is not sufficient.
    const check = () => {
      if (el.getBoundingClientRect().top < window.innerHeight * 0.9) show();
    };

    const io = new IntersectionObserver(([entry]) => {
      if (entry.isIntersecting) show();
    });
    io.observe(el);
    window.addEventListener("scroll", check, { passive: true });
    check();

    return () => {
      io.disconnect();
      window.removeEventListener("scroll", check);
    };
  }, []);

  return (
    // h-full so a stretched grid cell passes its height to the child. Without it the
    // wrapper stretches and the card inside sizes to its own content, which is what
    // made tiles in the same row end at different heights.
    <div
      ref={ref}
      className={`reveal h-full ${className}`}
      data-shown={shown}
      style={{ transitionDelay: `${delay}ms` }}
    >
      {children}
    </div>
  );
}
