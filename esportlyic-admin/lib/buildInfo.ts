// lib/buildInfo.ts
//
// Best-effort, read-only build/version info for every sub-project in
// this monorepo (mobile app, web_client, this admin panel, the
// Cloudflare Worker), read directly from the files this deployment was
// built from -- there's no version tracked anywhere in Firestore (no
// app writes its own version to a user doc, no remote-config-style
// min-version doc exists) and no cross-project deploy registry, so this
// is the only real signal available without inventing new
// infrastructure.
//
// Every read is defensive: if this admin panel is ever deployed from a
// checkout that doesn't include the sibling directories (e.g. a
// monorepo split where only esportlyic-admin/ ships), the corresponding
// field comes back null rather than throwing -- the page renders
// "unavailable" for that one entry instead of failing outright.

import 'server-only';

import fs from 'node:fs';
import path from 'node:path';
import { execSync } from 'node:child_process';

export interface BuildInfo {
  adminVersion: string | null;
  webClientVersion: string | null;
  mobileAppVersion: string | null;
  workerVersion: string | null;
  gitCommitSha: string | null;
}

function readJsonVersion(relativePath: string): string | null {
  try {
    const raw = fs.readFileSync(path.join(process.cwd(), relativePath), 'utf8');
    const parsed = JSON.parse(raw) as { version?: unknown };
    return typeof parsed.version === 'string' ? parsed.version : null;
  } catch {
    return null;
  }
}

function readPubspecVersion(relativePath: string): string | null {
  try {
    const raw = fs.readFileSync(path.join(process.cwd(), relativePath), 'utf8');
    const match = raw.match(/^version:\s*(\S+)/m);
    return match?.[1] ?? null;
  } catch {
    return null;
  }
}

function readGitCommitSha(): string | null {
  if (process.env.VERCEL_GIT_COMMIT_SHA) return process.env.VERCEL_GIT_COMMIT_SHA.slice(0, 12);
  try {
    return execSync('git rev-parse --short HEAD', { cwd: process.cwd(), timeout: 2000 })
      .toString()
      .trim();
  } catch {
    return null;
  }
}

export function getBuildInfo(): BuildInfo {
  return {
    adminVersion: readJsonVersion('package.json'),
    webClientVersion: readJsonVersion('../web_client/package.json'),
    mobileAppVersion: readPubspecVersion('../pubspec.yaml'),
    workerVersion: readJsonVersion('../worker/package.json'),
    gitCommitSha: readGitCommitSha(),
  };
}
