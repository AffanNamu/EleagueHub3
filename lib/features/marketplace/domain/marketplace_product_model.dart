import 'package:cloud_firestore/cloud_firestore.dart';

class MarketplaceProduct {
  const MarketplaceProduct({
    required this.productId,
    required this.name,
    required this.price,
    required this.description,
    required this.imageUrl,
    required this.affiliateUrl,
    required this.category,
    required this.sellerName,
    required this.createdAt,
    required this.createdBy,
  });

  final String productId;
  final String name;
  final String price;
  final String description;
  final String imageUrl;
  final String affiliateUrl;
  final String category;
  final String sellerName;
  final DateTime createdAt;
  final String createdBy;

  static MarketplaceProduct fromFirestore(
    DocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data() ?? const <String, dynamic>{};

    String readString(String key) {
      final v = data[key];
      if (v is String) return v.trim();
      return (v?.toString() ?? '').trim();
    }

    DateTime readCreatedAt() {
      final v = data['createdAt'];
      if (v is Timestamp) return v.toDate();
      if (v is DateTime) return v;
      if (v is int) {
        try {
          return DateTime.fromMillisecondsSinceEpoch(v);
        } catch (_) {
          return DateTime.fromMillisecondsSinceEpoch(0);
        }
      }
      if (v is num) {
        try {
          return DateTime.fromMillisecondsSinceEpoch(v.toInt());
        } catch (_) {
          return DateTime.fromMillisecondsSinceEpoch(0);
        }
      }
      return DateTime.fromMillisecondsSinceEpoch(0);
    }

    final productId = readString('productId').isNotEmpty
        ? readString('productId')
        : doc.id;

    return MarketplaceProduct(
      productId: productId,
      name: readString('name'),
      price: readString('price'),
      description: readString('description'),
      imageUrl: readString('imageUrl'),
      affiliateUrl: readString('affiliateUrl'),
      category: readString('category'),
      sellerName: readString('sellerName'),
      createdAt: readCreatedAt(),
      createdBy: readString('createdBy'),
    );
  }

  Map<String, dynamic> toFirestoreMap() {
    return <String, dynamic>{
      'productId': productId,
      'name': name,
      'price': price,
      'description': description,
      'imageUrl': imageUrl,
      'affiliateUrl': affiliateUrl,
      'category': category,
      'sellerName': sellerName,
      'createdAt': Timestamp.fromDate(createdAt),
      'createdBy': createdBy,
    };
  }

  MarketplaceProduct copyWith({
    String? productId,
    String? name,
    String? price,
    String? description,
    String? imageUrl,
    String? affiliateUrl,
    String? category,
    String? sellerName,
    DateTime? createdAt,
    String? createdBy,
  }) {
    return MarketplaceProduct(
      productId: productId ?? this.productId,
      name: name ?? this.name,
      price: price ?? this.price,
      description: description ?? this.description,
      imageUrl: imageUrl ?? this.imageUrl,
      affiliateUrl: affiliateUrl ?? this.affiliateUrl,
      category: category ?? this.category,
      sellerName: sellerName ?? this.sellerName,
      createdAt: createdAt ?? this.createdAt,
      createdBy: createdBy ?? this.createdBy,
    );
  }
}
