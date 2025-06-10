import 'dart:convert';
import 'package:http/http.dart' as http;

class ApiService {
  // Space ist https://huggingface.co/spaces/TimInf/DockerRecipe
  // API-URL ist https://timinf-dockerrecipe.hf.space/generate_recipe
  final String recipeApiUrl = "https://timinf-dockerrecipe.hf.space/generate_recipe";

  Future<Map<String, dynamic>> generateRecipe(
      List<String> requiredIngredients,
      List<String> availableIngredients) async {

    final headers = {'Content-Type': 'application/json'};

    final payload = {
      'required_ingredients': requiredIngredients,
      'available_ingredients': availableIngredients,
      'max_ingredients': 7,
      'max_retries': 5,
    };

    final requestBody = jsonEncode(payload);

    try {
      final response = await http.post(Uri.parse(recipeApiUrl), headers: headers, body: requestBody);

      if (response.statusCode == 200) {
        return jsonDecode(response.body);
      } else {
        print('API Error (Recipe Space) - Status Code: ${response.statusCode}');
        print('API Error (Recipe Space) - Response Body: ${response.body}');
        throw Exception(
            'Fehler beim Laden des Rezepts vom Space: ${response.statusCode} ${response.body}');
      }
    } catch (e) {
      print('Netzwerk/Anfrage-Fehler (Recipe Space): $e');
      throw Exception('Fehler beim Senden der Rezeptanfrage: $e');
    }
  }
}
