from flask import Flask, request, jsonify
from transformers import FlaxAutoModelForSeq2SeqLM, AutoTokenizer
from transformers import AutoModel
import torch
import numpy as np
import random
from flask_cors import CORS

app = Flask(__name__)
CORS(app)

# Load RecipeBERT model (for semantic ingredient combination)
bert_model_name = "alexdseo/RecipeBERT"
bert_tokenizer = AutoTokenizer.from_pretrained(bert_model_name)
bert_model = AutoModel.from_pretrained(bert_model_name)
bert_model.eval()

# Load T5 recipe generation model
MODEL_NAME_OR_PATH = "flax-community/t5-recipe-generation"
t5_tokenizer = AutoTokenizer.from_pretrained(MODEL_NAME_OR_PATH, use_fast=True)
t5_model = FlaxAutoModelForSeq2SeqLM.from_pretrained(MODEL_NAME_OR_PATH)

# Token mapping for T5 model output processing
special_tokens = t5_tokenizer.all_special_tokens
tokens_map = {
    "<sep>": "--",
    "<section>": "\n"
}

def get_embedding(text):
    """Computes embedding for a text with Mean Pooling over all tokens"""
    inputs = bert_tokenizer(text, return_tensors="pt", truncation=True, padding=True)
    with torch.no_grad():
        outputs = bert_model(**inputs)

    # Mean Pooling - take average of all token embeddings
    attention_mask = inputs['attention_mask']
    token_embeddings = outputs.last_hidden_state
    input_mask_expanded = attention_mask.unsqueeze(-1).expand(token_embeddings.size()).float()
    sum_embeddings = torch.sum(token_embeddings * input_mask_expanded, 1)
    sum_mask = torch.clamp(input_mask_expanded.sum(1), min=1e-9)

    return (sum_embeddings / sum_mask).squeeze(0)

def average_embedding(embedding_list):
    """Computes the average of a list of embeddings"""
    tensors = torch.stack([emb for _, emb in embedding_list])
    return tensors.mean(dim=0)

def get_cosine_similarity(vec1, vec2):
    """Computes the cosine similarity between two vectors"""
    if torch.is_tensor(vec1):
        vec1 = vec1.detach().numpy()
    if torch.is_tensor(vec2):
        vec2 = vec2.detach().numpy()

    # Make sure vectors have the right shape (flatten if necessary)
    vec1 = vec1.flatten()
    vec2 = vec2.flatten()

    dot_product = np.dot(vec1, vec2)
    norm_a = np.linalg.norm(vec1)
    norm_b = np.linalg.norm(vec2)

    # Avoid division by zero
    if norm_a == 0 or norm_b == 0:
        return 0

    return dot_product / (norm_a * norm_b)

def get_combined_scores(query_vector, embedding_list, all_good_embeddings, avg_weight=0.6):
    """Computes combined score considering both similarity to average and individual ingredients"""
    results = []

    for name, emb in embedding_list:
        # Similarity to average vector
        avg_similarity = get_cosine_similarity(query_vector, emb)

        # Average similarity to individual ingredients
        individual_similarities = [get_cosine_similarity(good_emb, emb)
                                  for _, good_emb in all_good_embeddings]
        avg_individual_similarity = sum(individual_similarities) / len(individual_similarities)

        # Combined score (weighted average)
        combined_score = avg_weight * avg_similarity + (1 - avg_weight) * avg_individual_similarity

        results.append((name, emb, combined_score))

    # Sort by combined score (descending)
    results.sort(key=lambda x: x[2], reverse=True)
    return results

