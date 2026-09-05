import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "Brand assets — StockPack",
  description: "The StockPack mark, lockup and banners in SVG and PNG, with the brand colours and typefaces.",
};

/* Every file here is served from /public/brand. The previews are the files
   themselves, so what you see is exactly what downloads. */

type File = { label: string; href: string };
type Asset = { title: string; note: string; preview: string; plate: "dark" | "white" | "raise"; files: File[] };

const MARKS: Asset[] = [
  {
    title: "Mark on dark",
    note: "Cream on the brand black. The default.",
    preview: "/brand/stockpack-mark-dark-1024.png",
    plate: "dark",
    files: [{ label: "PNG 1024", href: "/brand/stockpack-mark-dark-1024.png" }],
  },
  {
    title: "Mark on white",
    note: "Ink on white, for light documents.",
    preview: "/brand/stockpack-mark-white-1024.png",
    plate: "white",
    files: [{ label: "PNG 1024", href: "/brand/stockpack-mark-white-1024.png" }],
  },
  {
    title: "Mark, cream",
    note: "Transparent. Use over dark photography or colour.",
    preview: "/brand/stockpack-mark-cream-1024.png",
    plate: "raise",
    files: [
      { label: "SVG", href: "/brand/stockpack-mark-cream.svg" },
      { label: "PNG 1024", href: "/brand/stockpack-mark-cream-1024.png" },
    ],
  },
  {
    title: "Mark, ink",
    note: "Transparent. Use over light grounds.",
    preview: "/brand/stockpack-mark-ink-1024.png",
    plate: "white",
    files: [
      { label: "SVG", href: "/brand/stockpack-mark-ink.svg" },
      { label: "PNG 1024", href: "/brand/stockpack-mark-ink-1024.png" },
    ],
  },
];

const LOCKUPS: Asset[] = [
  {
    title: "Lockup on dark",
    note: "Mark, wordmark and full stop. Cream on the brand black.",
    preview: "/brand/stockpack-lockup-dark-2400.png",
    plate: "dark",
    files: [
      { label: "SVG", href: "/brand/stockpack-lockup-cream.svg" },
      { label: "PNG transparent", href: "/brand/stockpack-lockup-cream-2400.png" },
      { label: "PNG on black", href: "/brand/stockpack-lockup-dark-2400.png" },
    ],
  },
  {
    title: "Lockup on white",
    note: "The same lockup in ink, for light grounds.",
    preview: "/brand/stockpack-lockup-white-2400.png",
    plate: "white",
    files: [
      { label: "SVG", href: "/brand/stockpack-lockup-ink.svg" },
      { label: "PNG transparent", href: "/brand/stockpack-lockup-ink-2400.png" },
      { label: "PNG on white", href: "/brand/stockpack-lockup-white-2400.png" },
    ],
  },
];

const BANNERS: (Asset & { size: string })[] = [
  {
    title: "Social card",
    size: "1200 × 630",
    note: "Open Graph and link previews. This is what a shared stockpack link shows.",
    preview: "/brand/stockpack-social-1200x630.jpg",
    plate: "dark",
    files: [{ label: "JPG", href: "/brand/stockpack-social-1200x630.jpg" }],
  },
  {
    title: "The portfolio is the product",
    size: "1200 × 675",
    note: "16:9 campaign banner for posts and decks.",
    preview: "/brand/stockpack-banner-portfolio-1200x675.jpg",
    plate: "dark",
    files: [{ label: "JPG", href: "/brand/stockpack-banner-portfolio-1200x675.jpg" }],
  },
  {
    title: "A portfolio should move as one",
    size: "1280 × 427",
    note: "3:1 header for X, LinkedIn and similar profile banners.",
    preview: "/brand/stockpack-banner-header-1280x427.jpg",
    plate: "dark",
    files: [{ label: "JPG", href: "/brand/stockpack-banner-header-1280x427.jpg" }],
  },
];

const COLOURS = [
  { name: "Ink", hex: "#0A0A0A", use: "brand black, every dark ground" },
  { name: "Cream", hex: "#F4F0E5", use: "the mark and wordmark on dark" },
  { name: "Amber", hex: "#F1A93B", use: "the diamond and the full stop, nothing else" },
];

const PLATE = {
  dark: "bg-[#0A0A0A]",
  white: "bg-white",
  raise: "bg-raise",
} as const;

