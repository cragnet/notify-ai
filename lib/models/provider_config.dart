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
    displayName: 'Gemini Nano (on-device via ML Kit)',
    defaultModel: 'gemini-nano',
    defaultBaseUrl: '',
    needsApiKey: false,
    needsBaseUrl: false,
    modelHint: 'gemini-nano',
    urlHint: '',
    keyHint: '',
    // Note: uses ML Kit GenAI Prompt API. Requires Google Play Services and a supported device.
    // First use may trigger an on-device model download (~1-2 GB).
  ),
  ProviderConfig(
    id: 'claude',
    displayName: 'Claude (Anthropic)',
    defaultModel: 'claude-3-5-haiku-latest',
    defaultBaseUrl: 'https://api.anthropic.com',
    needsApiKey: true,
    needsBaseUrl: true,
    modelHint: 'e.g. claude-3-5-haiku-latest, claude-3-5-sonnet-latest',
    urlHint: 'https://api.anthropic.com',
    keyHint: 'sk-ant-api03-...',
  ),
  ProviderConfig(
    id: 'openrouter',
    displayName: 'OpenRouter',
    defaultModel: 'openai/gpt-4o-mini',
    defaultBaseUrl: 'https://openrouter.ai',
    needsApiKey: true,
    needsBaseUrl: true,
    modelHint: 'e.g. openai/gpt-4o-mini, meta-llama/llama-3.1-8b-instruct',
    urlHint: 'https://openrouter.ai',
    keyHint: 'sk-or-v1-...',
  ),
  ProviderConfig(
    id: 'local',
    displayName: 'Local / Custom',
    defaultModel: '',
    defaultBaseUrl: '',
    needsApiKey: false,
    apiKeyOptional: true,
    needsBaseUrl: true,
    modelHint: 'e.g. llama3.2:3b',
    urlHint: 'http://192.168.1.x:1234/v1',
    keyHint: 'Optional — leave blank if not required',
  ),
];

ProviderConfig? providerById(String id) {
  try {
    return kProviders.firstWhere((p) => p.id == id);
  } catch (_) {
    return null;
  }
}