def find_best_ingredients(required_ingredients, available_ingredients, max_ingredients=6, avg_weight=0.6):
    """
    Finds the best ingredients based on RecipeBERT embeddings.
    
    Args:
        required_ingredients (list): Required ingredients that must be used
        available_ingredients (list): Available ingredients to choose from
        max_ingredients (int): Maximum number of ingredients for the recipe
        avg_weight (float): Weight for average vector
        
    Returns:
        list: The optimal combination of ingredients
    """
    # Ensure no duplicates in lists
    required_ingredients = list(set(required_ingredients))
    available_ingredients = list(set([i for i in available_ingredients if i not in required_ingredients]))
    
    # Special case: If no required ingredients, randomly select one from available ingredients
    if not required_ingredients and available_ingredients:
        # Randomly select 1 ingredient as starting point
        random_ingredient = random.choice(available_ingredients)
        required_ingredients = [random_ingredient]
        available_ingredients = [i for i in available_ingredients if i != random_ingredient]
        print(f"No required ingredients provided. Randomly selected: {random_ingredient}")
    
    # If still no ingredients or already at max capacity
    if not required_ingredients or len(required_ingredients) >= max_ingredients:
        return required_ingredients[:max_ingredients]
    
    # If no additional ingredients available
    if not available_ingredients:
        return required_ingredients
    
    # Calculate embeddings for all ingredients
    embed_required = [(e, get_embedding(e)) for e in required_ingredients]
    embed_available = [(e, get_embedding(e)) for e in available_ingredients]
    
    # Number of ingredients to add
    num_to_add = min(max_ingredients - len(required_ingredients), len(available_ingredients))
    
    # Copy required ingredients to final list
    final_ingredients = embed_required.copy()
    
    # Add best ingredients
    for _ in range(num_to_add):
        # Calculate average vector of current combination
        avg = average_embedding(final_ingredients)
        
        # Calculate combined scores for all candidates
        candidates = get_combined_scores(avg, embed_available, final_ingredients, avg_weight)
        
        # If no candidates left, break
        if not candidates:
            break
            
        # Choose best ingredient
        best_name, best_embedding, _ = candidates[0]
        
        # Add best ingredient to final list
        final_ingredients.append((best_name, best_embedding))
        
        # Remove ingredient from available ingredients
        embed_available = [item for item in embed_available if item[0] != best_name]
    
    # Extract only ingredient names
    return [name for name, _ in final_ingredients]

def skip_special_tokens(text, special_tokens):
    """Removes special tokens from text"""
    for token in special_tokens:
        text = text.replace(token, "")
    return text

def target_postprocessing(texts, special_tokens):
    """Post-processes generated text"""
    if not isinstance(texts, list):
        texts = [texts]

    new_texts = []
    for text in texts:
        text = skip_special_tokens(text, special_tokens)

        for k, v in tokens_map.items():
            text = text.replace(k, v)

        new_texts.append(text)

    return new_texts

def validate_recipe_ingredients(recipe_ingredients, expected_ingredients, tolerance=0):
    """
    Validates if the recipe contains approximately the expected ingredients.
    
    Args:
        recipe_ingredients (list): Ingredients from generated recipe
        expected_ingredients (list): Expected ingredients
        tolerance (int): Allowed difference in ingredient count
        
    Returns:
        bool: True if recipe is valid, False otherwise
    """
    # Count non-empty ingredients
    recipe_count = len([ing for ing in recipe_ingredients if ing and ing.strip()])
    expected_count = len(expected_ingredients)
    
    # Check if ingredient count is within tolerance
    return abs(recipe_count - expected_count) == tolerance

