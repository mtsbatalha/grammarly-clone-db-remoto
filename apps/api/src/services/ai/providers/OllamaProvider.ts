import { AIProvider, CompletionOptions } from '../types.js';
import { env } from '../../../config/env.js';
import { logger } from '../../../config/logger.js';

/**
 * Ollama Provider - Recommended for local AI inference
 *
 * Ollama is the recommended AI provider because:
 * - 100% free and runs locally
 * - No data leaves your server
 * - Supports multiple models (Mistral, Llama, etc.)
 * - Easy to install and configure
 * - Good performance on consumer hardware
 *
 * Recommended models:
 * - mistral (7B) - Best balance of quality and speed
 * - llama3 (8B) - Good for general tasks
 * - codellama (7B) - Better for code-related corrections
 */
export class OllamaProvider implements AIProvider {
  name = 'ollama';
  private baseUrl: string;
  private model: string;

  constructor() {
    this.baseUrl = env.OLLAMA_BASE_URL;
    this.model = env.OLLAMA_MODEL;
  }

  async isAvailable(): Promise<boolean> {
    try {
      const response = await fetch(`${this.baseUrl}/api/tags`);
      if (!response.ok) return false;

      const data = (await response.json()) as { models?: { name: string }[] };
      const models = data.models || [];

      const hasModel = models.some(
        (m) => m.name === this.model || m.name.startsWith(`${this.model}:`)
      );

      if (!hasModel) {
        logger.warn(
          `Ollama model "${this.model}" not found. Available models: ${models.map((m) => m.name).join(', ')}`
        );
        logger.info(`Run: ollama pull ${this.model}`);
      }

      return hasModel;
    } catch (error) {
      logger.error('Ollama not available:', error);
      return false;
    }
  }

  async complete(prompt: string, options?: CompletionOptions): Promise<string> {
    try {
      const response = await fetch(`${this.baseUrl}/api/generate`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          model: this.model,
          prompt: options?.systemPrompt
            ? `${options.systemPrompt}\n\n${prompt}`
            : prompt,
          stream: false,
          options: {
            temperature: options?.temperature ?? 0.3,
            num_predict: options?.maxTokens ?? 2048,
            top_p: options?.topP ?? 0.9,
            stop: options?.stopSequences,
          },
        }),
      });

      if (!response.ok) {
        const error = await response.text();
        throw new Error(`Ollama API error: ${error}`);
      }

      const data = (await response.json()) as { response: string };
      return data.response;
    } catch (error) {
      logger.error('Ollama completion error:', error);
      throw error;
    }
  }

  async *stream(
    prompt: string,
    options?: CompletionOptions
  ): AsyncGenerator<string, void, unknown> {
    const response = await fetch(`${this.baseUrl}/api/generate`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        model: this.model,
        prompt: options?.systemPrompt
          ? `${options.systemPrompt}\n\n${prompt}`
          : prompt,
        stream: true,
        options: {
          temperature: options?.temperature ?? 0.3,
          num_predict: options?.maxTokens ?? 2048,
          top_p: options?.topP ?? 0.9,
        },
      }),
    });

    if (!response.ok || !response.body) {
      throw new Error('Ollama stream error');
    }

    const reader = response.body.getReader();
    const decoder = new TextDecoder();

    try {
      while (true) {
        const { done, value } = await reader.read();
        if (done) break;

        const chunk = decoder.decode(value, { stream: true });
        const lines = chunk.split('\n').filter(Boolean);

        for (const line of lines) {
          try {
            const data = JSON.parse(line) as { response?: string };
            if (data.response) {
              yield data.response;
            }
          } catch {
            // Skip invalid JSON
          }
        }
      }
    } finally {
      reader.releaseLock();
    }
  }
}
