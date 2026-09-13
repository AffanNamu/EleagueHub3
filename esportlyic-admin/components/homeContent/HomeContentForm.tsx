'use client';

import { useState } from 'react';
import Image from 'next/image';
import { UploadCloud, Loader2 } from 'lucide-react';
import { useHomeContentSave } from '@/hooks/useHomeContentActions';
import { uploadHomeContentImage } from '@/lib/cloudinary/adminCloudinaryUpload';
import { FIXED_ROUTES } from '@/types/homeContent';
import type {
  AnnouncementSeverity,
  CtaDestinationType,
  HomeContentInput,
  HomeContentItem,
  HomeContentType,
} from '@/types/homeContent';

function toDateInputValue(ms: number | null): string {
  if (ms == null) return '';
  return new Date(ms).toISOString().slice(0, 10);
}

function fromDateInputValue(value: string): number | null {
  if (!value) return null;
  const parsed = Date.parse(value);
  return Number.isFinite(parsed) ? parsed : null;
}

function inferDestinationType(item?: HomeContentItem): CtaDestinationType {
  if (!item || !item.ctaRoute) return 'none';
  if (item.ctaRoute.startsWith('/leagues/')) return 'league';
  return 'fixed_route';
}

export function HomeContentForm({ existing }: { existing?: HomeContentItem }) {
  const { save, submitting, error } = useHomeContentSave(existing?.id);

  const [type, setType] = useState<HomeContentType>(existing?.type ?? 'hero');
  const [title, setTitle] = useState(existing?.title ?? '');
  const [subtitle, setSubtitle] = useState(existing?.subtitle ?? '');
  const [imageUrl, setImageUrl] = useState(existing?.imageUrl ?? '');
  const [ctaLabel, setCtaLabel] = useState(existing?.ctaLabel ?? '');
  const [destinationType, setDestinationType] = useState<CtaDestinationType>(inferDestinationType(existing));
  const [ctaLeagueId, setCtaLeagueId] = useState(existing?.ctaRoute.startsWith('/leagues/') ? existing.ctaRoute.replace('/leagues/', '') : '');
  const [ctaFixedRoute, setCtaFixedRoute] = useState(
    existing && FIXED_ROUTES.some((r) => r.value === existing.ctaRoute) ? existing.ctaRoute : (FIXED_ROUTES[0]?.value ?? ''),
  );
  const [severity, setSeverity] = useState<AnnouncementSeverity>(existing?.severity ?? 'info');
  const [active, setActive] = useState(existing?.active ?? true);
  const [order, setOrder] = useState(existing?.order ?? 0);
  const [startAt, setStartAt] = useState(toDateInputValue(existing?.startAtMs ?? null));
  const [endAt, setEndAt] = useState(toDateInputValue(existing?.endAtMs ?? null));

  const [uploading, setUploading] = useState(false);
  const [uploadError, setUploadError] = useState<string | null>(null);

  async function handleFileChange(e: React.ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0];
    if (!file) return;

    setUploading(true);
    setUploadError(null);
    try {
      const url = await uploadHomeContentImage(file);
      setImageUrl(url);
    } catch (err) {
      setUploadError(err instanceof Error ? err.message : 'Upload failed.');
    } finally {
      setUploading(false);
      e.target.value = '';
    }
  }

  async function handleSubmit() {
    const input: HomeContentInput = {
      type,
      title,
      subtitle,
      imageUrl,
      ctaLabel,
      ctaDestinationType: destinationType,
      ctaLeagueId: destinationType === 'league' ? ctaLeagueId : undefined,
      ctaFixedRoute: destinationType === 'fixed_route' ? ctaFixedRoute : undefined,
      severity,
      active,
      order,
      startAtMs: fromDateInputValue(startAt),
      endAtMs: fromDateInputValue(endAt),
    };
    await save(input);
  }

  const requiresCtaLabel = destinationType !== 'none';
  const canSubmit =
    !submitting &&
    title.trim().length > 0 &&
    (!requiresCtaLabel || ctaLabel.trim().length > 0) &&
    (destinationType !== 'league' || ctaLeagueId.trim().length > 0);

  return (
    <div className="panel space-y-4 p-5">
      {error && (
        <div className="rounded-sm border border-signal-danger/40 bg-signal-dangerFaint px-3 py-2 text-sm text-signal-danger">
          {error}
        </div>
      )}

      <div>
        <label className="mb-1.5 block text-sm text-ink-secondary">Type</label>
        <select
          value={type}
          onChange={(e) => setType(e.target.value as HomeContentType)}
          className="w-full rounded-sm border border-base-border bg-base-raised px-3 py-2 text-sm text-ink-primary outline-none focus:border-brand"
        >
          <option value="hero">Hero banner</option>
          <option value="promo_card">Promo card</option>
          <option value="announcement">Announcement</option>
        </select>
      </div>

      <div>
        <label className="mb-1.5 block text-sm text-ink-secondary">Title</label>
        <input
          value={title}
          onChange={(e) => setTitle(e.target.value)}
          maxLength={120}
          className="w-full rounded-sm border border-base-border bg-base-raised px-3 py-2 text-sm text-ink-primary outline-none focus:border-brand"
        />
      </div>

      <div>
        <label className="mb-1.5 block text-sm text-ink-secondary">
          {type === 'announcement' ? 'Message' : 'Subtitle / description'}
        </label>
        <textarea
          value={subtitle}
          onChange={(e) => setSubtitle(e.target.value)}
          maxLength={400}
          rows={3}
          className="w-full rounded-sm border border-base-border bg-base-raised px-3 py-2 text-sm text-ink-primary outline-none focus:border-brand"
        />
      </div>

      {type === 'announcement' && (
        <div>
          <label className="mb-1.5 block text-sm text-ink-secondary">Severity</label>
          <select
            value={severity}
            onChange={(e) => setSeverity(e.target.value as AnnouncementSeverity)}
            className="w-full rounded-sm border border-base-border bg-base-raised px-3 py-2 text-sm text-ink-primary outline-none focus:border-brand"
          >
            <option value="info">Info</option>
            <option value="warning">Warning</option>
            <option value="critical">Critical</option>
          </select>
        </div>
      )}

      {type !== 'announcement' && (
        <div>
          <label className="mb-1.5 block text-sm text-ink-secondary">Image</label>
          <div className="flex items-center gap-3">
            {imageUrl && (
              <div className="relative h-16 w-28 overflow-hidden rounded-sm border border-base-border">
                <Image src={imageUrl} alt="" fill className="object-cover" />
              </div>
            )}
            <label className="flex cursor-pointer items-center gap-2 rounded-sm border border-base-border bg-base-raised px-3 py-2 text-sm text-ink-secondary hover:text-ink-primary">
              {uploading ? <Loader2 size={15} className="animate-spin" /> : <UploadCloud size={15} />}
              {uploading ? 'Uploading…' : imageUrl ? 'Replace image' : 'Upload image'}
              <input type="file" accept="image/*" className="hidden" onChange={handleFileChange} disabled={uploading} />
            </label>
          </div>
          {uploadError && <p className="mt-1.5 text-xs text-signal-danger">{uploadError}</p>}
        </div>
      )}

      <div>
        <label className="mb-1.5 block text-sm text-ink-secondary">Destination (CTA)</label>
        <select
          value={destinationType}
          onChange={(e) => setDestinationType(e.target.value as CtaDestinationType)}
          className="w-full rounded-sm border border-base-border bg-base-raised px-3 py-2 text-sm text-ink-primary outline-none focus:border-brand"
        >
          <option value="none">None</option>
          <option value="league">A specific league</option>
          <option value="fixed_route">A platform page</option>
        </select>
      </div>

      {destinationType === 'league' && (
        <div>
          <label className="mb-1.5 block text-sm text-ink-secondary">League ID</label>
          <input
            value={ctaLeagueId}
            onChange={(e) => setCtaLeagueId(e.target.value)}
            placeholder="Find this on the league's detail page URL"
            className="w-full rounded-sm border border-base-border bg-base-raised px-3 py-2 text-sm text-ink-primary outline-none focus:border-brand"
          />
        </div>
      )}

      {destinationType === 'fixed_route' && (
        <div>
          <label className="mb-1.5 block text-sm text-ink-secondary">Page</label>
          <select
            value={ctaFixedRoute}
            onChange={(e) => setCtaFixedRoute(e.target.value)}
            className="w-full rounded-sm border border-base-border bg-base-raised px-3 py-2 text-sm text-ink-primary outline-none focus:border-brand"
          >
            {FIXED_ROUTES.map((r) => (
              <option key={r.value} value={r.value}>
                {r.label}
              </option>
            ))}
          </select>
        </div>
      )}

      {destinationType !== 'none' && (
        <div>
          <label className="mb-1.5 block text-sm text-ink-secondary">CTA label</label>
          <input
            value={ctaLabel}
            onChange={(e) => setCtaLabel(e.target.value)}
            placeholder="e.g. Register Now"
            maxLength={40}
            className="w-full rounded-sm border border-base-border bg-base-raised px-3 py-2 text-sm text-ink-primary outline-none focus:border-brand"
          />
        </div>
      )}

      <div className="grid grid-cols-2 gap-4">
        <div>
          <label className="mb-1.5 block text-sm text-ink-secondary">Display order</label>
          <input
            type="number"
            value={order}
            onChange={(e) => setOrder(parseInt(e.target.value, 10) || 0)}
            className="w-full rounded-sm border border-base-border bg-base-raised px-3 py-2 text-sm text-ink-primary outline-none focus:border-brand"
          />
        </div>
        <label className="flex cursor-pointer items-center gap-2.5 self-end rounded-sm bg-base-raised px-3 py-2.5">
          <input
            type="checkbox"
            checked={active}
            onChange={(e) => setActive(e.target.checked)}
            className="h-4 w-4 rounded-sm border-base-border bg-base text-brand focus:ring-brand"
          />
          <span className="text-sm text-ink-primary">Active</span>
        </label>
      </div>

      <div className="grid grid-cols-2 gap-4">
        <div>
          <label className="mb-1.5 block text-sm text-ink-secondary">Start date (optional)</label>
          <input
            type="date"
            value={startAt}
            onChange={(e) => setStartAt(e.target.value)}
            className="w-full rounded-sm border border-base-border bg-base-raised px-3 py-2 text-sm text-ink-primary outline-none focus:border-brand"
          />
        </div>
        <div>
          <label className="mb-1.5 block text-sm text-ink-secondary">End date (optional)</label>
          <input
            type="date"
            value={endAt}
            onChange={(e) => setEndAt(e.target.value)}
            className="w-full rounded-sm border border-base-border bg-base-raised px-3 py-2 text-sm text-ink-primary outline-none focus:border-brand"
          />
        </div>
      </div>

      <button
        onClick={handleSubmit}
        disabled={!canSubmit}
        className="rounded-sm bg-brand px-4 py-2 text-sm font-medium text-white hover:bg-brand-soft disabled:opacity-60"
      >
        {submitting ? 'Saving…' : existing ? 'Save changes' : 'Create'}
      </button>
    </div>
  );
}
