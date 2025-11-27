import { AIProvider, CompletionOptions } from '../types.js';
import { env } from '../../../config/env.js';
import { logger } from '../../../config/logger.js';

/**
 * Groq AI Provider
 *
 * Uses Groq's ultra-fast inference API (free tier available)
 * API compatible with OpenAI format
 *
 * Get your free API key at: https://console.groq.com
 */
export class GroqProvider implements AIProvider {
  name = 'groq';
  private apiKey: string;
  private baseUrl: string;

  constructor() {
    this.apiKey = env.GROQ_API_KEY || '';
    this.baseUrl = 'https://api.groq.com/openai/v1';
  }

  async complete(prompt: string, options?: CompletionOptions): Promise<string> {
    if (!this.apiKey) {
      throw new Error(
        'GROQ_API_KEY não configurada. Obtenha sua chave gratuita em https://console.groq.com'
      );
    }

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

    try {
      const response = await fetch(`${this.baseUrl}/chat/completions`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer ${this.apiKey}`,
        },
        body: JSON.stringify({
          model: 'llama-3.3-70b-versatile', // Free, fast, and capable
          messages,
          temperature: options?.temperature ?? 0.3,
          max_tokens: options?.maxTokens ?? 2048,
        }),
      });

      if (!response.ok) {
        const error = await response.text();
        logger.error('Groq API error:', error);
        throw new Error(`Groq API error: ${error}`);
      }

      const data = (await response.json()) as {
        choices: { message: { content: string } }[];
      };

      return data.choices[0]?.message?.content || '';
    } catch (error) {
      logger.error('Groq completion failed:', error);
      throw error;
    }
  }

  async isAvailable(): Promise<boolean> {
    if (!this.apiKey) return false;

    try {
      const response = await fetch(`${this.baseUrl}/models`, {
        headers: {
          Authorization: `Bearer ${this.apiKey}`,
        },
      });
      return response.ok;
    } catch {
      return false;
    }
  }
}
