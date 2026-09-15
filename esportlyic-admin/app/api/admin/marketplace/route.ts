import { NextResponse } from 'next/server';
import { getCurrentAdminIdentity } from '@/lib/auth/adminAuthService';
import { hasPermission } from '@/lib/auth/requirePermission';
import {
  createMarketplaceProduct,
  listMarketplaceProducts,
  MarketplaceProductError,
} from '@/lib/repositories/marketplaceAdminRepository';
import type { MarketplaceProductInput } from '@/types/marketplaceProduct';

function parseInput(body: unknown): MarketplaceProductInput {
  const b = (body ?? {}) as Record<string, unknown>;
  return {
    name: typeof b.name === 'string' ? b.name : '',
    price: typeof b.price === 'string' ? b.price : '',
    description: typeof b.description === 'string' ? b.description : '',
    imageUrl: typeof b.imageUrl === 'string' ? b.imageUrl : '',
    affiliateUrl: typeof b.affiliateUrl === 'string' ? b.affiliateUrl : '',
    category: typeof b.category === 'string' ? b.category : '',
    sellerName: typeof b.sellerName === 'string' ? b.sellerName : '',
  };
}

export async function GET() {
  const identity = await getCurrentAdminIdentity();
  if (!hasPermission(identity, 'marketplace.view')) {
    return NextResponse.json({ error: 'Not authorized.' }, { status: 403 });
  }

  const items = await listMarketplaceProducts();
  return NextResponse.json({ items });
}

export async function POST(request: Request) {
  const identity = await getCurrentAdminIdentity();
  if (!hasPermission(identity, 'marketplace.manage')) {
    return NextResponse.json({ error: 'Not authorized.' }, { status: 403 });
  }

  try {
    const body = await request.json();
    const item = await createMarketplaceProduct(parseInput(body), { uid: identity!.uid, email: identity!.email });
    return NextResponse.json({ item });
  } catch (err) {
    if (err instanceof MarketplaceProductError) {
      return NextResponse.json({ error: err.message }, { status: 400 });
    }
    console.error('[create marketplace product]', err);
    return NextResponse.json({ error: 'Something went wrong. Please try again.' }, { status: 500 });
  }
}
