import { AIProvider, CompletionOptions } from '../types.js';
import { env } from '../../../config/env.js';
import { logger } from '../../../config/logger.js';

/**
 * Grok Provider - xAI's powerful AI model
 *
 * Grok offers:
 * - High quality text generation
 * - Fast response times
 * - Good multilingual support
 * - OpenAI-compatible API
 *
 * Note: Requires API key from https://console.x.ai/
 */
export class GrokProvider implements AIProvider {
  name = 'grok';
  private apiKey: string;
  private baseUrl: string;

  constructor() {
    this.apiKey = env.GROK_API_KEY || '';
    this.baseUrl = env.GROK_BASE_URL || 'https://api.x.ai/v1';
  }

  async isAvailable(): Promise<boolean> {
    if (!this.apiKey) {
      logger.warn('Grok API key not configured');
      return false;
    }

    try {
      const response = await fetch(`${this.baseUrl}/models`, {
        headers: {
          Authorization: `Bearer ${this.apiKey}`,
        },
      });
      return response.ok;
    } catch (error) {
      logger.error('Grok not available:', error);
      return false;
    }
  }

  async complete(prompt: string, options?: CompletionOptions): Promise<string> {
    try {
      const messages = [];

      if (options?.systemPrompt) {
        messages.push({
          role: 'system',
          content: options.systemPrompt,
        });
      }

      messages.push({
        role: 'user',
        content: prompt,
      });

      const response = await fetch(`${this.baseUrl}/chat/completions`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer ${this.apiKey}`,
        },
        body: JSON.stringify({
          model: 'grok-beta',
          messages,
          temperature: options?.temperature ?? 0.3,
          max_tokens: options?.maxTokens ?? 2048,
          top_p: options?.topP ?? 0.9,
          stop: options?.stopSequences,
        }),
      });

      if (!response.ok) {
        const error = await response.text();
        throw new Error(`Grok API error: ${error}`);
      }

      const data = (await response.json()) as {
        choices: { message: { content: string } }[];
      };

      return data.choices[0]?.message?.content || '';
    } catch (error) {
      logger.error('Grok completion error:', error);
      throw error;
    }
  }

  async *stream(
    prompt: string,
    options?: CompletionOptions
  ): AsyncGenerator<string, void, unknown> {
    const messages = [];

    if (options?.systemPrompt) {
      messages.push({
        role: 'system',
        content: options.systemPrompt,
      });
    }

    messages.push({
      role: 'user',
      content: prompt,
    });

    const response = await fetch(`${this.baseUrl}/chat/completions`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${this.apiKey}`,
      },
      body: JSON.stringify({
        model: 'grok-beta',
        messages,
        temperature: options?.temperature ?? 0.3,
        max_tokens: options?.maxTokens ?? 2048,
        stream: true,
      }),
    });

    if (!response.ok || !response.body) {
      throw new Error('Grok stream error');
    }

    const reader = response.body.getReader();
    const decoder = new TextDecoder();

    try {
      while (true) {
        const { done, value } = await reader.read();
        if (done) break;

        const chunk = decoder.decode(value, { stream: true });
        const lines = chunk.split('\n').filter((line) => line.startsWith('data:'));

        for (const line of lines) {
          const data = line.slice(5).trim();
          if (data === '[DONE]') return;

          try {
            const parsed = JSON.parse(data) as {
              choices: { delta: { content?: string } }[];
            };
            const content = parsed.choices[0]?.delta?.content;
            if (content) {
              yield content;
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
