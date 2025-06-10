import 'dart:convert'; // Import for jsonDecode and jsonEncode

class Recipe {
  final String id;
  final String title;
  final List<String> ingredients;
  final List<String> directions;
  final List<String> usedIngredients;
  final DateTime savedAt; // When the recipe was saved

  Recipe({
    required this.id,
    required this.title,
    required this.ingredients,
    required this.directions,
    required this.usedIngredients,
    required this.savedAt,
  });

  // Factory constructor to create a Recipe object from a JSON map
  factory Recipe.fromJson(Map<String, dynamic> json) {
    return Recipe(
      id: json['id'] as String,
      title: json['title'] as String? ?? 'Unknown Recipe',
      ingredients: (json['ingredients'] as List?)?.map((item) => item as String).toList() ?? [],
      directions: (json['directions'] as List?)?.map((item) => item as String).toList() ?? [],
      usedIngredients: (json['used_ingredients'] as List?)?.map((item) => item as String).toList() ?? [],
      savedAt: DateTime.parse(json['saved_at'] as String), // Parse date as string
    );
  }

  // Method to convert a Recipe object to a JSON-compatible map
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'ingredients': ingredients,
      'directions': directions,
      'used_ingredients': usedIngredients,
      'saved_at': savedAt.toIso8601String(), // Save date as ISO string
    };
  }

  // Create a copy of the recipe, optionally with new values
  Recipe copyWith({
    String? id,
    String? title,
    List<String>? ingredients,
    List<String>? directions,
    List<String>? usedIngredients,
    DateTime? savedAt,
  }) {
    return Recipe(
      id: id ?? this.id,
      title: title ?? this.title,
      ingredients: ingredients ?? this.ingredients,
      directions: directions ?? this.directions,
      usedIngredients: usedIngredients ?? this.usedIngredients,
      savedAt: savedAt ?? this.savedAt,
    );
  }
}
