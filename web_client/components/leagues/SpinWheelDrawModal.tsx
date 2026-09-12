'use client';

// Mirrors lib/features/leagues/presentation/spin_wheel_draw_screen.dart —
// an optional alternative input method for Classic League fixture generation.
//
// ARCHITECTURE NOTE: this component does NOT create, persist, or touch any
// FixtureMatch or Firestore document. It only randomizes the ORDER of the
// team list it is given and hands that order back to the caller via
// onConfirm(orderedTeams). The caller then feeds that order into the exact
// same FixtureGenerator.generateClassicLeagueFixtures(...) call used by the
// "Automatic" fixture-generation button. No new fixture data model, no new
// Firestore collection, no Security Rules changes.
//
// If the organizer backs out before confirming, onCancel() fires and
// nothing is generated or saved.

import { useMemo, useRef, useState } from 'react';
import { X, RotateCcw, Dice5, CheckCircle2, Info } from 'lucide-react';
import { Team } from '@/lib/models/leagueDetails';

const SEGMENT_COLORS = ['#1F2937', '#111827'];
const SPIN_DURATION_MS = 3200;

function shuffle<T>(list: T[]): T[] {
  const out = [...list];
  for (let i = out.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [out[i], out[j]] = [out[j], out[i]];
  }
  return out;
}

