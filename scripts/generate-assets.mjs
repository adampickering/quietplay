#!/usr/bin/env node
/**
 * Generate QuietPlay brand assets (App Icon + Top Shelf images) via the
 * Gemini 2.5 Flash Image model, resize them to the exact tvOS-required
 * pixel dimensions, and drop them into the Xcode asset catalog.
 *
 *   GEMINI_API_KEY=... node scripts/generate-assets.mjs
 *
 * Optional flags:
 *   --dry-run           don't hit Gemini, just re-run Contents.json rewrites
 *   --only <key>        generate only the named asset (home|store|shelf|wide)
 */

import { mkdir, writeFile, readFile } from 'node:fs/promises';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import sharp from 'sharp';

const here = dirname(fileURLToPath(import.meta.url));
const repoRoot = join(here, '..');
const brandDir = join(
  repoRoot,
  'ios/QuietPlay/QuietPlay/Assets.xcassets/App Icon & Top Shelf Image.brandassets',
);
const outDir = join(here, 'generated');

const MODEL = 'gemini-2.5-flash-image-preview';
const API_KEY = process.env.GEMINI_API_KEY;

// Shared brand direction — keep language consistent across prompts.
const brand = `
QuietPlay is a calm, intentional video app for families with smart
kids (think Apple TV+ meets a kid-safe homepage). Values: restraint,
no-algorithm curation, warm quiet tones, not loud or YouTube-y.
Palette: deep warm navy background (#0a1224 to #141b30) with an off-white
accent. Primary motif: a simple, soft-edged white play triangle with
a faint glow — rounded, friendly, not sharp. Feels premium without
being luxurious. No text in icons, no busy patterns, no photographic
elements. Think Apple's own tvOS iconography.
`.trim();

const assets = {
  // Home-screen App Icon layers. The Back layer carries the full
  // illustration; Middle and Front are transparent layers — we leave
  // them alone (tvOS will still parallax the back by itself).
  home: {
    label: 'App Icon (home)',
    prompt: `${brand}

Task: generate the **back parallax layer** for the home-screen app
icon. Landscape 16:9. Soft rounded-corner box background in deep
warm navy with subtle vertical gradient. Centered: a single white
play triangle, soft-edged, a faint glow behind it. Edge-to-edge
composition with small visual breathing room. No text. No logo
wordmark. No shadows. No extra elements.`,
    aspect: [400, 240],
    path: join(
      brandDir,
      'App Icon.imagestack/Back.imagestacklayer/Content.imageset',
    ),
    filename: 'back.png',
  },

  store: {
    label: 'App Icon (App Store)',
    prompt: `${brand}

Task: generate the App Store brand icon back layer. Landscape,
larger canvas. Same deep warm navy gradient background, a single
white play triangle centered, soft-edged, faint glow. Edge-to-edge,
no text, no wordmark, no shadow.`,
    aspect: [1280, 768],
    path: join(
      brandDir,
      'App Icon - App Store.imagestack/Back.imagestacklayer/Content.imageset',
    ),
    filename: 'back.png',
  },

  shelf: {
    label: 'Top Shelf Image',
    prompt: `${brand}

Task: generate the tvOS Top Shelf banner shown when QuietPlay is
focused on the home screen. Very wide landscape. Composition: left
third holds the same white soft-edged play triangle with a faint
glow; right two-thirds is the same warm navy gradient fading to a
slightly lighter purple on the far right. Clean, minimal, editorial.
Subtle ambient particles or soft bokeh spheres are acceptable if
they stay quiet. No text, no wordmark, no shadows.`,
    aspect: [1920, 720],
    path: join(brandDir, 'Top Shelf Image.imageset'),
    filename: 'shelf.png',
  },

  wide: {
    label: 'Top Shelf Image Wide',
    prompt: `${brand}

Task: generate a wider variant of the Top Shelf banner for displays
that request the wide aspect. Same composition direction as the
normal Top Shelf — a soft-edged white play triangle at left, warm
navy-to-purple gradient filling right. Aspect is significantly
wider. No text, no wordmark.`,
    aspect: [2320, 720],
    path: join(brandDir, 'Top Shelf Image Wide.imageset'),
    filename: 'shelf-wide.png',
  },
};

