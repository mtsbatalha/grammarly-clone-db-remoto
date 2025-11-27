import { Router } from 'express';
import { z } from 'zod';
import bcrypt from 'bcryptjs';
import { prisma } from '../config/database.js';
import { cache, cacheKeys } from '../config/redis.js';
import { ApiError } from '../utils/ApiError.js';
import { authenticate } from '../middleware/auth.js';
import { env } from '../config/env.js';

const router = Router();

// All routes require authentication
router.use(authenticate);

// Schemas
const updateProfileSchema = z.object({
  name: z.string().min(2).max(100).optional(),
  preferredLanguage: z.enum(['PT_BR', 'EN_US', 'EN_GB']).optional(),
});

const updatePasswordSchema = z.object({
  currentPassword: z.string().min(1, 'Senha atual é obrigatória'),
  newPassword: z.string().min(8, 'Nova senha deve ter no mínimo 8 caracteres'),
});

const updateSettingsSchema = z.object({
  enableGrammar: z.boolean().optional(),
  enableSpelling: z.boolean().optional(),
  enablePunctuation: z.boolean().optional(),
  enableStyle: z.boolean().optional(),
  enableTone: z.boolean().optional(),
  enableClarity: z.boolean().optional(),
  preferredTone: z
    .enum([
      'FORMAL',
      'INFORMAL',
      'CONFIDENT',
      'NEUTRAL',
      'FRIENDLY',
      'PROFESSIONAL',
      'DIRECT',
      'DIPLOMATIC',
    ])
    .optional(),
  showInlineCorrections: z.boolean().optional(),
  autoCorrect: z.boolean().optional(),
  darkMode: z.boolean().optional(),
  personalDictionary: z.array(z.string()).optional(),
  ignoredRules: z.array(z.string()).optional(),
});