def generate_recipe_with_t5(ingredients_list, max_retries=5):
    """
    Generates a recipe using the T5 recipe generation model with validation.
    
    Args:
        ingredients_list (list): List of ingredients
        max_retries (int): Maximum number of retry attempts
        
    Returns:
        dict: A dictionary with title, ingredients, and directions
    """
    original_ingredients = ingredients_list.copy()
    
    for attempt in range(max_retries):
        try:
            # For retries after the first attempt, shuffle the ingredients
            if attempt > 0:
                current_ingredients = original_ingredients.copy()
                random.shuffle(current_ingredients)
                print(f"Retry {attempt}: Shuffling ingredients order")
            else:
                current_ingredients = ingredients_list
            
            # Format ingredients as a comma-separated string
            ingredients_string = ", ".join(current_ingredients)
            prefix = "items: "
            
            # Generation settings
            generation_kwargs = {
                "max_length": 512,
                "min_length": 64,
                "do_sample": True,
                "top_k": 60,
                "top_p": 0.95
            }
            print(f"Attempt {attempt + 1}: {prefix + ingredients_string}")
            
            # Tokenize input
            inputs = t5_tokenizer(
                prefix + ingredients_string,
                max_length=256,
                padding="max_length",
                truncation=True,
                return_tensors="jax"
            )
            
            # Generate text
            output_ids = t5_model.generate(
                input_ids=inputs.input_ids,
                attention_mask=inputs.attention_mask,
                **generation_kwargs
            )
            
            # Decode and post-process
            generated = output_ids.sequences
            generated_text = target_postprocessing(
                t5_tokenizer.batch_decode(generated, skip_special_tokens=False),
                special_tokens
            )[0]
            
            # Parse sections
            recipe = {}
            sections = generated_text.split("\n")
            for section in sections:
                section = section.strip()
                if section.startswith("title:"):
                    recipe["title"] = section.replace("title:", "").strip().capitalize()
                elif section.startswith("ingredients:"):
                    ingredients_text = section.replace("ingredients:", "").strip()
                    recipe["ingredients"] = [item.strip().capitalize() for item in ingredients_text.split("--") if item.strip()]
                elif section.startswith("directions:"):
                    directions_text = section.replace("directions:", "").strip()
                    recipe["directions"] = [step.strip().capitalize() for step in directions_text.split("--") if step.strip()]
            
            # If title is missing, create one
            if "title" not in recipe:
                recipe["title"] = f"Recipe with {', '.join(current_ingredients[:3])}"
                
            # Ensure all sections exist
            if "ingredients" not in recipe:
                recipe["ingredients"] = current_ingredients
            if "directions" not in recipe:
                recipe["directions"] = ["No directions generated"]
            
            # Validate the recipe
            if validate_recipe_ingredients(recipe["ingredients"], original_ingredients):
                print(f"Success on attempt {attempt + 1}: Recipe has correct number of ingredients")
                return recipe
            else:
                print(f"Attempt {attempt + 1} failed: Expected {len(original_ingredients)} ingredients, got {len(recipe['ingredients'])}")
                if attempt == max_retries - 1:
                    print("Max retries reached, returning last generated recipe")
                    return recipe
                    
        except Exception as e:
            print(f"Error in recipe generation attempt {attempt + 1}: {str(e)}")
            if attempt == max_retries - 1:
                return {
                    "title": f"Recipe with {original_ingredients[0] if original_ingredients else 'ingredients'}",
                    "ingredients": original_ingredients,
                    "directions": ["Error generating recipe instructions"]
                }
    
    # Fallback (should not be reached)
    return {
        "title": f"Recipe with {original_ingredients[0] if original_ingredients else 'ingredients'}",
        "ingredients": original_ingredients,
        "directions": ["Error generating recipe instructions"]
    }

@app.route('/generate_recipe', methods=['POST'])
def handle_recipe_request():
    """
    Processes a recipe generation request with a given list of ingredients.
    Uses the intelligent ingredient combination feature.
    """
    if not request.is_json:
        return jsonify({"error": "Request must be JSON"}), 415

    data = request.get_json()

    # Extract required and available ingredients from request
    required_ingredients = data.get('required_ingredients', [])
    available_ingredients = data.get('available_ingredients', [])
    
    # For backward compatibility: If only 'ingredients' is specified, treat as required ingredients
    if data.get('ingredients') and not required_ingredients:
        required_ingredients = data.get('ingredients', [])
    
    # Maximum number of ingredients (for better recipes)
    max_ingredients = data.get('max_ingredients', 7)
    
    # Maximum retries for recipe generation
    max_retries = data.get('max_retries', 5)
    
    # If no ingredients specified
    if not required_ingredients and not available_ingredients:
        return jsonify({"error": "No ingredients provided"}), 400
    
    try:
        # Always find best ingredient combination with RecipeBERT
        optimized_ingredients = find_best_ingredients(
            required_ingredients, 
            available_ingredients, 
            max_ingredients
        )
        
        # Generate recipe with optimized ingredients using T5 model with validation
        recipe = generate_recipe_with_t5(optimized_ingredients, max_retries)
        
        # Format for Flutter app consumption - structured format
        return jsonify({
            'title': recipe['title'],
            'ingredients': recipe['ingredients'],
            'directions': recipe['directions'],
            'used_ingredients': optimized_ingredients
        })
        
    except Exception as e:
        return jsonify({"error": f"Error in recipe generation: {str(e)}"}), 500

@app.route('/generate_recipe_smart', methods=['POST'])
def handle_smart_recipe_request():
    """
    Processes an intelligent recipe generation request.
    This endpoint remains for backward compatibility.
    """
    # Delegate to handle_recipe_request
    return handle_recipe_request()

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8000, debug=True)