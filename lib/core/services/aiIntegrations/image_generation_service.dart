import '../ai_client.dart';

const String _imageGenerationEndpoint = String.fromEnvironment(
  'AWS_LAMBDA_IMAGE_GENERATION_URL',
);

Future<Map<String, dynamic>> generateImage(
  String provider,
  String model,
  String prompt, {
  Map<String, dynamic> parameters = const {},
}) async {
  final payload = {
    'provider': provider,
    'model': model,
    'prompt': prompt,
    'parameters': parameters,
  };
  return await callLambdaFunction(_imageGenerationEndpoint, payload);
}
