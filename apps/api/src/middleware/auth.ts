import { Request, Response, NextFunction } from 'express';
import jwt from 'jsonwebtoken';
import { env } from '../config/env.js';
import { prisma } from '../config/database.js';
import { cache, cacheKeys } from '../config/redis.js';
import { ApiError } from '../utils/ApiError.js';

export interface JwtPayload {
  userId: string;
  email: string;
  plan: string;
}

declare global {
  namespace Express {
    interface Request {
      user?: {
        id: string;
        email: string;
        plan: string;
        name?: string | null;
      };
    }
  }
}

export const authenticate = async (
  req: Request,
  res: Response,
  next: NextFunction
) => {
  try {
    const authHeader = req.headers.authorization;

    if (!authHeader?.startsWith('Bearer ')) {
      throw new ApiError(401, 'Token de autenticação não fornecido');
    }

    const token = authHeader.substring(7);

    // Verify token
    const payload = jwt.verify(token, env.JWT_SECRET) as JwtPayload;

    // Check cache first
    let user = await cache.get<typeof req.user>(cacheKeys.user(payload.userId));

    if (!user) {
      // Fetch from database
      const dbUser = await prisma.user.findUnique({
        where: { id: payload.userId },
        select: {
          id: true,
          email: true,
          name: true,
          plan: true,
          status: true,
        },
      });

      if (!dbUser) {
        throw new ApiError(401, 'Usuário não encontrado');
      }

      if (dbUser.status !== 'ACTIVE') {
        throw new ApiError(403, 'Conta desativada ou suspensa');
      }

      user = {
        id: dbUser.id,
        email: dbUser.email,
        name: dbUser.name,
        plan: dbUser.plan,
      };

      // Cache for 5 minutes
      await cache.set(cacheKeys.user(payload.userId), user, 300);
    }

    req.user = user;
    next();
  } catch (error) {
    if (error instanceof jwt.JsonWebTokenError) {
      next(new ApiError(401, 'Token inválido'));
    } else if (error instanceof jwt.TokenExpiredError) {
      next(new ApiError(401, 'Token expirado'));
    } else {
      next(error);
    }
  }
};

export const optionalAuth = async (
  req: Request,
  res: Response,
  next: NextFunction
) => {
  const authHeader = req.headers.authorization;

  if (!authHeader?.startsWith('Bearer ')) {
    return next();
  }

  return authenticate(req, res, next);
};

export const requirePlan = (...plans: string[]) => {
  return (req: Request, res: Response, next: NextFunction) => {
    if (!req.user) {
      return next(new ApiError(401, 'Autenticação necessária'));
    }

    if (!plans.includes(req.user.plan)) {
      return next(
        new ApiError(
          403,
          `Este recurso requer um plano: ${plans.join(' ou ')}`
        )
      );
    }

    next();
  };
};
