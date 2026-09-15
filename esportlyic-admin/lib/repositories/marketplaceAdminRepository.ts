// lib/repositories/marketplaceAdminRepository.ts
//
// Full CRUD for marketplace_products (see types/marketplaceProduct.ts for
// the schema background). Same shape as every other admin repository here:
// Admin SDK writes (bypasses firestore.rules' isPricingAdmin()-only create
// gate and its `allow update, delete: if false` — callers are already
// gated on marketplace.manage by the API route), immutable audit log entry
// per mutation.
//
// createdAt is stored as a Firestore Timestamp (not a raw number) to match
// exactly what MarketplaceProduct.fromFirestore expects in the mobile app —
// its epoch-millis fallback branch exists for legacy data, not as the
// intended write shape.

import 'server-only';

import { Timestamp } from 'firebase-admin/firestore';
import { adminDb } from '@/lib/firebase-admin';
import { recordAuditLog } from '@/lib/audit/auditLog';
import type { MarketplaceProduct, MarketplaceProductInput } from '@/types/marketplaceProduct';

const COLLECTION = 'marketplace_products';

export class MarketplaceProductError extends Error {}

function toMarketplaceProduct(id: string, data: FirebaseFirestore.DocumentData): MarketplaceProduct {
  const createdAt = data.createdAt;
  const createdAtMs =
    createdAt instanceof Timestamp
      ? createdAt.toMillis()
      : typeof createdAt === 'number'
        ? createdAt
        : 0;

  return {
    id,
    name: typeof data.name === 'string' ? data.name : '',
    price: typeof data.price === 'string' ? data.price : '',
    description: typeof data.description === 'string' ? data.description : '',
    imageUrl: typeof data.imageUrl === 'string' ? data.imageUrl : '',
    affiliateUrl: typeof data.affiliateUrl === 'string' ? data.affiliateUrl : '',
    category: typeof data.category === 'string' ? data.category : '',
    sellerName: typeof data.sellerName === 'string' ? data.sellerName : '',
    createdAtMs,
    createdBy: typeof data.createdBy === 'string' ? data.createdBy : '',
  };
}

function validate(input: MarketplaceProductInput): void {
  if (!input.name.trim()) throw new MarketplaceProductError('Name is required.');
  if (input.name.length > 120) throw new MarketplaceProductError('Name must be 120 characters or fewer.');
  if (!input.price.trim()) throw new MarketplaceProductError('Price is required.');
  if (!input.affiliateUrl.trim()) throw new MarketplaceProductError('Affiliate URL is required.');
  try {
    const url = new URL(input.affiliateUrl.trim());
    if (url.protocol !== 'http:' && url.protocol !== 'https:') throw new Error();
  } catch {
    throw new MarketplaceProductError('Affiliate URL must be a valid http(s) link.');
  }
  if (!input.category.trim()) throw new MarketplaceProductError('Category is required.');
  if (!input.sellerName.trim()) throw new MarketplaceProductError('Seller name is required.');
  if (input.description.length > 2000) {
    throw new MarketplaceProductError('Description must be 2000 characters or fewer.');
  }
}

export async function listMarketplaceProducts(): Promise<MarketplaceProduct[]> {
  const snap = await adminDb.collection(COLLECTION).orderBy('createdAt', 'desc').get();
  return snap.docs.map((doc) => toMarketplaceProduct(doc.id, doc.data()));
}

export async function getMarketplaceProduct(id: string): Promise<MarketplaceProduct | null> {
  const snap = await adminDb.collection(COLLECTION).doc(id).get();
  if (!snap.exists) return null;
  return toMarketplaceProduct(snap.id, snap.data() ?? {});
}

export async function createMarketplaceProduct(
  input: MarketplaceProductInput,
  actor: { uid: string; email?: string | null },
): Promise<MarketplaceProduct> {
  validate(input);

  const ref = adminDb.collection(COLLECTION).doc();
  const createdAt = Timestamp.now();

  const data = {
    productId: ref.id,
    name: input.name.trim(),
    price: input.price.trim(),
    description: input.description.trim(),
    imageUrl: input.imageUrl.trim(),
    affiliateUrl: input.affiliateUrl.trim(),
    category: input.category.trim(),
    sellerName: input.sellerName.trim(),
    createdAt,
    createdBy: actor.uid,
  };

  await ref.set(data);

  await recordAuditLog({
    actorUid: actor.uid,
    actorEmail: actor.email,
    action: 'marketplace_product.create',
    targetType: 'marketplace_product',
    targetId: ref.id,
    summary: `Created listing "${data.name}"`,
  });

  return toMarketplaceProduct(ref.id, data);
}

export async function updateMarketplaceProduct(
  id: string,
  input: MarketplaceProductInput,
  actor: { uid: string; email?: string | null },
): Promise<MarketplaceProduct> {
  validate(input);

  const ref = adminDb.collection(COLLECTION).doc(id);
  const existing = await ref.get();
  if (!existing.exists) throw new MarketplaceProductError('Listing not found.');

  const data = {
    name: input.name.trim(),
    price: input.price.trim(),
    description: input.description.trim(),
    imageUrl: input.imageUrl.trim(),
    affiliateUrl: input.affiliateUrl.trim(),
    category: input.category.trim(),
    sellerName: input.sellerName.trim(),
  };

  await ref.update(data);

  await recordAuditLog({
    actorUid: actor.uid,
    actorEmail: actor.email,
    action: 'marketplace_product.update',
    targetType: 'marketplace_product',
    targetId: id,
    summary: `Updated listing "${data.name}"`,
  });

  return toMarketplaceProduct(id, { ...existing.data(), ...data });
}

export async function deleteMarketplaceProduct(
  id: string,
  actor: { uid: string; email?: string | null },
): Promise<void> {
  const ref = adminDb.collection(COLLECTION).doc(id);
  const existing = await ref.get();
  if (!existing.exists) throw new MarketplaceProductError('Listing not found.');

  await ref.delete();

  await recordAuditLog({
    actorUid: actor.uid,
    actorEmail: actor.email,
    action: 'marketplace_product.delete',
    targetType: 'marketplace_product',
    targetId: id,
    summary: `Deleted listing "${existing.data()?.name ?? id}"`,
  });
}