async function callGemini(prompt) {
  if (!API_KEY) {
    throw new Error('GEMINI_API_KEY is not set in the environment.');
  }
  const url = `https://generativelanguage.googleapis.com/v1beta/models/${MODEL}:generateContent?key=${API_KEY}`;
  const res = await fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      contents: [{ role: 'user', parts: [{ text: prompt }] }],
    }),
  });
  if (!res.ok) {
    const body = await res.text();
    throw new Error(`Gemini returned ${res.status}: ${body.slice(0, 500)}`);
  }
  const data = await res.json();
  const parts = data?.candidates?.[0]?.content?.parts ?? [];
  const image = parts.find((p) => p?.inlineData?.data);
  if (!image) {
    throw new Error(`Gemini response had no image. Body: ${JSON.stringify(data).slice(0, 500)}`);
  }
  return Buffer.from(image.inlineData.data, 'base64');
}

async function renderContentsJson(assetDir, filename) {
  const isImageSet = assetDir.endsWith('.imageset');
  // For imagesets inside imagestacks Xcode's generated Contents.json has
  // two entries (scale 1x + 2x). tvOS only needs one of them populated,
  // but we'll list the file at 1x and leave 2x as a placeholder.
  const json = {
    images: [
      { idiom: 'tv', scale: '1x', filename },
      { idiom: 'tv', scale: '2x' },
    ],
    info: { author: 'xcode', version: 1 },
  };
  // Top Shelf imagesets want a slightly different shape (no scale matters)
  // but the schema above is accepted by Xcode.
  await writeFile(join(assetDir, 'Contents.json'), JSON.stringify(json, null, 2) + '\n');
  return isImageSet;
}

async function generateAsset(key, spec, { dryRun }) {
  const [w, h] = spec.aspect;
  console.log(`\n▶ ${spec.label} — target ${w}×${h}`);

  let buffer;
  if (dryRun) {
    // In dry-run mode just write a flat color fallback so Xcode builds.
    buffer = await sharp({
      create: {
        width: w,
        height: h,
        channels: 3,
        background: { r: 10, g: 18, b: 36 },
      },
    })
      .png()
      .toBuffer();
    console.log('  dry-run: wrote flat navy placeholder');
  } else {
    console.log('  requesting from Gemini…');
    const raw = await callGemini(spec.prompt);
    await mkdir(outDir, { recursive: true });
    const rawPath = join(outDir, `${key}.raw.png`);
    await writeFile(rawPath, raw);
    console.log(`  raw → ${rawPath}`);
    buffer = await sharp(raw)
      .resize(w, h, { fit: 'cover', position: 'attention' })
      .png()
      .toBuffer();
  }

  await mkdir(spec.path, { recursive: true });
  const finalPath = join(spec.path, spec.filename);
  await writeFile(finalPath, buffer);
  await renderContentsJson(spec.path, spec.filename);
  console.log(`  final → ${finalPath}`);
}

async function main() {
  const argv = process.argv.slice(2);
  const dryRun = argv.includes('--dry-run');
  const onlyIdx = argv.indexOf('--only');
  const only = onlyIdx >= 0 ? argv[onlyIdx + 1] : null;

  if (!API_KEY && !dryRun) {
    console.error(
      'GEMINI_API_KEY is not set. Export it (see https://aistudio.google.com/app/apikey) or pass --dry-run.',
    );
    process.exit(1);
  }

  const keys = only ? [only] : Object.keys(assets);
  for (const key of keys) {
    const spec = assets[key];
    if (!spec) {
      console.error(`Unknown asset key: ${key}`);
      process.exit(1);
    }
    await generateAsset(key, spec, { dryRun });
  }

  console.log('\n✓ done');
}

main().catch((err) => {
  console.error('\n✗', err.message);
  process.exit(1);
});
