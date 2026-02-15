import 'package:flutter/material.dart';

import 'product_details_screen.dart';

class ListingDetailScreen extends StatelessWidget {
  const ListingDetailScreen({super.key, required this.listingId});

  final String listingId;

  @override
  Widget build(BuildContext context) {
    return ProductDetailsScreen(productId: listingId);
  }
}