export function SpinWheelDrawModal({
  teams,
  onConfirm,
  onCancel,
}: {
  teams: Team[];
  onConfirm: (orderedTeams: Team[]) => void;
  onCancel: () => void;
}) {
  const [pool, setPool] = useState<Team[]>(() => shuffle(teams));
  const [drawnOrder, setDrawnOrder] = useState<Team[]>([]);
  const [wheelAngle, setWheelAngle] = useState(0);
  const [spinning, setSpinning] = useState(false);
  const spinTimeout = useRef<ReturnType<typeof setTimeout> | null>(null);

  const drawComplete = pool.length === 0;
  const currentMatchNumber = Math.floor(drawnOrder.length / 2) + 1;
  const pairStart = Math.floor(drawnOrder.length / 2) * 2;
  const slotA = pairStart < drawnOrder.length ? drawnOrder[pairStart] : null;
  const slotB = pairStart + 1 < drawnOrder.length ? drawnOrder[pairStart + 1] : null;

  const handleClose = () => {
    if (drawnOrder.length > 0) {
      const leave = confirm('Leave draw? Your current draw has not been confirmed. Leaving will discard the temporary pairings.');
      if (!leave) return;
    }
    onCancel();
  };

  const spin = () => {
    if (spinning || pool.length === 0) return;

    const selectedIndex = Math.floor(Math.random() * pool.length);
    const selected = pool[selectedIndex];

    const segmentCount = pool.length;
    const segmentAngle = 360 / segmentCount;
    const targetSegmentMid = selectedIndex * segmentAngle + segmentAngle / 2;

    const extraSpins = 4 + Math.floor(Math.random() * 3); // 4-6 full rotations
    const targetAngle = wheelAngle + extraSpins * 360 + (360 - targetSegmentMid);

    setSpinning(true);
    setWheelAngle(targetAngle);

    spinTimeout.current = setTimeout(() => {
      setPool((prev) => prev.filter((_, i) => i !== selectedIndex));
      setDrawnOrder((prev) => [...prev, selected]);
      setWheelAngle(targetAngle % 360);
      setSpinning(false);
    }, SPIN_DURATION_MS);
  };

  const restartDraw = () => {
    if (drawnOrder.length === 0) return;
    if (!confirm('Restart this draw? All current temporary pairings will be discarded.')) return;
    if (spinTimeout.current) clearTimeout(spinTimeout.current);
    setPool(shuffle(teams));
    setDrawnOrder([]);
    setWheelAngle(0);
    setSpinning(false);
  };

  const confirmAndGenerate = () => {
    if (!drawComplete) return;
    onConfirm(drawnOrder);
  };

  const wheelSegments = useMemo(() => {
    const n = pool.length;
    if (n === 0) return [];
    const segmentAngle = 360 / n;
    return pool.map((t, i) => {
      const startAngle = i * segmentAngle - 90 - segmentAngle / 2;
      const endAngle = startAngle + segmentAngle;
      const midAngle = startAngle + segmentAngle / 2;
      const toRad = (deg: number) => (deg * Math.PI) / 180;
      const cx = 100;
      const cy = 100;
      const r = 98;
      const x1 = cx + r * Math.cos(toRad(startAngle));
      const y1 = cy + r * Math.sin(toRad(startAngle));
      const x2 = cx + r * Math.cos(toRad(endAngle));
      const y2 = cy + r * Math.sin(toRad(endAngle));
      const largeArc = segmentAngle > 180 ? 1 : 0;
      const path = `M ${cx} ${cy} L ${x1} ${y1} A ${r} ${r} 0 ${largeArc} 1 ${x2} ${y2} Z`;
      const labelR = r * 0.62;
      const lx = cx + labelR * Math.cos(toRad(midAngle));
      const ly = cy + labelR * Math.sin(toRad(midAngle));
      const fontSize = n <= 6 ? 8 : n <= 12 ? 6.5 : n <= 20 ? 5.5 : 4.5;
      return { path, color: SEGMENT_COLORS[i % 2], label: t.name, lx, ly, midAngle, fontSize };
    });
  }, [pool]);

  const pairs: [Team, Team][] = [];
  for (let i = 0; i + 1 < drawnOrder.length; i += 2) pairs.push([drawnOrder[i], drawnOrder[i + 1]]);
  const leftover = drawnOrder.length % 2 === 1 ? drawnOrder[drawnOrder.length - 1] : null;

  return (
    <div className="fixed inset-0 z-50 bg-[#070B14] flex flex-col">
      <div className="flex items-center gap-3 p-4 border-b border-[#1E293B]">
        <button onClick={handleClose} className="p-2 bg-[#0B1221] border border-[#1E293B] rounded-xl text-white">
          <X className="w-5 h-5" />
        </button>
        <h1 className="text-lg font-black text-white">🎡 Spin Wheel Draw</h1>
      </div>

      {!drawComplete ? (
        <div className="flex-1 flex flex-col overflow-y-auto">
          <p className="text-center text-xs font-black text-gray-400 tracking-wide pt-3">Match {currentMatchNumber}</p>

          <div className="px-4 pt-2">
            <div className="bg-[#0B1221] border border-[#1E293B] rounded-2xl p-3 flex items-center gap-2">
              <SlotTile name={slotA?.name} />
              <span className="text-gray-400 font-black text-sm px-2">VS</span>
              <SlotTile name={slotB?.name} />
            </div>
          </div>

          <div className="flex-1 flex items-center justify-center py-4">
            <div className="relative w-[min(72vw,340px)] h-[min(72vw,340px)]">
              <svg
                viewBox="0 0 200 200"
                className="w-full h-full"
                style={{ transform: `rotate(${wheelAngle}deg)`, transition: spinning ? `transform ${SPIN_DURATION_MS}ms cubic-bezier(0.15,0.8,0.25,1)` : 'none' }}
              >
                {wheelSegments.map((seg, i) => (
                  <g key={i}>
                    <path d={seg.path} fill={seg.color} stroke="#BEF264" strokeOpacity={0.35} strokeWidth={0.5} />
                    <text
                      x={seg.lx}
                      y={seg.ly}
                      fill="white"
                      fontSize={seg.fontSize}
                      fontWeight={800}
                      textAnchor="middle"
                      dominantBaseline="middle"
                      transform={`rotate(${seg.midAngle + 90}, ${seg.lx}, ${seg.ly})`}
                    >
                      {seg.label.length > 14 ? `${seg.label.slice(0, 13)}…` : seg.label}
                    </text>
                  </g>
                ))}
                <circle cx="100" cy="100" r="98" fill="none" stroke="#BEF264" strokeWidth="3" />
              </svg>
              <div className="absolute inset-0 flex items-center justify-center pointer-events-none">
                <div className="w-4 h-4 rounded-full bg-[#BEF264] border-2 border-[#0F172A]" />
              </div>
              <div className="absolute -top-1 left-1/2 -translate-x-1/2 text-[#BEF264] text-2xl pointer-events-none">▼</div>
            </div>
          </div>

          <p className="text-center text-xs font-bold text-gray-400 pb-2">
            {pool.length === 0 ? 'All participants drawn' : `${pool.length} participant${pool.length === 1 ? '' : 's'} remaining`}
          </p>

          <div className="flex gap-2 p-4">
            {drawnOrder.length > 0 && (
              <button
                onClick={restartDraw}
                disabled={spinning}
                className="flex-1 py-3.5 border border-[#1E293B] text-gray-300 rounded-xl font-black text-sm hover:bg-[#1E293B] disabled:opacity-50 flex items-center justify-center gap-2"
              >
                <RotateCcw className="w-4 h-4" /> Restart
              </button>
            )}
            <button
              onClick={spin}
              disabled={spinning || pool.length === 0}
              className="flex-[2] py-3.5 bg-[#BEF264] text-[#0F172A] rounded-xl font-black text-sm hover:brightness-110 disabled:opacity-50 flex items-center justify-center gap-2"
            >
              <Dice5 className="w-4 h-4" /> {spinning ? 'Spinning…' : 'SPIN'}
            </button>
          </div>
        </div>
      ) : (
        <div className="flex-1 flex flex-col overflow-hidden">
          <p className="px-4 pt-4 pb-2 text-lg font-black text-white">🎡 Draw Complete</p>
          <div className="flex-1 overflow-y-auto px-4 space-y-2.5">
            {pairs.map((pair, i) => (
              <div key={i} className="bg-[#0B1221] border border-[#1E293B] rounded-2xl p-3.5 flex items-center gap-2">
                <span className="text-xs font-black text-gray-400 shrink-0">Match {i + 1}</span>
                <span className="flex-1 text-right font-black text-white text-sm truncate">{pair[0].name}</span>
                <span className="text-gray-500 text-xs px-2">vs</span>
                <span className="flex-1 font-black text-white text-sm truncate">{pair[1].name}</span>
              </div>
            ))}
            {leftover && (
              <div className="bg-[#0B1221] border border-[#1E293B] rounded-2xl p-3.5 flex items-start gap-2.5">
                <Info className="w-4 h-4 text-gray-400 shrink-0 mt-0.5" />
                <p className="text-xs text-gray-400 font-semibold leading-relaxed">
                  {leftover.name} — odd participant count. The league schedule rotates each team through a bye round automatically.
                </p>
              </div>
            )}
          </div>
          <div className="p-4 space-y-3">
            <p className="text-center text-xs font-bold text-gray-400">All participants have been assigned.</p>
            <div className="flex gap-2">
              <button onClick={restartDraw} className="flex-1 py-3.5 border border-[#1E293B] text-gray-300 rounded-xl font-black text-sm hover:bg-[#1E293B] flex items-center justify-center gap-2">
                <RotateCcw className="w-4 h-4" /> Restart Draw
              </button>
              <button
                onClick={confirmAndGenerate}
                className="flex-[2] py-3.5 bg-[#BEF264] text-[#0F172A] rounded-xl font-black text-sm hover:brightness-110 flex items-center justify-center gap-2"
              >
                <CheckCircle2 className="w-4 h-4" /> Confirm & Generate
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

function SlotTile({ name }: { name?: string }) {
  return (
    <div
      className={`flex-1 h-11 rounded-xl flex items-center justify-center px-2 text-xs font-black truncate ${
        name ? 'bg-[#BEF264]/10 border border-[#BEF264] text-white' : 'border border-[#1E293B] text-gray-500'
      }`}
    >
      {name || 'Waiting…'}
    </div>
  );
}