function Downloads({ files }: { files: File[] }) {
  return (
    <ul className="flex flex-wrap gap-x-4 gap-y-2">
      {files.map((f) => (
        <li key={f.href}>
          <a href={f.href} download className="link-arrow">
            {f.label} &darr;
          </a>
        </li>
      ))}
    </ul>
  );
}

function Tile({ asset, wide = false }: { asset: Asset; wide?: boolean }) {
  return (
    // min-w-0: the previews are full-size files, so without it a grid cell is floored
    // at the image's intrinsic width and the whole page gains a horizontal scrollbar
    <div className="panel flex min-w-0 flex-col">
      <div className="panel-head">
        <span>{asset.title}</span>
        <span>{"size" in asset ? (asset as { size: string }).size : asset.files.length > 1 ? "svg · png" : "png"}</span>
      </div>
      <div className={`${PLATE[asset.plate]} ${wide ? "px-6 py-8" : "aspect-square p-8"}`}>
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img
          src={asset.preview}
          alt={asset.title}
          loading="lazy"
          className={wide ? "block h-auto w-full" : "block h-full w-full object-contain"}
        />
      </div>
      <div className="mt-auto space-y-3 border-t border-line px-4 py-4">
        <p className="mini">{asset.note}</p>
        <Downloads files={asset.files} />
      </div>
    </div>
  );
}

export default function BrandPage() {
  return (
    <div className="page space-y-16">
      <div>
        <p className="eyebrow">Brand</p>
        <h1 className="page-title mt-3">StockPack brand assets.</h1>
        <p className="mt-4 max-w-2xl text-muted">
          The mark, the lockup and the campaign banners, as vector and PNG. Use them as they come: keep the mark upright,
          keep the diamond amber, and leave clear space around it of at least half its width. Do not redraw, outline or
          recolour it.
        </p>
      </div>

      <section>
        <p className="eyebrow">The mark</p>
        <p className="mt-3 max-w-2xl text-muted">
          Four blades turning around one amber diamond: many positions, sealed into one thing that moves as one.
        </p>
        <div className="mt-8 grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
          {MARKS.map((a) => (
            <Tile key={a.title} asset={a} />
          ))}
        </div>
      </section>

      <section>
        <p className="eyebrow">The lockup</p>
        <p className="mt-3 max-w-2xl text-muted">
          The wordmark is set in Playfair Display Bold and ends in the amber full stop. Use the lockup wherever there is
          room for it; below about 24 px tall, use the mark alone.
        </p>
        <div className="mt-8 grid gap-4 lg:grid-cols-2">
          {LOCKUPS.map((a) => (
            <Tile key={a.title} asset={a} wide />
          ))}
        </div>
      </section>

      <section>
        <p className="eyebrow">Banners</p>
        <div className="mt-8 grid gap-4 lg:grid-cols-3">
          {BANNERS.map((a) => (
            <Tile key={a.title} asset={a} wide />
          ))}
        </div>
      </section>

      <section>
        <p className="eyebrow">Colour and type</p>
        <div className="mt-8 grid gap-4 lg:grid-cols-[1.4fr_1fr]">
          <div className="panel">
            <div className="panel-head">
              <span>palette</span>
              <span>3 colours</span>
            </div>
            <div className="grid divide-line sm:grid-cols-3 sm:divide-x">
              {COLOURS.map((c) => (
                <div key={c.hex} className="px-5 py-6">
                  <span aria-hidden className="block h-12 w-full border border-line" style={{ background: c.hex }} />
                  <p className="mt-4 text-[13px]">{c.name}</p>
                  <p className="mt-1 text-[12px] text-accent-ink">{c.hex}</p>
                  <p className="mini mt-2">{c.use}</p>
                </div>
              ))}
            </div>
          </div>

          <div className="panel flex flex-col">
            <div className="panel-head">
              <span>type</span>
              <span>3 faces</span>
            </div>
            <div className="divide-y divide-line">
              {[
                { face: "Playfair Display 700", role: "the wordmark only, as outlines" },
                { face: "Inter Tight 700", role: "display headings on the site" },
                { face: "JetBrains Mono", role: "body, labels and numbers" },
              ].map((t) => (
                <div key={t.face} className="px-5 py-4">
                  <p className="text-[13px]">{t.face}</p>
                  <p className="mini mt-1">{t.role}</p>
                </div>
              ))}
            </div>
            <div className="mt-auto border-t border-line px-5 py-4">
              <Downloads files={[{ label: "Avatar PNG 800", href: "/brand/stockpack-avatar-800.png" }]} />
            </div>
          </div>
        </div>
      </section>
    </div>
  );
}