// GET /api/v1/users/profile
router.get('/profile', async (req, res, next) => {
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
        lastLoginAt: true,
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

// PATCH /api/v1/users/profile
router.patch('/profile', async (req, res, next) => {
  try {
    const body = updateProfileSchema.parse(req.body);

    const user = await prisma.user.update({
      where: { id: req.user!.id },
      data: body,
      select: {
        id: true,
        email: true,
        name: true,
        avatar: true,
        plan: true,
        preferredLanguage: true,
      },
    });

    // Clear cache
    await cache.del(cacheKeys.user(req.user!.id));

    res.json({
      message: 'Perfil atualizado com sucesso',
      user,
    });
  } catch (error) {
    next(error);
  }
});

// PATCH /api/v1/users/password
router.patch('/password', async (req, res, next) => {
  try {
    const body = updatePasswordSchema.parse(req.body);

    const user = await prisma.user.findUnique({
      where: { id: req.user!.id },
      select: { passwordHash: true },
    });

    if (!user) {
      throw new ApiError(404, 'Usuário não encontrado');
    }

    // Verify current password
    const isValid = await bcrypt.compare(body.currentPassword, user.passwordHash);

    if (!isValid) {
      throw new ApiError(400, 'Senha atual incorreta');
    }

    // Hash new password
    const newPasswordHash = await bcrypt.hash(body.newPassword, 12);

    await prisma.user.update({
      where: { id: req.user!.id },
      data: { passwordHash: newPasswordHash },
    });

    // Invalidate all sessions except current
    const authHeader = req.headers.authorization;
    const currentToken = authHeader?.substring(7);

    await prisma.session.deleteMany({
      where: {
        userId: req.user!.id,
        token: { not: currentToken },
      },
    });

    res.json({ message: 'Senha alterada com sucesso' });
  } catch (error) {
    next(error);
  }
});

// GET /api/v1/users/settings
router.get('/settings', async (req, res, next) => {
  try {
    let settings = await prisma.userSettings.findUnique({
      where: { userId: req.user!.id },
    });

    if (!settings) {
      settings = await prisma.userSettings.create({
        data: { userId: req.user!.id },
      });
    }

    res.json({ settings });
  } catch (error) {
    next(error);
  }
});

// PATCH /api/v1/users/settings
router.patch('/settings', async (req, res, next) => {
  try {
    const body = updateSettingsSchema.parse(req.body);

    const settings = await prisma.userSettings.upsert({
      where: { userId: req.user!.id },
      update: body,
      create: {
        userId: req.user!.id,
        ...body,
      },
    });

    // Clear cache
    await cache.del(cacheKeys.userSettings(req.user!.id));

    res.json({
      message: 'Configurações atualizadas com sucesso',
      settings,
    });
  } catch (error) {
    next(error);
  }
});

// POST /api/v1/users/dictionary
router.post('/dictionary', async (req, res, next) => {
  try {
    const { word } = z.object({ word: z.string().min(1) }).parse(req.body);

    const settings = await prisma.userSettings.findUnique({
      where: { userId: req.user!.id },
    });

    const currentDictionary = settings?.personalDictionary || [];

    if (currentDictionary.includes(word.toLowerCase())) {
      return res.json({ message: 'Palavra já existe no dicionário' });
    }

    await prisma.userSettings.upsert({
      where: { userId: req.user!.id },
      update: {
        personalDictionary: [...currentDictionary, word.toLowerCase()],
      },
      create: {
        userId: req.user!.id,
        personalDictionary: [word.toLowerCase()],
      },
    });

    res.json({ message: 'Palavra adicionada ao dicionário' });
  } catch (error) {
    next(error);
  }
});

// DELETE /api/v1/users/dictionary/:word
router.delete('/dictionary/:word', async (req, res, next) => {
  try {
    const word = req.params.word.toLowerCase();

    const settings = await prisma.userSettings.findUnique({
      where: { userId: req.user!.id },
    });

    if (!settings) {
      throw new ApiError(404, 'Configurações não encontradas');
    }

    const updatedDictionary = settings.personalDictionary.filter(
      (w) => w !== word
    );

    await prisma.userSettings.update({
      where: { userId: req.user!.id },
      data: { personalDictionary: updatedDictionary },
    });

    res.json({ message: 'Palavra removida do dicionário' });
  } catch (error) {
    next(error);
  }
});

// DELETE /api/v1/users/account
router.delete('/account', async (req, res, next) => {
  try {
    const { password } = z
      .object({ password: z.string().min(1) })
      .parse(req.body);

    const user = await prisma.user.findUnique({
      where: { id: req.user!.id },
      select: { passwordHash: true },
    });

    if (!user) {
      throw new ApiError(404, 'Usuário não encontrado');
    }

    const isValid = await bcrypt.compare(password, user.passwordHash);

    if (!isValid) {
      throw new ApiError(400, 'Senha incorreta');
    }

    // Delete user (cascade will delete related data)
    await prisma.user.delete({
      where: { id: req.user!.id },
    });

    // Clear cache
    await cache.del(cacheKeys.user(req.user!.id));

    res.json({ message: 'Conta excluída com sucesso' });
  } catch (error) {
    next(error);
  }
});

// GET /api/v1/users/ai-config
router.get('/ai-config', async (req, res, next) => {
  try {
    // Mask API keys for security (show only last 4 characters)
    const maskKey = (key: string | undefined) => {
      if (!key) return null;
      if (key.length <= 8) return '****';
      return '****' + key.slice(-4);
    };

    const providers = [
      {
        id: 'groq',
        name: 'Groq',
        description: 'API gratuita, rápida (LLaMA 3.3 70B)',
        website: 'https://console.groq.com',
        configured: !!env.GROQ_API_KEY,
        apiKey: maskKey(env.GROQ_API_KEY),
      },
      {
        id: 'grok',
        name: 'Grok (xAI)',
        description: 'IA da xAI (Elon Musk)',
        website: 'https://console.x.ai',
        configured: !!env.GROK_API_KEY,
        apiKey: maskKey(env.GROK_API_KEY),
      },
      {
        id: 'deepseek',
        name: 'DeepSeek',
        description: 'Modelo chinês de alta performance',
        website: 'https://platform.deepseek.com',
        configured: !!env.DEEPSEEK_API_KEY,
        apiKey: maskKey(env.DEEPSEEK_API_KEY),
      },
      {
        id: 'ollama',
        name: 'Ollama',
        description: 'Modelos locais (requer instalação)',
        website: 'https://ollama.ai',
        configured: true,
        model: env.OLLAMA_MODEL,
      },
    ];

    res.json({
      currentProvider: env.AI_PROVIDER,
      providers,
      note: 'Para alterar o provedor ou API keys, edite o arquivo .env e reinicie os containers.',
    });
  } catch (error) {
    next(error);
  }
});

export default router;
