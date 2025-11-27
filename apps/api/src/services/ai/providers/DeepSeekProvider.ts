import { AIProvider, CompletionOptions } from '../types.js';
import { env } from '../../../config/env.js';
import { logger } from '../../../config/logger.js';

/**
 * DeepSeek Provider - Cloud-based AI with free tier
 *
 * DeepSeek offers:
 * - Free API tier with generous limits
 * - High quality text generation
 * - Good multilingual support (PT/EN)
 * - OpenAI-compatible API
 *
 * Note: Requires API key from https://platform.deepseek.com/
 */
export class DeepSeekProvider implements AIProvider {
  name = 'deepseek';
  private apiKey: string;
  private baseUrl: string;

  constructor() {
    this.apiKey = env.DEEPSEEK_API_KEY || '';
    this.baseUrl = env.DEEPSEEK_BASE_URL || 'https://api.deepseek.com/v1';
  }

  async isAvailable(): Promise<boolean> {
    if (!this.apiKey) {
      logger.warn('DeepSeek API key not configured');
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
      logger.error('DeepSeek not available:', error);
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
          model: 'deepseek-chat',
          messages,
          temperature: options?.temperature ?? 0.3,
          max_tokens: options?.maxTokens ?? 2048,
          top_p: options?.topP ?? 0.9,
          stop: options?.stopSequences,
        }),
      });

      if (!response.ok) {
        const error = await response.text();
        throw new Error(`DeepSeek API error: ${error}`);
      }

      const data = (await response.json()) as {
        choices: { message: { content: string } }[];
      };

      return data.choices[0]?.message?.content || '';
    } catch (error) {
      logger.error('DeepSeek completion error:', error);
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
        model: 'deepseek-chat',
        messages,
        temperature: options?.temperature ?? 0.3,
        max_tokens: options?.maxTokens ?? 2048,
        stream: true,
      }),
    });

    if (!response.ok || !response.body) {
      throw new Error('DeepSeek stream error');
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
