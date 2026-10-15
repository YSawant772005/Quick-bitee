import 'package:flutter/material.dart';

/// Presentation metadata for cuisines: a single, consistent Material icon set
/// (no emoji, no mixed icon families).
class CuisineMeta {
  const CuisineMeta(this.name, this.icon);
  final String name;
  final IconData icon;
}

const kCuisines = <CuisineMeta>[
  CuisineMeta('Biryani', Icons.rice_bowl_outlined),
  CuisineMeta('Pizza', Icons.local_pizza_outlined),
  CuisineMeta('Burgers', Icons.lunch_dining_outlined),
  CuisineMeta('South Indian', Icons.breakfast_dining_outlined),
  CuisineMeta('North Indian', Icons.dinner_dining_outlined),
  CuisineMeta('Asian', Icons.ramen_dining_outlined),
  CuisineMeta('Desserts', Icons.cake_outlined),
  CuisineMeta('Beverages', Icons.local_cafe_outlined),
];

IconData cuisineIcon(String cuisine) {
  final c = cuisine.toLowerCase();
  if (c.contains('biryani') || c.contains('hyderabadi')) return Icons.rice_bowl_outlined;
  if (c.contains('pizza') || c.contains('italian')) return Icons.local_pizza_outlined;
  if (c.contains('burger') || c.contains('american')) return Icons.lunch_dining_outlined;
  if (c.contains('south')) return Icons.breakfast_dining_outlined;
  if (c.contains('north') || c.contains('punjabi')) return Icons.dinner_dining_outlined;
  if (c.contains('asian') || c.contains('chinese') || c.contains('thai')) return Icons.ramen_dining_outlined;
  if (c.contains('dessert') || c.contains('sweet')) return Icons.cake_outlined;
  if (c.contains('beverage') || c.contains('cafe') || c.contains('chai')) return Icons.local_cafe_outlined;
  return Icons.restaurant_menu;
}

/// A section of dishes to order, shown on home/explore.
class CategoryChipData {
  const CategoryChipData(this.label, this.icon);
  final String label;
  final IconData icon;
}
