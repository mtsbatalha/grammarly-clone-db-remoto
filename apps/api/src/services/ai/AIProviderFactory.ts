import { AIProvider } from './types.js';
import { OllamaProvider } from './providers/OllamaProvider.js';
import { DeepSeekProvider } from './providers/DeepSeekProvider.js';
import { GPT4AllProvider } from './providers/GPT4AllProvider.js';
import { GrokProvider } from './providers/GrokProvider.js';
import { GroqProvider } from './providers/GroqProvider.js';
import { env } from '../../config/env.js';
import { logger } from '../../config/logger.js';

/**
 * AI Provider Factory
 *
 * This factory creates the appropriate AI provider based on configuration.
 * It allows easy switching between different AI backends.
 *
 * Recommended order of preference:
 * 1. Ollama (local, free, good quality)
 * 2. DeepSeek (cloud, free tier available)
 * 3. Grok (xAI, fast and powerful)
 * 4. GPT4All (local, free, good for CPU)
 *
 * To switch providers, change AI_PROVIDER in your .env file.
 */
export class AIProviderFactory {
  private static instance: AIProvider | null = null;
  private static providers = new Map<string, () => AIProvider>([
    ['ollama', () => new OllamaProvider() as AIProvider],
    ['deepseek', () => new DeepSeekProvider() as AIProvider],
    ['grok', () => new GrokProvider() as AIProvider],
    ['groq', () => new GroqProvider() as AIProvider],
    ['gpt4all', () => new GPT4AllProvider() as AIProvider],
  ]);

  /**
   * Create or return the configured AI provider
   */
  static create(providerName?: string): AIProvider {
    const name = providerName || env.AI_PROVIDER;

    if (this.instance && !providerName) {
      return this.instance;
    }

    const factory = this.providers.get(name);

    if (!factory) {
      logger.error(`Unknown AI provider: ${name}`);
      logger.info(`Available providers: ${Array.from(this.providers.keys()).join(', ')}`);
      throw new Error(`Unknown AI provider: ${name}`);
    }

    const provider = factory();
    logger.info(`Using AI provider: ${provider.name}`);

    if (!providerName) {
      this.instance = provider;
    }

    return provider;
  }

  /**
   * Get the first available provider (fallback mechanism)
   */
  static async getAvailable(): Promise<AIProvider> {
    const preferredOrder = ['ollama', 'deepseek', 'gpt4all'];

    for (const name of preferredOrder) {
      try {
        const provider = this.create(name);
        const isAvailable = await provider.isAvailable();

        if (isAvailable) {
          logger.info(`Using available AI provider: ${name}`);
          this.instance = provider;
          return provider;
        }
      } catch (error) {
        logger.warn(`Provider ${name} not available:`, error);
      }
    }

    throw new Error('No AI provider available. Please install Ollama or configure another provider.');
  }

  /**
   * Register a custom provider
   */
  static register(name: string, factory: () => AIProvider): void {
    this.providers.set(name, factory);
    logger.info(`Registered custom AI provider: ${name}`);
  }

  /**
   * Check which providers are available
   */
  static async checkAvailability(): Promise<{ name: string; available: boolean }[]> {
    const results = [];

    for (const [name, factory] of this.providers) {
      try {
        const provider = factory();
        const available = await provider.isAvailable();
        results.push({ name, available });
      } catch {
        results.push({ name, available: false });
      }
    }

    return results;
  }

  /**
   * Reset the singleton instance (useful for testing)
   */
  static reset(): void {
    this.instance = null;
  }
}
