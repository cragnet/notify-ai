class ProviderConfig {
  final String id;
  final String displayName;
  final String defaultModel;
  final String defaultBaseUrl;
  final bool needsApiKey;
  final bool needsBaseUrl;
  final List<ModelOption> models;

  const ProviderConfig({
    required this.id,
    required this.displayName,
    required this.defaultModel,
    required this.defaultBaseUrl,
    required this.needsApiKey,
    required this.needsBaseUrl,
    required this.models,
  });
}

class ModelOption {
  final String id;
  final String name;
  final bool isCustom;
  const ModelOption(this.id, this.name, {this.isCustom = false});
}

const kProviders = [
  ProviderConfig(
    id: 'claude',
    displayName: 'Claude (Anthropic)',
    defaultModel: 'claude-haiku-4-5-20251001',
    defaultBaseUrl: 'https://api.anthropic.com',
    needsApiKey: true,
    needsBaseUrl: true,
    models: [
      ModelOption('claude-haiku-4-5-20251001', 'Claude Haiku — fastest, cheapest'),
      ModelOption('claude-sonnet-4-6', 'Claude Sonnet — recommended'),
      ModelOption('claude-opus-4-6', 'Claude Opus — most capable'),
    ],
  ),
  ProviderConfig(
    id: 'openai',
    displayName: 'OpenAI',
    defaultModel: 'gpt-4o-mini',
    defaultBaseUrl: 'https://api.openai.com',
    needsApiKey: true,
    needsBaseUrl: true,
    models: [
      ModelOption('gpt-4o-mini', 'GPT-4o Mini — fastest, cheapest'),
      ModelOption('gpt-4o', 'GPT-4o — recommended'),
      ModelOption('gpt-4-turbo', 'GPT-4 Turbo'),
    ],
  ),
  ProviderConfig(
    id: 'ollama',
    displayName: 'Ollama (local / Pi)',
    defaultModel: 'llama3.2:3b',
    defaultBaseUrl: 'http://10.0.1.33:11434',
    needsApiKey: false,
    needsBaseUrl: true,
    models: [
      ModelOption('llama3.2:3b', 'Llama 3.2 3B — recommended'),
      ModelOption('llama3.2:1b', 'Llama 3.2 1B — fastest'),
      ModelOption('qwen2.5:1.5b', 'Qwen 2.5 1.5B'),
      ModelOption('qwen2.5:3b', 'Qwen 2.5 3B'),
      ModelOption('mistral:7b', 'Mistral 7B'),
      ModelOption('custom', 'Custom model name…', isCustom: true),
    ],
  ),
  ProviderConfig(
    id: 'openrouter',
    displayName: 'OpenRouter',
    defaultModel: 'anthropic/claude-haiku-4-5',
    defaultBaseUrl: 'https://openrouter.ai',
    needsApiKey: true,
    needsBaseUrl: false,
    models: [
      ModelOption('anthropic/claude-haiku-4-5', 'Claude Haiku (fast)'),
      ModelOption('anthropic/claude-sonnet-4-6', 'Claude Sonnet'),
      ModelOption('openai/gpt-4o-mini', 'GPT-4o Mini'),
      ModelOption('openai/gpt-4o', 'GPT-4o'),
      ModelOption('meta-llama/llama-3.2-3b-instruct:free', 'Llama 3.2 3B (free)'),
      ModelOption('google/gemini-flash-1.5', 'Gemini Flash 1.5'),
    ],
  ),
  ProviderConfig(
    id: 'gemini',
    displayName: 'Google Gemini',
    defaultModel: 'gemini-2.0-flash',
    defaultBaseUrl: '',
    needsApiKey: true,
    needsBaseUrl: false,
    models: [
      ModelOption('gemini-2.0-flash', 'Gemini 2.0 Flash — recommended'),
      ModelOption('gemini-1.5-flash', 'Gemini 1.5 Flash'),
      ModelOption('gemini-1.5-pro', 'Gemini 1.5 Pro'),
    ],
  ),
  ProviderConfig(
    id: 'gemini_nano',
    displayName: 'Gemini Nano (on-device)',
    defaultModel: 'gemini-nano',
    defaultBaseUrl: '',
    needsApiKey: false,
    needsBaseUrl: false,
    models: [
      ModelOption('gemini-nano', 'Gemini Nano — fully local, no key needed'),
    ],
  ),
];

ProviderConfig? providerById(String id) {
  try {
    return kProviders.firstWhere((p) => p.id == id);
  } catch (_) {
    return null;
  }
}
