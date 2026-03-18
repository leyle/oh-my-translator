import '../../models/provider_config.dart';
import '../../models/prompt_templates.dart';
import 'anthropic_engine.dart';
import 'base_engine.dart';
import 'openai_compatible_engine.dart';

BaseEngine createEngine({
  required ProviderConfig config,
  PromptTemplates? promptTemplates,
}) {
  if (config.usesAnthropicMessagesApi) {
    return AnthropicEngine(config: config, promptTemplates: promptTemplates);
  }

  return OpenAICompatibleEngine(
    config: config,
    promptTemplates: promptTemplates,
  );
}
