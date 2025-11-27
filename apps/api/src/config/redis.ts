import Redis from 'ioredis';
import { env } from './env.js';
import { logger } from './logger.js';

export const redis = new Redis(env.REDIS_URL, {
  maxRetriesPerRequest: 3,
  retryStrategy(times) {
    const delay = Math.min(times * 50, 2000);
    return delay;
  },
});

redis.on('connect', () => {
  logger.info('✅ Redis connected');
});

redis.on('error', (error) => {
  logger.error('❌ Redis error:', error);
});

redis.on('close', () => {
  logger.warn('Redis connection closed');
});

// Cache helpers
export const cache = {
  async get<T>(key: string): Promise<T | null> {
    const data = await redis.get(key);
    if (!data) return null;
    return JSON.parse(data) as T;
  },

  async set(key: string, value: unknown, ttlSeconds?: number): Promise<void> {
    const data = JSON.stringify(value);
    if (ttlSeconds) {
      await redis.setex(key, ttlSeconds, data);
    } else {
      await redis.set(key, data);
    }
  },

  async del(key: string): Promise<void> {
    await redis.del(key);
  },

  async exists(key: string): Promise<boolean> {
    return (await redis.exists(key)) === 1;
  },

  async increment(key: string, ttlSeconds?: number): Promise<number> {
    const result = await redis.incr(key);
    if (ttlSeconds && result === 1) {
      await redis.expire(key, ttlSeconds);
    }
    return result;
  },

  async getMany<T>(keys: string[]): Promise<(T | null)[]> {
    if (keys.length === 0) return [];
    const data = await redis.mget(...keys);
    return data.map((item) => (item ? JSON.parse(item) : null));
  },
};

// Cache key generators
export const cacheKeys = {
  user: (id: string) => `user:${id}`,
  userSettings: (id: string) => `user:${id}:settings`,
  session: (token: string) => `session:${token}`,
  rateLimit: (ip: string) => `ratelimit:${ip}`,
  rateLimitUser: (userId: string) => `ratelimit:user:${userId}`,
  grammarCheck: (hash: string) => `grammar:${hash}`,
  document: (id: string) => `document:${id}`,
};
