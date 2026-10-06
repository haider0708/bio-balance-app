import '../../core/api/json.dart';

class Product {
  const Product({
    required this.id,
    required this.reference,
    required this.name,
    required this.family,
    this.barcode,
    this.range = '',
    this.packageSize = '',
    this.description = '',
    this.instructions = '',
    this.ingredients = '',
    this.precautions = '',
    this.imageId,
    this.active = true,
  });

  factory Product.fromJson(Json j) => Product(
    id: j.str('id'),
    reference: j.str('reference'),
    name: j.str('name'),
    family: j.str('family'),
    barcode: j.strOrNull('barcode'),
    range: j.str('range'),
    packageSize: j.str('packageSize'),
    description: j.str('description'),
    instructions: j.str('instructions'),
    ingredients: j.str('ingredients'),
    precautions: j.str('precautions'),
    imageId: j.strOrNull('imageId'),
    active: j.flag('active', true),
  );

  final String id;
  final String reference;
  final String name;
  final String family;
  final String? barcode;
  final String range;
  final String packageSize;
  final String description;
  final String instructions;
  final String ingredients;
  final String precautions;
  final String? imageId;
  final bool active;

  Json toJson() => {
    'id': id,
    'reference': reference,
    'name': name,
    'family': family,
    'barcode': barcode,
    'range': range,
    'packageSize': packageSize,
    'description': description,
    'instructions': instructions,
    'ingredients': ingredients,
    'precautions': precautions,
    'imageId': imageId,
    'active': active,
  };
}
