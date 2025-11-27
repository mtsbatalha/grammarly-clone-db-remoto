import { AIProvider, CompletionOptions } from '../types.js';
import { env } from '../../../config/env.js';
import { logger } from '../../../config/logger.js';

/**
 * GPT4All Provider - Local AI using GPT4All
 *
 * GPT4All provides:
 * - 100% local inference
 * - Multiple model support
 * - Good performance on CPU
 * - Privacy-focused
 *
 * Note: Requires GPT4All to be running with API server enabled
 * Start with: gpt4all --server
 */
export class GPT4AllProvider implements AIProvider {
  name = 'gpt4all';
  private baseUrl: string;
  private modelPath: string;

  constructor() {
    // GPT4All runs a local OpenAI-compatible API on port 4891 by default
    this.baseUrl = 'http://localhost:4891/v1';
    this.modelPath = env.GPT4ALL_MODEL_PATH || '';
  }

  async isAvailable(): Promise<boolean> {
    try {
      const response = await fetch(`${this.baseUrl}/models`);
      return response.ok;
    } catch (error) {
      logger.error('GPT4All not available:', error);
      logger.info('Make sure GPT4All is running with: gpt4all --server');
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
        },
        body: JSON.stringify({
          model: 'mistral-7b-instruct-v0.1.Q4_0',
          messages,
          temperature: options?.temperature ?? 0.3,
          max_tokens: options?.maxTokens ?? 2048,
          top_p: options?.topP ?? 0.9,
        }),
      });

      if (!response.ok) {
        const error = await response.text();
        throw new Error(`GPT4All API error: ${error}`);
      }

      const data = (await response.json()) as {
        choices: { message: { content: string } }[];
      };

      return data.choices[0]?.message?.content || '';
    } catch (error) {
      logger.error('GPT4All completion error:', error);
      throw error;
    }
  }
}
