import { spawn } from 'node:child_process';

const FORMAT = 'best[height<=1080][ext=mp4]/best[height<=1080]/best';
// YouTube's SABR/PO-token rollout stripped the combined itag-18 URL from the
// default web client — the URLs it now returns 403 on HEAD/range, so AVPlayer
// can't play them. The tv_simply client still serves a range-capable combined
// MP4. Verified 2026-08-28; revisit if resolves start failing en masse.
const PLAYER_CLIENT = 'tv_simply';
// Typical resolve runs 16–20s on this hardware. 25s left almost no
// headroom for cipher-decode or YouTube edge-node spikes, so one
// flaky moment poisoned the FAIL cache and the kid kept hitting
// "Server's having a lie down" for the next 15 min.
const TIMEOUT_MS = 45_000;
const VIDEO_ID_RE = /^[A-Za-z0-9_-]{11}$/;

export class ResolveError extends Error {}

export interface YtDlpRunner {
  resolve(videoId: string): Promise<string>;
}

export const defaultRunner: YtDlpRunner = {
  resolve(videoId) {
    if (!VIDEO_ID_RE.test(videoId)) {
      return Promise.reject(new ResolveError('invalid video id'));
    }

    return new Promise((resolvePromise, reject) => {
      const child = spawn(
        'yt-dlp',
        [
          '-g',
          '-f',
          FORMAT,
          '--extractor-args',
          `youtube:player_client=${PLAYER_CLIENT}`,
          '--no-playlist',
          `https://www.youtube.com/watch?v=${videoId}`,
        ],
        { stdio: ['ignore', 'pipe', 'pipe'] },
      );

      let stdout = '';
      let stderr = '';
      let settled = false;

      const timer = setTimeout(() => {
        if (settled) return;
        settled = true;
        child.kill('SIGKILL');
        reject(new ResolveError('yt-dlp timeout'));
      }, TIMEOUT_MS);

      child.stdout.on('data', (chunk) => {
        stdout += chunk.toString();
      });
      child.stderr.on('data', (chunk) => {
        stderr += chunk.toString();
      });
      child.on('error', (err) => {
        if (settled) return;
        settled = true;
        clearTimeout(timer);
        reject(new ResolveError(`yt-dlp spawn failed: ${err.message}`));
      });
      child.on('close', (code) => {
        if (settled) return;
        settled = true;
        clearTimeout(timer);
        if (code !== 0) {
          reject(new ResolveError(`yt-dlp exit ${code}: ${stderr.trim().slice(0, 200)}`));
          return;
        }
        const url = stdout.split('\n').find((line) => line.trim().length > 0)?.trim();
        if (!url) {
          reject(new ResolveError('yt-dlp produced no url'));
          return;
        }
        resolvePromise(url);
      });
    });
  },
};
