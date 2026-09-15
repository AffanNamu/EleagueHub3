// types/marketplaceProduct.ts
//
// marketplace_products collection. Confirmed against
// lib/features/marketplace/domain/marketplace_product_model.dart — a flat,
// admin-authored affiliate product catalog (affiliateUrl points off-platform;
// this is not peer-to-peer user listings). firestore.rules gates create on
// isPricingAdmin() and blocks update/delete outright (`allow update, delete:
// if false`) — until this admin panel, there was no way for anyone to edit
// or remove a listing once created, and no UI anywhere to create one either.

export interface MarketplaceProduct {
  id: string;
  name: string;
  price: string;
  description: string;
  imageUrl: string;
  affiliateUrl: string;
  category: string;
  sellerName: string;
  createdAtMs: number;
  createdBy: string;
}

export interface MarketplaceProductInput {
  name: string;
  price: string;
  description: string;
  imageUrl: string;
  affiliateUrl: string;
  category: string;
  sellerName: string;
}
