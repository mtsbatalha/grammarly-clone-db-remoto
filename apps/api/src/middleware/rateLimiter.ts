import { Request, Response, NextFunction } from 'express';
import { env } from '../config/env.js';
import { cache, cacheKeys } from '../config/redis.js';
import { ApiError } from '../utils/ApiError.js';

export const rateLimiter = async (
  req: Request,
  res: Response,
  next: NextFunction
) => {
  try {
    const ip = req.ip || req.socket.remoteAddress || 'unknown';
    const key = cacheKeys.rateLimit(ip);

    const current = await cache.increment(
      key,
      env.RATE_LIMIT_WINDOW_MS / 1000
    );

    // Set headers
    res.setHeader('X-RateLimit-Limit', env.RATE_LIMIT_MAX_REQUESTS);
    res.setHeader(
      'X-RateLimit-Remaining',
      Math.max(0, env.RATE_LIMIT_MAX_REQUESTS - current)
    );

    if (current > env.RATE_LIMIT_MAX_REQUESTS) {
      throw new ApiError(
        429,
        'Muitas requisições. Tente novamente em alguns minutos.',
        'RATE_LIMIT_EXCEEDED'
      );
    }

    next();
  } catch (error) {
    if (error instanceof ApiError) {
      next(error);
    } else {
      // If Redis fails, allow the request
      next();
    }
  }
};

export const userRateLimiter = async (
  req: Request,
  res: Response,
  next: NextFunction
) => {
  try {
    if (!req.user) {
      return next();
    }

    const key = cacheKeys.rateLimitUser(req.user.id);
    const limit =
      req.user.plan === 'PRO' || req.user.plan === 'ENTERPRISE'
        ? env.RATE_LIMIT_MAX_REQUESTS_PRO
        : env.RATE_LIMIT_MAX_REQUESTS;

    const current = await cache.increment(
      key,
      env.RATE_LIMIT_WINDOW_MS / 1000
    );

    res.setHeader('X-RateLimit-Limit', limit);
    res.setHeader('X-RateLimit-Remaining', Math.max(0, limit - current));

    if (current > limit) {
      const upgradeMsg =
        req.user.plan === 'FREE'
          ? ' Faça upgrade para o plano Pro para mais requisições.'
          : '';
      throw new ApiError(
        429,
        `Limite de requisições atingido.${upgradeMsg}`,
        'USER_RATE_LIMIT_EXCEEDED'
      );
    }

    next();
  } catch (error) {
    if (error instanceof ApiError) {
      next(error);
    } else {
      next();
    }
  }
};
