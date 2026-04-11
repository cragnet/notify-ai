class ProviderConfig {
  final String id;
  final String displayName;
  final String defaultModel;
  final String defaultBaseUrl;
  final bool needsApiKey;
  final bool apiKeyOptional; // key is optional (e.g. local servers)
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
    id: 'claude',
    displayName: 'Claude (Anthropic)',
    defaultModel: 'claude-haiku-4-5-20251001',
    defaultBaseUrl: 'https://api.anthropic.com',
    needsApiKey: true,
    needsBaseUrl: true,
    modelHint: 'e.g. claude-haiku-4-5-20251001',
    urlHint: 'https://api.anthropic.com',
    keyHint: 'sk-ant-...',
  ),
  ProviderConfig(
    id: 'openai',
    displayName: 'OpenAI',
    defaultModel: 'gpt-4o-mini',
    defaultBaseUrl: 'https://api.openai.com',
    needsApiKey: true,
    needsBaseUrl: true,
    modelHint: 'e.g. gpt-4o-mini',
    urlHint: 'https://api.openai.com',
    keyHint: 'sk-...',
  ),
  ProviderConfig(
    id: 'openrouter',
    displayName: 'OpenRouter',
    defaultModel: 'anthropic/claude-haiku-4-5',
    defaultBaseUrl: 'https://openrouter.ai',
    needsApiKey: true,
    needsBaseUrl: false,
    modelHint: 'e.g. anthropic/claude-haiku-4-5',
    urlHint: 'https://openrouter.ai',
    keyHint: 'sk-or-...',
  ),
  ProviderConfig(
    id: 'gemini',
    displayName: 'Google Gemini',
    defaultModel: 'gemini-2.0-flash',
    defaultBaseUrl: '',
    needsApiKey: true,
    needsBaseUrl: false,
    modelHint: 'e.g. gemini-2.0-flash',
    urlHint: '',
    keyHint: 'AIza...',
  ),
  ProviderConfig(
    id: 'ollama',
    displayName: 'Ollama',
    defaultModel: 'llama3.2:3b',
    defaultBaseUrl: 'https://your-ollama-cloud-url.com',
    needsApiKey: false,
    apiKeyOptional: true,
    needsBaseUrl: true,
    modelHint: 'e.g. llama3.2:3b',
    urlHint: 'https://your-ollama-cloud-url.com',
    keyHint: 'Optional — leave blank if not required',
  ),
  ProviderConfig(
    id: 'local',
    displayName: 'Local / Custom',
    defaultModel: '',
    defaultBaseUrl: 'http://192.168.1.x:11434',
    needsApiKey: false,
    apiKeyOptional: true,
    needsBaseUrl: true,
    modelHint: 'Enter model name exactly as it appears',
    urlHint: 'http://192.168.1.x:port',
    keyHint: 'Optional — leave blank if not required',
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
