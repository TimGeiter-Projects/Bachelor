import 'dart:convert';

// Diese Definition muss mit den Definitionen in RecipePage, RecipeService und SavedRecipesPage übereinstimmen.
class IngredientEntry {
  final String name;
  final DateTime dateAdded;
  final String category;

  IngredientEntry({required this.name, required this.dateAdded, required this.category});

  // Convert an IngredientEntry to a JSON-serializable map
  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'dateAdded': dateAdded.toIso8601String(), // Convert DateTime to ISO 8601 string
      'category': category,
    };
  }

  // Create an IngredientEntry from a JSON map
  factory IngredientEntry.fromJson(Map<String, dynamic> json) {
    return IngredientEntry(
      name: json['name'] as String,
      dateAdded: DateTime.parse(json['dateAdded'] as String), // Parse ISO 8601 string back to DateTime
      category: json['category'] as String? ?? 'Unknown', // Read category from JSON, with fallback
    );
  }

  @override
  String toString() {
    return 'IngredientEntry(name: $name, dateAdded: ${dateAdded.toIso8601String()}, category: $category)';
  }
}