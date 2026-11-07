/**
 * ملف بطاقة الغيار الذي يُرسل على واتساب.
 * الشعار فوق اسم المحل، ثم جدول البيان/التفاصيل، ثم رقم التواصل،
 * واسم المكان مكتوباً، ورمز QR فقط بلا رابط ظاهر.
 *
 * الحروف تُرسم مسارات بعد تشكيل حقيقي، حتى لا يعيد عارض الجوال ترتيبها.
 */

import {
  PDFDocument,
  appendBezierCurve,
  closePath,
  fill,
  lineTo,
  moveTo,
  popGraphicsState,
  pushGraphicsState,
  rgb,
  setFillingColor,
  type PDFDocument as PdfDoc,
  type PDFImage,
  type PDFPage,
  type PDFOperator,
} from 'https://esm.sh/pdf-lib@1.17.1';
import * as fontkitNs from 'https://esm.sh/@pdf-lib/fontkit@1.1.1';
import hbjsFactory from 'npm:harfbuzzjs@0.3.6/hbjs.js';

const fontkit = (
  (fontkitNs as unknown as { default?: { create: (bytes: Uint8Array) => FkFont } }).default ??
  (fontkitNs as unknown as { create: (bytes: Uint8Array) => FkFont })
);

const PAGE_WIDTH = 270;
const MARGIN = 16;

const INK = rgb(11 / 255, 31 / 255, 74 / 255);
const MUTED = rgb(92 / 255, 107 / 255, 122 / 255);
const GOLD = rgb(201 / 255, 162 / 255, 39 / 255);
const LINE = rgb(213 / 255, 219 / 255, 227 / 255);
const HEADER_BG = rgb(238 / 255, 242 / 255, 246 / 255);
const ALT_BG = rgb(247 / 255, 248 / 255, 250 / 255);
const WHITE = rgb(1, 1, 1);

const LABELS: Array<[string, string]> = [
  ['customer', 'الزبون'],
  ['car', 'السيارة'],
  ['car_model', 'الموديل'],
  ['plate', 'اللوحة'],
  ['engine', 'المحرك'],
  ['odo_current', 'العداد'],
  ['odo_next', 'الغيار القادم'],
  ['oil_brand', 'الزيت'],
  ['oil_grade', 'اللزوجة'],
  ['oil_size', 'الكمية'],
  ['hyd_gear', 'هيدروليك القير'],
  ['hyd_power', 'هيدروليك الباور'],
  ['filters', 'الفلاتر'],
  ['products', 'منتجات'],
  ['services', 'خدمات'],
  ['price_before', 'قبل التخفيض'],
  ['discount', 'الخصم'],
  ['total', 'الإجمالي'],
  ['paid', 'المدفوع'],
  ['remaining', 'المتبقي'],
  ['employee', 'الفني'],
  ['notes', 'ملاحظات'],
];

type Rgb = ReturnType<typeof rgb>;

type FkGlyph = {
  name?: string;
  path: { commands: Array<{ command: string; args: number[] }> };
};

type FkFont = {
  unitsPerEm: number;
  ascent: number;
  descent: number;
  getGlyph: (id: number) => FkGlyph;
};

type HbGlyph = { id: number; ax: number; dx: number; dy: number };

type HbFont = { destroy: () => void };

type HbBlob = { destroy: () => void };

type HbFace = { destroy: () => void };

type HbBuffer = {
  addText: (text: string) => void;
  setDirection: (dir: 'ltr' | 'rtl') => void;
  setScript: (script: string) => void;
  json: () => Array<Record<string, number>>;
  destroy: () => void;
};

type HbApi = {
  createBlob: (bytes: Uint8Array) => HbBlob;
  createFace: (blob: HbBlob, index: number) => HbFace;
  createFont: (face: HbFace) => HbFont;
  createBuffer: () => HbBuffer;
  shape: (font: HbFont, buffer: HbBuffer) => void;
};

type Face = { fk: FkFont; hb: HbFont };

let hbApi: HbApi | null = null;

async function harfbuzz(): Promise<HbApi> {
  if (hbApi) return hbApi;
  const wasm = await fetch(new URL('./hb.wasm', import.meta.url));
  if (!wasm.ok) throw new Error('hb_wasm_missing');
  const { instance } = await WebAssembly.instantiate(await wasm.arrayBuffer());
  const factory = hbjsFactory as unknown as (instance: WebAssembly.Instance) => HbApi;
  hbApi = factory(instance);
  return hbApi;
}

function useful(raw: unknown): string | null {
  const s = String(raw ?? '').trim();
  if (!s || s === '-' || s === '—') return null;
  return s;
}

