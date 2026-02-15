import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/marketplace_product_model.dart';

class MarketplaceRepository {
  MarketplaceRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _col =>
      _firestore.collection('marketplace_products');

  Stream<List<MarketplaceProduct>> watchProducts({
    String? category,
    int limit = 100,
  }) {
    Query<Map<String, dynamic>> q = _col;

    final cat = (category ?? '').trim();
    if (cat.isNotEmpty && cat.toLowerCase() != 'all') {
      q = q.where('category', isEqualTo: cat);
    }

    q = q.orderBy('createdAt', descending: true).limit(limit);

    return q.snapshots().map((snap) {
      return snap.docs.map(MarketplaceProduct.fromFirestore).toList();
    });
  }

  Stream<MarketplaceProduct?> watchProductById(String productId) {
    final id = productId.trim();
    if (id.isEmpty) return const Stream<MarketplaceProduct?>.empty();

    return _col.doc(id).snapshots().map((doc) {
      if (!doc.exists) return null;
      return MarketplaceProduct.fromFirestore(doc);
    });
  }

  Future<MarketplaceProduct> createProduct({
    required String name,
    required String price,
    required String description,
    required String imageUrl,
    required String affiliateUrl,
    required String category,
    required String sellerName,
    required String createdBy,
  }) async {
    final now = DateTime.now();
    final doc = _col.doc();

    final product = MarketplaceProduct(
      productId: doc.id,
      name: name.trim(),
      price: price.trim(),
      description: description.trim(),
      imageUrl: imageUrl.trim(),
      affiliateUrl: affiliateUrl.trim(),
      category: category.trim(),
      sellerName: sellerName.trim(),
      createdAt: now,
      createdBy: createdBy.trim(),
    );

    // NOTE: Firestore rules require `createdAt` to be a `timestamp` in the request.
    // Using FieldValue.serverTimestamp() would not satisfy `is timestamp` checks.
    await doc.set(<String, dynamic>{
      'productId': product.productId,
      'name': product.name,
      'price': product.price,
      'description': product.description,
      'imageUrl': product.imageUrl,
      'affiliateUrl': product.affiliateUrl,
      'category': product.category,
      'sellerName': product.sellerName,
      'createdAt': Timestamp.fromDate(now),
      'createdBy': product.createdBy,
    });

    return product;
  }
}
