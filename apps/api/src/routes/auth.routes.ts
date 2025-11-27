import { Router } from 'express';
import { z } from 'zod';
import bcrypt from 'bcryptjs';
import jwt from 'jsonwebtoken';
import { v4 as uuidv4 } from 'uuid';
import { prisma } from '../config/database.js';
import { env } from '../config/env.js';
import { cache, cacheKeys } from '../config/redis.js';
import { ApiError } from '../utils/ApiError.js';
import { authenticate } from '../middleware/auth.js';

const router = Router();

// Schemas
const registerSchema = z.object({
  email: z.string().email('Email inválido'),
  password: z.string().min(8, 'Senha deve ter no mínimo 8 caracteres'),
  name: z.string().min(2, 'Nome deve ter no mínimo 2 caracteres').optional(),
});

const loginSchema = z.object({
  email: z.string().email('Email inválido'),
  password: z.string().min(1, 'Senha é obrigatória'),
});

const refreshSchema = z.object({
  refreshToken: z.string(),
});

// Helper to generate tokens
function generateTokens(userId: string, email: string, plan: string) {
  const accessToken = jwt.sign(
    { userId, email, plan },
    env.JWT_SECRET,
    { expiresIn: '7d' }
  );

  const refreshToken = uuidv4();

  return { accessToken, refreshToken };
}

// POST /api/v1/auth/register
router.post('/register', async (req, res, next) => {
  try {
    const body = registerSchema.parse(req.body);

    // Check if user exists
    const existingUser = await prisma.user.findUnique({
      where: { email: body.email },
    });

    if (existingUser) {
      throw new ApiError(409, 'Email já cadastrado');
    }

    // Hash password
    const passwordHash = await bcrypt.hash(body.password, 12);

    // Create user with settings and statistics
    const user = await prisma.user.create({
      data: {
        email: body.email,
        passwordHash,
        name: body.name,
        settings: {
          create: {},
        },
      },
      select: {
        id: true,
        email: true,
        name: true,
        plan: true,
        createdAt: true,
      },
    });

    // Create statistics
    await prisma.userStatistics.create({
      data: { userId: user.id },
    });

    // Generate tokens
    const { accessToken, refreshToken } = generateTokens(
      user.id,
      user.email,
      user.plan
    );

    // Save session
    const expiresAt = new Date();
    expiresAt.setDate(expiresAt.getDate() + 30);

    await prisma.session.create({
      data: {
        userId: user.id,
        token: accessToken,
        refreshToken,
        userAgent: req.headers['user-agent'],
        ipAddress: req.ip,
        expiresAt,
      },
    });

    res.status(201).json({
      message: 'Usuário criado com sucesso',
      user,
      accessToken,
      refreshToken,
    });
  } catch (error) {
    next(error);
  }
});

// POST /api/v1/auth/login
router.post('/login', async (req, res, next) => {
  try {
    const body = loginSchema.parse(req.body);

    // Find user
    const user = await prisma.user.findUnique({
      where: { email: body.email },
      select: {
        id: true,
        email: true,
        name: true,
        plan: true,
        status: true,
        passwordHash: true,
      },
    });

    if (!user) {
      throw new ApiError(401, 'Email ou senha incorretos');
    }

    if (user.status !== 'ACTIVE') {
      throw new ApiError(403, 'Conta desativada ou suspensa');
    }

    // Check password
    const isValidPassword = await bcrypt.compare(body.password, user.passwordHash);

    if (!isValidPassword) {
      throw new ApiError(401, 'Email ou senha incorretos');
    }

    // Generate tokens
    const { accessToken, refreshToken } = generateTokens(
      user.id,
      user.email,
      user.plan
    );

    // Save session
    const expiresAt = new Date();
    expiresAt.setDate(expiresAt.getDate() + 30);

    await prisma.session.create({
      data: {
        userId: user.id,
        token: accessToken,
        refreshToken,
        userAgent: req.headers['user-agent'],
        ipAddress: req.ip,
        expiresAt,
      },
    });

    // Update last login
    await prisma.user.update({
      where: { id: user.id },
      data: { lastLoginAt: new Date() },
    });

    // Clear cache
    await cache.del(cacheKeys.user(user.id));

    const { passwordHash: _, ...userWithoutPassword } = user;

    res.json({
      message: 'Login realizado com sucesso',
      user: userWithoutPassword,
      accessToken,
      refreshToken,
    });
  } catch (error) {
    next(error);
  }
});

// POST /api/v1/auth/refresh
router.post('/refresh', async (req, res, next) => {
  try {
    const body = refreshSchema.parse(req.body);

    // Find session
    const session = await prisma.session.findUnique({
      where: { refreshToken: body.refreshToken },
      include: {
        user: {
          select: {
            id: true,
            email: true,
            plan: true,
            status: true,
          },
        },
      },
    });

    if (!session) {
      throw new ApiError(401, 'Refresh token inválido');
    }

    if (session.expiresAt < new Date()) {
      await prisma.session.delete({ where: { id: session.id } });
      throw new ApiError(401, 'Refresh token expirado');
    }

    if (session.user.status !== 'ACTIVE') {
      throw new ApiError(403, 'Conta desativada ou suspensa');
    }

    // Generate new tokens
    const { accessToken, refreshToken } = generateTokens(
      session.user.id,
      session.user.email,
      session.user.plan
    );

    // Update session
    const expiresAt = new Date();
    expiresAt.setDate(expiresAt.getDate() + 30);

    await prisma.session.update({
      where: { id: session.id },
      data: {
        token: accessToken,
        refreshToken,
        expiresAt,
      },
    });

    res.json({
      accessToken,
      refreshToken,
    });
  } catch (error) {
    next(error);
  }
});

// POST /api/v1/auth/logout
router.post('/logout', authenticate, async (req, res, next) => {
  try {
    const authHeader = req.headers.authorization;
    const token = authHeader?.substring(7);

    if (token) {
      await prisma.session.deleteMany({
        where: { token },
      });
    }

    // Clear cache
    if (req.user) {
      await cache.del(cacheKeys.user(req.user.id));
    }

    res.json({ message: 'Logout realizado com sucesso' });
  } catch (error) {
    next(error);
  }
});

// GET /api/v1/auth/me
router.get('/me', authenticate, async (req, res, next) => {
  try {
    const user = await prisma.user.findUnique({
      where: { id: req.user!.id },
      select: {
        id: true,
        email: true,
        name: true,
        avatar: true,
        plan: true,
        preferredLanguage: true,
        dailyChecks: true,
        dailyChecksLimit: true,
        createdAt: true,
        settings: true,
      },
    });

    if (!user) {
      throw new ApiError(404, 'Usuário não encontrado');
    }

    res.json({ user });
  } catch (error) {
    next(error);
  }
});

export default router;
