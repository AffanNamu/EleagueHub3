// lib/leagues/fixturesShareCard.ts
//
// Mirrors fixtures_screen.dart's _FixturesShareCard / _FixturesShareRow +
// _captureShareCardPngBytes — renders the selected fixtures into a shareable
// PNG card. Dart captures an offscreen widget via RenderRepaintBoundary;
// web has no DOM-to-image capture without adding a new dependency
// (html2canvas etc.), so this draws the identical card layout directly with
// the Canvas 2D API instead and exports a PNG Blob.

export interface ShareCardMatch {
  roundNumber: number;
  groupId?: string | null;
  sortIndex: number;
  homeTeamId: string;
  awayTeamId: string;
  homeScore: number | null;
  awayScore: number | null;
}

export interface FixturesShareCardPayload {
  leagueName: string;
  leagueLogoUrl?: string;
  subtitle?: string; // selected group, for Group/World Cup formats
  matches: ShareCardMatch[];
  teamNames: Record<string, string>;
}

const CARD_WIDTH = 720;
const PAD = 28;
const MAX_ITEMS = 12;

function roundRect(ctx: CanvasRenderingContext2D, x: number, y: number, w: number, h: number, r: number) {
  ctx.beginPath();
  ctx.moveTo(x + r, y);
  ctx.arcTo(x + w, y, x + w, y + h, r);
  ctx.arcTo(x + w, y + h, x, y + h, r);
  ctx.arcTo(x, y + h, x, y, r);
  ctx.arcTo(x, y, x + w, y, r);
  ctx.closePath();
}

function truncateToWidth(ctx: CanvasRenderingContext2D, text: string, maxWidth: number): string {
  if (ctx.measureText(text).width <= maxWidth) return text;
  let out = text;
  while (out.length > 1 && ctx.measureText(`${out}…`).width > maxWidth) {
    out = out.slice(0, -1);
  }
  return `${out}…`;
}

async function loadImage(url: string): Promise<HTMLImageElement | null> {
  return new Promise((resolve) => {
    const img = new Image();
    img.crossOrigin = 'anonymous';
    img.onload = () => resolve(img);
    img.onerror = () => resolve(null);
    img.src = url;
    setTimeout(() => resolve(null), 6000);
  });
}

