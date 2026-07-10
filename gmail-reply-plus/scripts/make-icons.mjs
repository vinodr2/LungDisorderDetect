// Generates the extension PNG icons with zero dependencies (Node zlib only).
// Draws a rounded blue tile with a white envelope + reply arrow, at 16/48/128.
//
//   node scripts/make-icons.mjs
//
// Re-run whenever you want to tweak the mark; the PNGs are committed so a plain
// `npm run build` never needs this.

import { deflateSync } from "node:zlib";
import { writeFileSync, mkdirSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");

const ACCENT = [26, 115, 232]; // Google blue
const WHITE = [255, 255, 255];

function crc32(buf) {
  let c = ~0;
  for (let i = 0; i < buf.length; i++) {
    c ^= buf[i];
    for (let k = 0; k < 8; k++) c = (c >>> 1) ^ (0xedb88320 & -(c & 1));
  }
  return ~c >>> 0;
}

function chunk(type, data) {
  const len = Buffer.alloc(4);
  len.writeUInt32BE(data.length, 0);
  const typeBuf = Buffer.from(type, "latin1");
  const body = Buffer.concat([typeBuf, data]);
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(body), 0);
  return Buffer.concat([len, body, crc]);
}

function encodePng(size, pixels) {
  // pixels: Uint8Array RGBA, length size*size*4
  const sig = Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]);
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(size, 0);
  ihdr.writeUInt32BE(size, 4);
  ihdr[8] = 8; // bit depth
  ihdr[9] = 6; // colour type RGBA
  // 10,11,12 = compression, filter, interlace = 0
  const stride = size * 4;
  const raw = Buffer.alloc((stride + 1) * size);
  for (let y = 0; y < size; y++) {
    raw[y * (stride + 1)] = 0; // filter: none
    pixels.copy
      ? pixels.copy(raw, y * (stride + 1) + 1, y * stride, y * stride + stride)
      : Buffer.from(pixels.subarray(y * stride, y * stride + stride)).copy(
          raw,
          y * (stride + 1) + 1,
        );
  }
  const idat = deflateSync(raw, { level: 9 });
  return Buffer.concat([
    sig,
    chunk("IHDR", ihdr),
    chunk("IDAT", idat),
    chunk("IEND", Buffer.alloc(0)),
  ]);
}

function draw(size) {
  const px = Buffer.alloc(size * size * 4);
  const s = size;
  const radius = s * 0.22;

  const inRounded = (x, y) => {
    const rx = Math.min(x, s - 1 - x);
    const ry = Math.min(y, s - 1 - y);
    if (rx >= radius || ry >= radius) return true;
    const dx = radius - rx;
    const dy = radius - ry;
    return dx * dx + dy * dy <= radius * radius;
  };

  // Envelope geometry (a centred rectangle with a V flap).
  const ex0 = s * 0.24, ex1 = s * 0.76;
  const ey0 = s * 0.34, ey1 = s * 0.66;
  const cx = s * 0.5;

  const onEnvelope = (x, y) => {
    if (x < ex0 || x > ex1 || y < ey0 || y > ey1) return false;
    // Flap: two lines from top corners meeting at centre just below the top.
    const t = (x - ex0) / (ex1 - ex0);
    const flapY = ey0 + Math.abs(0.5 - t) * (ey1 - ey0) * 0.9;
    const stroke = Math.max(1, s * 0.035);
    // envelope border
    const border =
      x <= ex0 + stroke || x >= ex1 - stroke || y <= ey0 + stroke || y >= ey1 - stroke;
    const flap = Math.abs(y - flapY) <= stroke && y < ey0 + (ey1 - ey0) * 0.62;
    return border || flap;
  };

  // Reply arrow tucked at bottom-left of the envelope.
  const onArrow = (x, y) => {
    const ax = s * 0.5, ay = s * 0.72;
    const stroke = Math.max(1, s * 0.04);
    const shaft = Math.abs(y - ay) <= stroke && x >= cx - s * 0.02 && x <= ax + s * 0.14;
    const headTop = Math.abs(x - (cx - s * 0.02) - (y - ay)) <= stroke && y <= ay && y >= ay - s * 0.09;
    const headBot = Math.abs(x - (cx - s * 0.02) + (y - ay)) <= stroke && y >= ay && y <= ay + s * 0.09;
    return shaft || headTop || headBot;
  };

  for (let y = 0; y < s; y++) {
    for (let x = 0; x < s; x++) {
      const i = (y * s + x) * 4;
      if (!inRounded(x + 0.5, y + 0.5)) {
        px[i + 3] = 0; // transparent outside the tile
        continue;
      }
      let color = ACCENT;
      if (onEnvelope(x + 0.5, y + 0.5) || onArrow(x + 0.5, y + 0.5)) color = WHITE;
      px[i] = color[0];
      px[i + 1] = color[1];
      px[i + 2] = color[2];
      px[i + 3] = 255;
    }
  }
  return px;
}

const outDir = resolve(root, "icons");
mkdirSync(outDir, { recursive: true });
for (const size of [16, 48, 128]) {
  const png = encodePng(size, draw(size));
  writeFileSync(resolve(outDir, `icon${size}.png`), png);
  console.log(`icons/icon${size}.png (${png.length} bytes)`);
}
