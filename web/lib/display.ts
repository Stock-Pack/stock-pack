import { encodePacked, formatUnits, keccak256 } from "viem";

/** Mirrors StockPackRenderer._sanitize: printable ASCII minus <>, capped length. */
export function sanitizeName(name: string, maxLen = 31): string {
  let out = "";
  for (const ch of name) {
    const c = ch.charCodeAt(0);
    if (c >= 0x20 && c <= 0x7e && ch !== "<" && ch !== ">") out += ch;
    if (out.length >= maxLen) break;
  }
  return out;
}

/** Mirrors the on-chain accent hue: keccak256(abi.encodePacked(sanitizedName, creator)) % 360. */
export function accentHue(name: string, creator: `0x${string}`): number {
  const h = keccak256(encodePacked(["string", "address"], [sanitizeName(name), creator]));
  return Number(BigInt(h) % 360n);
}

/** Mirrors SVGCard.formatAmount: ≤2 truncated decimals for ≥0.01; up to 6 trimmed
 *  decimals below that ("0.005", "0.000123"); "<0.000001" under card precision. */
export function formatAmount(raw: bigint, decimals: number): string {
  if (raw === 0n) return "0";
  const dec = Math.min(decimals, 77);
  const unit = 10n ** BigInt(dec);
  const whole = raw / unit;
  const frac2 = ((raw % unit) * 100n) / unit;
  if (whole === 0n && frac2 === 0n) {
    const frac6 = dec >= 6 ? raw / (unit / 1_000_000n) : raw * 10n ** BigInt(6 - dec);
    if (frac6 === 0n) return "<0.000001";
    return `0.${frac6.toString().padStart(6, "0").replace(/0+$/, "")}`;
  }
  if (frac2 === 0n) return whole.toString();
  if (frac2 % 10n === 0n) return `${whole}.${frac2 / 10n}`;
  return `${whole}.${frac2 < 10n ? "0" : ""}${frac2}`;
}

/** Full-precision input parsing helper re-export shape (UI convenience). */
export function fullAmount(raw: bigint, decimals: number): string {
  return formatUnits(raw, decimals);
}

export function shortAddress(a: string): string {
  return `${a.slice(0, 6)}…${a.slice(-4)}`;
}

export function sealedDate(unixSeconds: number): string {
  if (!unixSeconds) return "—";
  return new Date(unixSeconds * 1000).toISOString().slice(0, 10);
}