function hasArabic(text: string): boolean {
  return /[\u0600-\u06FF]/.test(text);
}

const LTR_RUN = /([0-9A-Za-z@:/?&=._+\-#%,]+)/;

export type PdfLineRun = { text: string; ltr: boolean };

/** يفصل الأرقام واللاتيني عن العربي، ويبقي كل خانة رقم كما كُتبت. */
export function pdfLineRuns(logical: string): PdfLineRun[] {
  const raw = String(logical ?? '');
  return raw.split(LTR_RUN).filter((part: string) => part.length > 0).map((text: string) => ({
    text,
    ltr: /^[0-9A-Za-z@:/?&=._+\-#%,]+$/.test(text),
  }));
}

function glyphOf(raw: Record<string, number>): HbGlyph {
  return {
    id: Number(raw.g ?? raw.GlyphId ?? 0),
    ax: Number(raw.ax ?? raw.XAdvance ?? 0),
    dx: Number(raw.dx ?? raw.XOffset ?? 0),
    dy: Number(raw.dy ?? raw.YOffset ?? 0),
  };
}

function shapeRun(hb: HbApi, font: HbFont, text: string, rtl: boolean): HbGlyph[] {
  if (!text) return [];
  const buffer = hb.createBuffer();
  buffer.addText(text);
  buffer.setDirection(rtl ? 'rtl' : 'ltr');
  buffer.setScript(rtl ? 'Arab' : 'Latn');
  hb.shape(font, buffer);
  const glyphs = buffer.json().map(glyphOf);
  buffer.destroy();
  return glyphs;
}

function isRtl(run: PdfLineRun): boolean {
  return !run.ltr && hasArabic(run.text);
}

/** ترتيب الرسم من اليسار إلى اليمين بعد تشكيل كل خانة وحدها. */
export function lineGlyphs(hb: HbApi, face: HbFont, logical: string): HbGlyph[] {
  const out: HbGlyph[] = [];
  const runs = pdfLineRuns(logical);
  for (let i = runs.length - 1; i >= 0; i--) {
    const run = runs[i];
    out.push(...shapeRun(hb, face, run.text, isRtl(run)));
  }
  return out;
}

export async function lineGlyphNames(fontBytes: Uint8Array, logical: string): Promise<string[]> {
  const hb = await harfbuzz();
  const opened = openFace(hb, fontBytes);
  try {
    return lineGlyphs(hb, opened.face.hb, logical).map((g) =>
      opened.face.fk.getGlyph(g.id).name ?? ''
    );
  } finally {
    closeFace(opened);
  }
}

function unitsWidth(glyphs: HbGlyph[]): number {
  return glyphs.reduce((sum, g) => sum + g.ax, 0);
}

function scaleOf(font: FkFont, size: number): number {
  return size / (font.unitsPerEm || 1000);
}

function openFace(hb: HbApi, bytes: Uint8Array): { face: Face; blob: HbBlob; hbFace: HbFace } {
  const fk = fontkit.create(bytes);
  const blob = hb.createBlob(bytes);
  const hbFace = hb.createFace(blob, 0);
  const hbFont = hb.createFont(hbFace);
  return { face: { fk, hb: hbFont }, blob, hbFace };
}

function closeFace(opened: { face: Face; blob: HbBlob; hbFace: HbFace }): void {
  opened.face.hb.destroy();
  opened.hbFace.destroy();
  opened.blob.destroy();
}

function emitGlyphPath(
  ops: PDFOperator[],
  glyph: FkGlyph,
  originX: number,
  originY: number,
  scale: number,
): void {
  const commands = glyph.path?.commands ?? [];
  let cx = originX;
  let cy = originY;
  for (const cmd of commands) {
    const a = cmd.args ?? [];
    if (cmd.command === 'moveTo') {
      cx = originX + a[0] * scale;
      cy = originY + a[1] * scale;
      ops.push(moveTo(cx, cy));
    } else if (cmd.command === 'lineTo') {
      cx = originX + a[0] * scale;
      cy = originY + a[1] * scale;
      ops.push(lineTo(cx, cy));
    } else if (cmd.command === 'quadraticCurveTo') {
      const qx = originX + a[0] * scale;
      const qy = originY + a[1] * scale;
      const ex = originX + a[2] * scale;
      const ey = originY + a[3] * scale;
      const c1x = cx + (2 / 3) * (qx - cx);
      const c1y = cy + (2 / 3) * (qy - cy);
      const c2x = ex + (2 / 3) * (qx - ex);
      const c2y = ey + (2 / 3) * (qy - ey);
      ops.push(appendBezierCurve(c1x, c1y, c2x, c2y, ex, ey));
      cx = ex;
      cy = ey;
    } else if (cmd.command === 'bezierCurveTo' || cmd.command === 'curveTo') {
      const x1 = originX + a[0] * scale;
      const y1 = originY + a[1] * scale;
      const x2 = originX + a[2] * scale;
      const y2 = originY + a[3] * scale;
      const ex = originX + a[4] * scale;
      const ey = originY + a[5] * scale;
      ops.push(appendBezierCurve(x1, y1, x2, y2, ex, ey));
      cx = ex;
      cy = ey;
    } else if (cmd.command === 'closePath') {
      ops.push(closePath());
    }
  }
}

function paintGlyphs(
  page: PDFPage,
  fk: FkFont,
  glyphs: HbGlyph[],
  left: number,
  baseline: number,
  size: number,
  color: Rgb,
): void {
  if (!glyphs.length) return;
  const scale = scaleOf(fk, size);
  const ops: PDFOperator[] = [pushGraphicsState(), setFillingColor(color)];
  let x = left;
  for (const g of glyphs) {
    if (g.id) {
      emitGlyphPath(
        ops,
        fk.getGlyph(g.id),
        x + g.dx * scale,
        baseline + g.dy * scale,
        scale,
      );
    }
    x += g.ax * scale;
  }
  ops.push(fill(), popGraphicsState());
  page.pushOperators(...ops);
}

function textWidth(hb: HbApi, face: Face, text: string, size: number): number {
  const glyphs = lineGlyphs(hb, face.hb, text);
  return unitsWidth(glyphs) * scaleOf(face.fk, size);
}

function fitSize(hb: HbApi, face: Face, text: string, maxWidth: number, start: number): number {
  let size = start;
  while (size > 7 && textWidth(hb, face, text, size) > maxWidth) size -= 0.5;
  return size;
}

function baselineOf(fk: FkFont, size: number, boxBottom: number, boxHeight: number): number {
  const scale = scaleOf(fk, size);
  const ascent = Math.abs(fk.ascent || 940) * scale;
  const descent = Math.abs(fk.descent || 240) * scale;
  return boxBottom + (boxHeight - (ascent + descent)) / 2 + descent;
}

type QrGrid = { size: number; data: unknown };

function qrModuleOn(grid: QrGrid, row: number, col: number): boolean {
  const data = grid.data;
  if (Array.isArray(data)) {
    const line = data[row];
    if (Array.isArray(line) || line instanceof Uint8Array) return !!line[col];
  }
  if (data instanceof Uint8Array) return data[row * grid.size + col] !== 0;
  return false;
}

async function drawQr(
  page: PDFPage,
  text: string,
  centerX: number,
  bottomY: number,
  size: number,
): Promise<void> {
  const { encode } = await import('npm:uqr@0.1.3');
  const grid = encode(text) as QrGrid;
  const n = grid.size;
  if (!n) return;
  const quiet = 2;
  const cell = size / (n + quiet * 2);
  const originX = centerX - size / 2;
  for (let row = 0; row < n; row++) {
    for (let col = 0; col < n; col++) {
      if (!qrModuleOn(grid, row, col)) continue;
      page.drawRectangle({
        x: originX + (col + quiet) * cell,
        y: bottomY + (n - 1 - row + quiet) * cell,
        width: cell + 0.15,
        height: cell + 0.15,
        color: INK,
      });
    }
  }
}

async function embedLogo(doc: PdfDoc, bytes: Uint8Array): Promise<PDFImage | null> {
  try {
    if (bytes[0] === 0x89) return await doc.embedPng(bytes);
    if (bytes[0] === 0xff && bytes[1] === 0xd8) return await doc.embedJpg(bytes);
  } catch {
    return null;
  }
  return null;
}

export async function buildFallbackOilCardPdf(args: {
  fontBytes: Uint8Array;
  boldFontBytes?: Uint8Array | null;
  logoBytes?: Uint8Array | null;
  shopName?: string | null;
  address?: string | null;
  phones?: string[] | null;
  mapsUrl?: string | null;
  issuedAt?: string | null;
  card: Record<string, string> | null;
}): Promise<Uint8Array> {
  const card = args.card ?? {};
  const rows: Array<[string, string]> = [];
  for (const [key, label] of LABELS) {
    const value = useful(card[key]);
    if (!value) continue;
    rows.push([label, value]);
  }

  const shop = useful(args.shopName) ?? useful(card.shop) ?? 'بطاقة غيار الزيت';
  const address = useful(args.address);
  const phones = (args.phones ?? []).map((p) => useful(p)).filter((p): p is string => !!p);
  const maps = useful(args.mapsUrl);
  const issued = useful(args.issuedAt);
  const boldBytes = args.boldFontBytes && args.boldFontBytes.length > 1000
    ? args.boldFontBytes
    : args.fontBytes;

  const hb = await harfbuzz();
  const regular = openFace(hb, args.fontBytes);
  const bold = openFace(hb, boldBytes);

  try {
    const contentW = PAGE_WIDTH - MARGIN * 2;
    const labelW = contentW * 0.42;
    const valueW = contentW - labelW;
    const rowH = 18;
    const qrSize = 100;

    const hasLogo = !!args.logoBytes && args.logoBytes.length > 8;
    let height = MARGIN + 16;
    if (hasLogo) height += 74;
    height += 32 + 16 + 22;
    if (issued) height += 20;
    height += 12 + (rows.length + 1) * rowH + 16;
    height += phones.length * 20;
    if (address) height += 20;
    if (maps) height += qrSize + 28;
    height += MARGIN;
    height = Math.max(420, Math.min(1400, height));

    const doc = await PDFDocument.create();
    const page = doc.addPage([PAGE_WIDTH, height]);
    const logo = args.logoBytes ? await embedLogo(doc, args.logoBytes) : null;

    let top = height - MARGIN;

    if (logo) {
      const scaled = logo.scaleToFit(78, 64);
      page.drawImage(logo, {
        x: (PAGE_WIDTH - scaled.width) / 2,
        y: top - scaled.height,
        width: scaled.width,
        height: scaled.height,
      });
      top -= scaled.height + 8;
    }

    const paintCentered = (
      face: Face,
      text: string,
      size: number,
      color: Rgb,
      gap: number,
    ) => {
      const fitted = fitSize(hb, face, text, contentW, size);
      const glyphs = lineGlyphs(hb, face.hb, text);
      const width = unitsWidth(glyphs) * scaleOf(face.fk, fitted);
      const boxH = fitted + 4;
      const baseline = baselineOf(face.fk, fitted, top - boxH, boxH);
      paintGlyphs(page, face.fk, glyphs, (PAGE_WIDTH - width) / 2, baseline, fitted, color);
      top -= boxH + gap;
    };

    paintCentered(bold.face, shop, 18, INK, 2);
    const ruleW = 90;
    page.drawLine({
      start: { x: (PAGE_WIDTH - ruleW) / 2, y: top },
      end: { x: (PAGE_WIDTH + ruleW) / 2, y: top },
      thickness: 1.4,
      color: GOLD,
    });
    top -= 10;
    paintCentered(bold.face, 'بطاقة غيار الزيت', 11, INK, 1);
    if (issued) paintCentered(regular.face, `تاريخ الفاتورة: ${issued}`, 9, MUTED, 2);
    top -= 6;

    const paintCell = (
      face: Face,
      text: string,
      cellX: number,
      cellW: number,
      rowBottom: number,
      size: number,
    ) => {
      const pad = 5;
      const fitted = fitSize(hb, face, text, cellW - pad * 2, size);
      const glyphs = lineGlyphs(hb, face.hb, text);
      const width = unitsWidth(glyphs) * scaleOf(face.fk, fitted);
      const right = cellX + cellW - pad;
      const baseline = baselineOf(face.fk, fitted, rowBottom, rowH);
      paintGlyphs(page, face.fk, glyphs, right - width, baseline, fitted, INK);
    };

    const tableBottom = top - (rows.length + 1) * rowH;
    for (let i = 0; i <= rows.length; i++) {
      const rowTop = top - i * rowH;
      const rowBottom = rowTop - rowH;
      const fillColor = i === 0 ? HEADER_BG : i % 2 === 0 ? ALT_BG : WHITE;
      page.drawRectangle({
        x: MARGIN,
        y: rowBottom,
        width: contentW,
        height: rowH,
        color: fillColor,
        borderWidth: 0,
      });
      if (i === 0) {
        paintCell(bold.face, 'البيان', MARGIN + valueW, labelW, rowBottom, 9);
        paintCell(bold.face, 'التفاصيل', MARGIN, valueW, rowBottom, 9);
      } else {
        const [label, value] = rows[i - 1];
        paintCell(bold.face, label, MARGIN + valueW, labelW, rowBottom, 9);
        paintCell(regular.face, value, MARGIN, valueW, rowBottom, 9);
      }
    }
    const tableRight = MARGIN + contentW;
    page.drawLine({
      start: { x: MARGIN, y: top },
      end: { x: tableRight, y: top },
      thickness: 0.7,
      color: LINE,
    });
    page.drawLine({
      start: { x: MARGIN, y: tableBottom },
      end: { x: tableRight, y: tableBottom },
      thickness: 0.7,
      color: LINE,
    });
    page.drawLine({
      start: { x: MARGIN, y: tableBottom },
      end: { x: MARGIN, y: top },
      thickness: 0.7,
      color: LINE,
    });
    page.drawLine({
      start: { x: tableRight, y: tableBottom },
      end: { x: tableRight, y: top },
      thickness: 0.7,
      color: LINE,
    });
    page.drawLine({
      start: { x: MARGIN + valueW, y: tableBottom },
      end: { x: MARGIN + valueW, y: top },
      thickness: 0.7,
      color: LINE,
    });
    for (let i = 1; i <= rows.length; i++) {
      const y = top - i * rowH;
      page.drawLine({
        start: { x: MARGIN, y },
        end: { x: MARGIN + contentW, y },
        thickness: 0.6,
        color: LINE,
      });
    }
    top = tableBottom - 12;

    const paintLabeled = (label: string, value: string) => {
      const size = 10;
      const labelGlyphs = lineGlyphs(hb, bold.face.hb, label);
      const gapGlyphs = lineGlyphs(hb, regular.face.hb, ' ');
      const valueGlyphs = lineGlyphs(hb, regular.face.hb, value);
      const labelWidth = unitsWidth(labelGlyphs) * scaleOf(bold.face.fk, size);
      const gapWidth = unitsWidth(gapGlyphs) * scaleOf(regular.face.fk, size);
      const valueWidth = unitsWidth(valueGlyphs) * scaleOf(regular.face.fk, size);
      const boxH = size + 4;
      const baseline = baselineOf(regular.face.fk, size, top - boxH, boxH);
      let x = (PAGE_WIDTH - (labelWidth + gapWidth + valueWidth)) / 2;
      paintGlyphs(page, regular.face.fk, valueGlyphs, x, baseline, size, INK);
      x += valueWidth;
      paintGlyphs(page, regular.face.fk, gapGlyphs, x, baseline, size, INK);
      x += gapWidth;
      paintGlyphs(page, bold.face.fk, labelGlyphs, x, baseline, size, INK);
      top -= boxH + 1;
    };

    for (const phone of phones) {
      paintLabeled('رقم التواصل:', phone);
    }
    if (address) paintLabeled('الموقع:', address);
    if (maps) {
      top -= 4;
      if (top - qrSize > MARGIN) {
        await drawQr(page, maps, PAGE_WIDTH / 2, top - qrSize, qrSize);
        top -= qrSize + 2;
        paintCentered(regular.face, 'امسح لفتح الموقع', 8, MUTED, 0);
      }
    }

    return await doc.save();
  } finally {
    closeFace(regular);
    closeFace(bold);
  }
}

async function loadFontFile(names: string[]): Promise<Uint8Array> {
  for (const name of names) {
    try {
      const res = await fetch(new URL(`./fonts/${name}`, import.meta.url));
      if (!res.ok) continue;
      const buf = new Uint8Array(await res.arrayBuffer());
      if (buf.length > 1000) return buf;
    } catch {
      /* المصدر التالي */
    }
  }
  const remote = await fetch(
    'https://cdn.jsdelivr.net/gh/google/fonts@main/ofl/tajawal/Tajawal-Regular.ttf',
  );
  if (!remote.ok) throw new Error('font_missing');
  return new Uint8Array(await remote.arrayBuffer());
}

export async function loadTajawalRegular(): Promise<Uint8Array> {
  return await loadFontFile(['Tajawal-Regular.ttf']);
}

export async function loadTajawalBold(): Promise<Uint8Array> {
  return await loadFontFile(['Tajawal-Bold.ttf', 'Tajawal-Regular.ttf']);
}

export function formatInvoiceStamp(iso: string | null | undefined): string | null {
  const d = iso ? new Date(iso) : null;
  if (!d || Number.isNaN(d.getTime())) return null;
  const parts = new Intl.DateTimeFormat('en-GB', {
    timeZone: 'Asia/Baghdad',
    day: 'numeric',
    month: 'numeric',
    year: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
    hourCycle: 'h23',
  }).formatToParts(d);
  const pick = (type: string) => parts.find((p) => p.type === type)?.value ?? '';
  const day = pick('day');
  const month = pick('month');
  const year = pick('year');
  const hour = pick('hour');
  const minute = pick('minute');
  if (!day || !year) return null;
  return `${day}/${month}/${year} ${hour}:${minute}`;
}
