export interface MarketplaceProduct {
  id: string;
  sellerId: string;
  sellerName: string;
  title: string;
  description: string;
  price: number;
  currency: string;
  imageUrls: string[];
  category: string;
  condition: 'new' | 'used' | 'refurbished';
  isAvailable: boolean;
  createdAt: any; // Firestore Timestamp
  updatedAt: any;
}
