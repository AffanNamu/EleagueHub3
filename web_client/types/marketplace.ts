// Mirrors lib/features/marketplace/domain/marketplace_product_model.dart and
// the `marketplace_products` Firestore collection exactly — an
// admin-curated affiliate product catalog (NOT a peer-to-peer listings
// marketplace). firestore.rules' `marketplace_products/{productId}` create
// rule requires exactly these fields, with `price` as a free-text string
// (e.g. "$49.99", not a number) and a single `imageUrl` (not an array).
export interface MarketplaceProduct {
  productId: string;
  name: string;
  price: string;
  description: string;
  imageUrl: string;
  affiliateUrl: string;
  category: string;
  sellerName: string;
  createdAt: number;
  createdBy: string;
}
