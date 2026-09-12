// Mirrors lib/features/marketplace/data/marketplace_repository.dart.

import { collection, doc, setDoc, Timestamp } from 'firebase/firestore';
import { db } from '@/lib/firebase';
import { MarketplaceProduct } from '@/types/marketplace';

const PRODUCTS_COLLECTION = 'marketplace_products';

export function marketplaceProductFromDoc(id: string, data: Record<string, unknown>): MarketplaceProduct {
  const productId = typeof data.productId === 'string' && data.productId.trim() ? data.productId.trim() : id;
  const createdAtRaw = data.createdAt;
  const createdAt = createdAtRaw instanceof Timestamp ? createdAtRaw.toMillis() : Number(createdAtRaw) || 0;

  return {
    productId,
    name: typeof data.name === 'string' ? data.name.trim() : '',
    price: typeof data.price === 'string' ? data.price.trim() : '',
    description: typeof data.description === 'string' ? data.description.trim() : '',
    imageUrl: typeof data.imageUrl === 'string' ? data.imageUrl.trim() : '',
    affiliateUrl: typeof data.affiliateUrl === 'string' ? data.affiliateUrl.trim() : '',
    category: typeof data.category === 'string' ? data.category.trim() : '',
    sellerName: typeof data.sellerName === 'string' ? data.sellerName.trim() : '',
    createdAt,
    createdBy: typeof data.createdBy === 'string' ? data.createdBy.trim() : '',
  };
}

/** Admin-only (enforced by firestore.rules — createdBy must equal the
 * super-admin uid). Mirrors MarketplaceRepository.createProduct(). */
export async function createMarketplaceProductWeb(params: {
  name: string;
  price: string;
  description: string;
  imageUrl: string;
  affiliateUrl: string;
  category: string;
  sellerName: string;
  createdBy: string;
}): Promise<MarketplaceProduct> {
  const ref = doc(collection(db, PRODUCTS_COLLECTION));
  const now = new Date();

  const product: MarketplaceProduct = {
    productId: ref.id,
    name: params.name.trim(),
    price: params.price.trim(),
    description: params.description.trim(),
    imageUrl: params.imageUrl.trim(),
    affiliateUrl: params.affiliateUrl.trim(),
    category: params.category.trim(),
    sellerName: params.sellerName.trim(),
    createdAt: now.getTime(),
    createdBy: params.createdBy.trim(),
  };

  await setDoc(ref, {
    productId: product.productId,
    name: product.name,
    price: product.price,
    description: product.description,
    imageUrl: product.imageUrl,
    affiliateUrl: product.affiliateUrl,
    category: product.category,
    sellerName: product.sellerName,
    createdAt: Timestamp.fromDate(now),
    createdBy: product.createdBy,
  });

  return product;
}

export { PRODUCTS_COLLECTION };
