import { SquadPlayerSlot } from './teamProfileRepository';

export interface FormationSlot {
  label: string;
  x: number;
  y: number;
}

export const FORMATION_PRESETS: Record<string, FormationSlot[]> = {
  '4-3-3': [
    { label: 'GK', x: 0.50, y: 0.06 },
    { label: 'LB', x: 0.14, y: 0.24 },
    { label: 'CB', x: 0.36, y: 0.20 },
    { label: 'CB', x: 0.64, y: 0.20 },
    { label: 'RB', x: 0.86, y: 0.24 },
    { label: 'CM', x: 0.30, y: 0.46 },
    { label: 'CM', x: 0.50, y: 0.42 },
    { label: 'CM', x: 0.70, y: 0.46 },
    { label: 'LW', x: 0.16, y: 0.78 },
    { label: 'ST', x: 0.50, y: 0.86 },
    { label: 'RW', x: 0.84, y: 0.78 },
  ],
  '4-2-3-1': [
    { label: 'GK', x: 0.50, y: 0.06 },
    { label: 'LB', x: 0.14, y: 0.24 },
    { label: 'CB', x: 0.36, y: 0.20 },
    { label: 'CB', x: 0.64, y: 0.20 },
    { label: 'RB', x: 0.86, y: 0.24 },
    { label: 'CDM', x: 0.36, y: 0.42 },
    { label: 'CDM', x: 0.64, y: 0.42 },
    { label: 'LAM', x: 0.18, y: 0.66 },
    { label: 'CAM', x: 0.50, y: 0.62 },
    { label: 'RAM', x: 0.82, y: 0.66 },
    { label: 'ST', x: 0.50, y: 0.88 },
  ],
  '4-4-2': [
    { label: 'GK', x: 0.50, y: 0.06 },
    { label: 'LB', x: 0.14, y: 0.24 },
    { label: 'CB', x: 0.36, y: 0.20 },
    { label: 'CB', x: 0.64, y: 0.20 },
    { label: 'RB', x: 0.86, y: 0.24 },
    { label: 'LM', x: 0.14, y: 0.50 },
    { label: 'CM', x: 0.38, y: 0.48 },
    { label: 'CM', x: 0.62, y: 0.48 },
    { label: 'RM', x: 0.86, y: 0.50 },
    { label: 'ST', x: 0.38, y: 0.84 },
    { label: 'ST', x: 0.62, y: 0.84 },
  ],
  '3-5-2': [
    { label: 'GK', x: 0.50, y: 0.06 },
    { label: 'CB', x: 0.26, y: 0.20 },
    { label: 'CB', x: 0.50, y: 0.16 },
    { label: 'CB', x: 0.74, y: 0.20 },
    { label: 'LWB', x: 0.08, y: 0.46 },
    { label: 'CM', x: 0.34, y: 0.44 },
    { label: 'CM', x: 0.50, y: 0.40 },
    { label: 'CM', x: 0.66, y: 0.44 },
    { label: 'RWB', x: 0.92, y: 0.46 },
    { label: 'ST', x: 0.38, y: 0.84 },
    { label: 'ST', x: 0.62, y: 0.84 },
  ],
};

export const SUPPORTED_FORMATIONS = ['4-3-3', '4-2-3-1', '4-4-2', '3-5-2'];

export function getSlotsForFormation(formation: string): FormationSlot[] {
  return FORMATION_PRESETS[formation.trim()] || FORMATION_PRESETS['4-3-3'];
}

export class FormationDetector {
  private static readonly MIN_LINE_GAP = 0.10;

  static detect(startingXI: SquadPlayerSlot[], fallback: string): string {
    if (startingXI.length === 0) return fallback;

    let gk = startingXI.find(p => p.position.trim().toUpperCase() === 'GK');
    if (!gk) {
      gk = startingXI.reduce((prev, curr) => (curr.y <= prev.y ? curr : prev));
    }

    const outfield = startingXI.filter(p => p.playerId !== gk!.playerId).sort((a, b) => a.y - b.y);
    if (outfield.length < 3) return fallback;

    const ys = outfield.map(p => p.y);
    const gaps: number[] = [];
    for (let i = 0; i < ys.length - 1; i++) gaps.push(ys[i + 1] - ys[i]);

    if (gaps.length === 0) return fallback;

    const meanGap = gaps.reduce((a, b) => a + b, 0) / gaps.length;
    const threshold = Math.max(meanGap * 1.3, this.MIN_LINE_GAP);

    let splits: number[] = [];
    for (let i = 0; i < gaps.length; i++) {
      if (gaps[i] > threshold) splits.push(i);
    }

    if (splits.length > 3) {
      splits = [...splits].sort((a, b) => gaps[b] - gaps[a]).slice(0, 3).sort((a, b) => a - b);
    }

    if (splits.length === 0) return fallback;

    const lineCounts: number[] = [];
    let start = 0;
    for (const splitIndex of splits) {
      lineCounts.push(splitIndex - start + 1);
      start = splitIndex + 1;
    }
    lineCounts.push(outfield.length - start);

    if (lineCounts.some(c => c <= 0)) return fallback;

    return lineCounts.join('-');
  }
}
