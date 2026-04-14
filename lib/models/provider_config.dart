class ProviderConfig {
  final String id;
  final String displayName;
  final String defaultModel;
  final String defaultBaseUrl;
  final bool needsApiKey;
  final bool apiKeyOptional;
  final bool needsBaseUrl;
  final String modelHint;
  final String urlHint;
  final String keyHint;

  const ProviderConfig({
    required this.id,
    required this.displayName,
    required this.defaultModel,
    required this.defaultBaseUrl,
    required this.needsApiKey,
    this.apiKeyOptional = false,
    required this.needsBaseUrl,
    required this.modelHint,
    required this.urlHint,
    required this.keyHint,
  });
}

const kProviders = [
  ProviderConfig(
    id: 'ollama',
    displayName: 'Ollama',
    defaultModel: '',
    defaultBaseUrl: '',
    needsApiKey: false,
    apiKeyOptional: true,
    needsBaseUrl: true,
    modelHint: 'e.g. llama3.2:3b or qwen2.5:1.5b',
    urlHint: 'http://192.168.1.x:11434',
    keyHint: 'Optional — leave blank if not required',
  ),
  ProviderConfig(
    id: 'openai',
    displayName: 'OpenAI / Compatible',
    defaultModel: 'gpt-4o-mini',
    defaultBaseUrl: 'https://api.openai.com',
    needsApiKey: true,
    needsBaseUrl: true,
    modelHint: 'e.g. gpt-4o-mini, gpt-4o',
    urlHint: 'https://api.openai.com or https://ollama.com/v1',
    keyHint: 'sk-...',
  ),
  ProviderConfig(
    id: 'gemini',
    displayName: 'Google Gemini',
    defaultModel: 'gemini-2.0-flash',
    defaultBaseUrl: '',
    needsApiKey: true,
    needsBaseUrl: false,
    modelHint: 'e.g. gemini-2.0-flash or gemini-1.5-flash',
    urlHint: '',
    keyHint: 'AIza...',
  ),
  ProviderConfig(
    id: 'gemini_nano',
    displayName: 'Gemini Nano (on-device)',
    defaultModel: 'gemini-nano',
    defaultBaseUrl: '',
    needsApiKey: false,
    needsBaseUrl: false,
    modelHint: 'gemini-nano',
    urlHint: '',
    keyHint: '',
  ),
];

ProviderConfig? providerById(String id) {
  try {
    return kProviders.firstWhere((p) => p.id == id);
  } catch (_) {
    return null;
  }
}