export async function renderFixturesShareCardPng(payload: FixturesShareCardPayload): Promise<Blob> {
  const sorted = [...payload.matches].sort((a, b) => {
    if (a.roundNumber !== b.roundNumber) return a.roundNumber - b.roundNumber;
    return a.sortIndex - b.sortIndex;
  });
  const shown = sorted.slice(0, MAX_ITEMS);
  const extra = Math.max(0, sorted.length - shown.length);

  const rowH = 66;
  const headerH = 84;
  const footerH = 46;
  const dividerGap = 22;
  const extraLineH = extra > 0 ? 26 : 0;
  const height = PAD * 2 + headerH + dividerGap + shown.length * (rowH + 10) + extraLineH + dividerGap + footerH;

  const canvas = document.createElement('canvas');
  const scale = 2; // crisp export
  canvas.width = CARD_WIDTH * scale;
  canvas.height = height * scale;
  const ctx = canvas.getContext('2d');
  if (!ctx) throw new Error('Canvas not supported.');
  ctx.scale(scale, scale);

  // Background card with a subtle lime-tinted gradient, matching the Dart card.
  const base = '#0B1220';
  const grad = ctx.createLinearGradient(0, 0, CARD_WIDTH, height);
  grad.addColorStop(0, '#132018');
  grad.addColorStop(1, base);
  roundRect(ctx, 0, 0, CARD_WIDTH, height, 22);
  ctx.fillStyle = grad;
  ctx.fill();
  ctx.strokeStyle = 'rgba(255,255,255,0.18)';
  ctx.lineWidth = 1;
  ctx.stroke();

  const fg = '#FFFFFF';
  const lime = '#BEF264';

  // Header: logo, name/title/subtitle, "N selected" badge.
  const logoSize = 44;
  const logoX = PAD;
  const logoY = PAD;
  roundRect(ctx, logoX, logoY, logoSize, logoSize, 14);
  ctx.fillStyle = 'rgba(190,242,100,0.12)';
  ctx.fill();
  ctx.strokeStyle = 'rgba(190,242,100,0.35)';
  ctx.stroke();

  if (payload.leagueLogoUrl?.trim()) {
    const img = await loadImage(payload.leagueLogoUrl.trim());
    if (img) {
      ctx.save();
      roundRect(ctx, logoX, logoY, logoSize, logoSize, 14);
      ctx.clip();
      ctx.drawImage(img, logoX, logoY, logoSize, logoSize);
      ctx.restore();
    } else {
      ctx.fillStyle = lime;
      ctx.font = '700 20px sans-serif';
      ctx.textAlign = 'center';
      ctx.textBaseline = 'middle';
      ctx.fillText('🏆', logoX + logoSize / 2, logoY + logoSize / 2 + 1);
    }
  } else {
    ctx.fillStyle = lime;
    ctx.font = '700 20px sans-serif';
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    ctx.fillText('🏆', logoX + logoSize / 2, logoY + logoSize / 2 + 1);
  }

  const textX = logoX + logoSize + 12;
  ctx.textAlign = 'left';
  ctx.textBaseline = 'alphabetic';

  const safeLeagueName = payload.leagueName.trim() || 'League';
  ctx.fillStyle = 'rgba(255,255,255,0.78)';
  ctx.font = '900 12px sans-serif';
  ctx.fillText(truncateToWidth(ctx, safeLeagueName, 380), textX, logoY + 14);

  ctx.fillStyle = fg;
  ctx.font = '900 20px sans-serif';
  ctx.fillText('Fixtures', textX, logoY + 36);

  if (payload.subtitle?.trim()) {
    ctx.fillStyle = 'rgba(255,255,255,0.75)';
    ctx.font = '800 12px sans-serif';
    ctx.fillText(payload.subtitle.trim(), textX, logoY + 54);
  }

  const badgeText = `${payload.matches.length} selected`;
  ctx.font = '900 12px sans-serif';
  const badgeW = ctx.measureText(badgeText).width + 20;
  const badgeX = CARD_WIDTH - PAD - badgeW;
  const badgeY = logoY + 8;
  roundRect(ctx, badgeX, badgeY, badgeW, 26, 13);
  ctx.fillStyle = 'rgba(255,255,255,0.06)';
  ctx.fill();
  ctx.strokeStyle = 'rgba(255,255,255,0.18)';
  ctx.stroke();
  ctx.fillStyle = 'rgba(255,255,255,0.85)';
  ctx.textAlign = 'center';
  ctx.fillText(badgeText, badgeX + badgeW / 2, badgeY + 17);
  ctx.textAlign = 'left';

  let y = PAD + headerH;
  ctx.strokeStyle = 'rgba(255,255,255,0.18)';
  ctx.beginPath();
  ctx.moveTo(PAD, y);
  ctx.lineTo(CARD_WIDTH - PAD, y);
  ctx.stroke();
  y += dividerGap;

  // Match rows.
  for (const m of shown) {
    const rowX = PAD;
    const rowW = CARD_WIDTH - PAD * 2;
    roundRect(ctx, rowX, y, rowW, rowH, 16);
    ctx.fillStyle = 'rgba(255,255,255,0.05)';
    ctx.fill();
    ctx.strokeStyle = 'rgba(255,255,255,0.18)';
    ctx.stroke();

    const chipText = `R${m.roundNumber}`;
    ctx.font = '900 12px sans-serif';
    const chipW = ctx.measureText(chipText).width + 20;
    const chipX = rowX + 12;
    const chipY = y + 12;
    roundRect(ctx, chipX, chipY, chipW, 24, 12);
    ctx.fillStyle = 'rgba(190,242,100,0.16)';
    ctx.fill();
    ctx.strokeStyle = 'rgba(190,242,100,0.30)';
    ctx.stroke();
    ctx.fillStyle = lime;
    ctx.textAlign = 'center';
    ctx.fillText(chipText, chipX + chipW / 2, chipY + 16);
    ctx.textAlign = 'left';

    const group = (m.groupId || '').trim();
    if (group) {
      ctx.fillStyle = 'rgba(255,255,255,0.70)';
      ctx.font = '900 10px sans-serif';
      ctx.textAlign = 'center';
      ctx.fillText(group, chipX + chipW / 2, chipY + 36);
      ctx.textAlign = 'left';
    }

    const homeName = (payload.teamNames[m.homeTeamId] || 'TBD').trim();
    const awayName = (payload.teamNames[m.awayTeamId] || 'TBD').trim();
    const matchup = `${homeName} vs ${awayName}`;
    const matchupX = chipX + chipW + 16;
    const hasScore = m.homeScore != null && m.awayScore != null;
    const scoreText = hasScore ? `${m.homeScore}  -  ${m.awayScore}` : 'vs';

    ctx.font = '900 13px sans-serif';
    const scoreW = ctx.measureText(scoreText).width + 24;
    const matchupMaxW = rowW - (matchupX - rowX) - scoreW - 22;

    ctx.fillStyle = 'rgba(255,255,255,0.96)';
    ctx.font = '900 14px sans-serif';
    ctx.fillText(truncateToWidth(ctx, matchup, matchupMaxW), matchupX, y + rowH / 2 + 5);

    const scoreX = rowX + rowW - scoreW - 12;
    const scoreY = y + (rowH - 34) / 2;
    roundRect(ctx, scoreX, scoreY, scoreW, 34, 12);
    ctx.fillStyle = hasScore ? 'rgba(190,242,100,0.16)' : 'rgba(255,255,255,0.06)';
    ctx.fill();
    ctx.strokeStyle = hasScore ? 'rgba(190,242,100,0.30)' : 'rgba(255,255,255,0.18)';
    ctx.stroke();
    ctx.fillStyle = hasScore ? lime : 'rgba(255,255,255,0.75)';
    ctx.font = '900 13px sans-serif';
    ctx.textAlign = 'center';
    ctx.fillText(scoreText, scoreX + scoreW / 2, scoreY + 22);
    ctx.textAlign = 'left';

    y += rowH + 10;
  }

  if (extra > 0) {
    ctx.fillStyle = 'rgba(255,255,255,0.70)';
    ctx.font = '900 12px sans-serif';
    ctx.fillText(`+${extra} more`, PAD, y + 8);
    y += extraLineH;
  }

  ctx.strokeStyle = 'rgba(255,255,255,0.18)';
  ctx.beginPath();
  ctx.moveTo(PAD, y + 8);
  ctx.lineTo(CARD_WIDTH - PAD, y + 8);
  ctx.stroke();

  ctx.fillStyle = 'rgba(255,255,255,0.75)';
  ctx.font = '800 12px sans-serif';
  ctx.fillText('🔒 Shared from fixtures', PAD, y + 32);

  ctx.fillStyle = lime;
  ctx.font = '900 12px sans-serif';
  const brandText = 'eSportlyic league';
  const brandW = ctx.measureText(brandText).width;
  ctx.fillText(brandText, CARD_WIDTH - PAD - brandW, y + 32);

  return new Promise((resolve, reject) => {
    canvas.toBlob((blob) => {
      if (blob) resolve(blob);
      else reject(new Error('Failed to encode share image.'));
    }, 'image/png');
  });
}
