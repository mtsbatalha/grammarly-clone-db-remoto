import { Router } from 'express';
import { z } from 'zod';
import crypto from 'crypto';
import { prisma } from '../config/database.js';
import { cache, cacheKeys } from '../config/redis.js';
import { ApiError } from '../utils/ApiError.js';
import { authenticate, optionalAuth } from '../middleware/auth.js';
import { userRateLimiter } from '../middleware/rateLimiter.js';
import { AIProviderFactory } from '../services/ai/AIProviderFactory.js';
import { GrammarService } from '../services/GrammarService.js';

const router = Router();

// Schemas
const checkGrammarSchema = z.object({
  text: z.string().min(1).max(50000),
  language: z.enum(['PT_BR', 'EN_US', 'EN_GB', 'ES_ES', 'ES_MX']).default('PT_BR'),
  documentId: z.string().uuid().optional(),
  options: z
    .object({
      enableGrammar: z.boolean().default(true),
      enableSpelling: z.boolean().default(true),
      enablePunctuation: z.boolean().default(true),
      enableStyle: z.boolean().default(true),
      enableTone: z.boolean().default(false),
      enableClarity: z.boolean().default(true),
      targetTone: z
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
    })
    .optional(),
});

const toneAdjustSchema = z.object({
  text: z.string().min(1).max(10000),
  language: z.enum(['PT_BR', 'EN_US', 'EN_GB', 'ES_ES', 'ES_MX']).default('PT_BR'),
  targetTone: z.enum([
    'FORMAL',
    'INFORMAL',
    'CONFIDENT',
    'NEUTRAL',
    'FRIENDLY',
    'PROFESSIONAL',
    'DIRECT',
    'DIPLOMATIC',
  ]),
});

const correctionActionSchema = z.object({
  action: z.enum(['accept', 'ignore']),
});

// Initialize services
const aiProvider = AIProviderFactory.create();
const grammarService = new GrammarService(aiProvider);

// POST /api/v1/grammar/check
router.post('/check', optionalAuth, userRateLimiter, async (req, res, next) => {
  try {
    const body = checkGrammarSchema.parse(req.body);

    // Check daily limit for authenticated users
    if (req.user) {
      const user = await prisma.user.findUnique({
        where: { id: req.user.id },
        select: {
          dailyChecks: true,
          dailyChecksLimit: true,
          lastCheckReset: true,
          plan: true,
          settings: true,
        },
      });

      if (user) {
        // Reset daily checks if new day
        const today = new Date();
        today.setHours(0, 0, 0, 0);

        if (user.lastCheckReset < today) {
          await prisma.user.update({
            where: { id: req.user.id },
            data: {
              dailyChecks: 0,
              lastCheckReset: today,
            },
          });
          user.dailyChecks = 0;
        }

        // Check limit
        if (
          user.plan === 'FREE' &&
          user.dailyChecks >= user.dailyChecksLimit
        ) {
          throw new ApiError(
            429,
            'Limite diário de verificações atingido. Faça upgrade para o plano Pro.',
            'DAILY_LIMIT_EXCEEDED'
          );
        }

        // Merge user settings with request options
        if (user.settings && !body.options) {
          body.options = {
            enableGrammar: user.settings.enableGrammar,
            enableSpelling: user.settings.enableSpelling,
            enablePunctuation: user.settings.enablePunctuation,
            enableStyle: user.settings.enableStyle,
            enableTone: user.settings.enableTone,
            enableClarity: user.settings.enableClarity,
            targetTone: user.settings.preferredTone,
          };
        }
      }
    }

    // Generate cache key
    const cacheKey = cacheKeys.grammarCheck(
      crypto
        .createHash('md5')
        .update(
          JSON.stringify({
            text: body.text,
            language: body.language,
            options: body.options,
          })
        )
        .digest('hex')
    );

    // Check cache
    const cached = await cache.get<{
      corrections: unknown[];
      stats: unknown;
    }>(cacheKey);

    if (cached) {
      return res.json({
        ...cached,
        cached: true,
      });
    }

    // Perform grammar check
    const result = await grammarService.check(
      body.text,
      body.language,
      body.options
    );

    // Save corrections to database if user is authenticated
    if (req.user && result.corrections.length > 0) {
      const correctionsData = result.corrections.map((c) => ({
        userId: req.user!.id,
        documentId: body.documentId || null,
        originalText: c.originalText,
        context: c.context,
        startOffset: c.startOffset,
        endOffset: c.endOffset,
        type: c.type,
        severity: c.severity,
        suggestion: c.suggestion,
        explanation: c.explanation,
        rule: c.rule,
        language: body.language,
      }));

      await prisma.correction.createMany({
        data: correctionsData,
      });

      // Update user stats
      await prisma.$transaction([
        prisma.user.update({
          where: { id: req.user.id },
          data: { dailyChecks: { increment: 1 } },
        }),
        prisma.userStatistics.upsert({
          where: { userId: req.user.id },
          update: {
            totalCorrections: { increment: result.corrections.length },
            totalWordsChecked: { increment: result.stats.wordCount },
            grammarErrors: {
              increment: result.corrections.filter(
                (c) => c.type === 'GRAMMAR'
              ).length,
            },
            spellingErrors: {
              increment: result.corrections.filter(
                (c) => c.type === 'SPELLING'
              ).length,
            },
            punctuationErrors: {
              increment: result.corrections.filter(
                (c) => c.type === 'PUNCTUATION'
              ).length,
            },
            styleIssues: {
              increment: result.corrections.filter((c) => c.type === 'STYLE')
                .length,
            },
          },
          create: {
            userId: req.user.id,
            totalCorrections: result.corrections.length,
            totalWordsChecked: result.stats.wordCount,
          },
        }),
      ]);
    }

    // Cache result for 1 hour
    await cache.set(cacheKey, result, 3600);

    res.json(result);
  } catch (error) {
    next(error);
  }
});

// POST /api/v1/grammar/tone
router.post('/tone', authenticate, userRateLimiter, async (req, res, next) => {
  try {
    const body = toneAdjustSchema.parse(req.body);

    const result = await grammarService.adjustTone(
      body.text,
      body.targetTone,
      body.language
    );

    // Update stats
    await prisma.userStatistics.upsert({
      where: { userId: req.user!.id },
      update: { toneAdjustments: { increment: 1 } },
      create: { userId: req.user!.id, toneAdjustments: 1 },
    });

    res.json(result);
  } catch (error) {
    next(error);
  }
});

// POST /api/v1/grammar/rewrite
router.post(
  '/rewrite',
  optionalAuth,
  userRateLimiter,
  async (req, res, next) => {
    try {
      const { text, language, style } = z
        .object({
          text: z.string().min(1).max(5000),
          language: z.enum(['PT_BR', 'EN_US', 'EN_GB', 'ES_ES', 'ES_MX']).default('PT_BR'),
          style: z
            .enum(['concise', 'expanded', 'simplified', 'formal', 'better', 'shorter', 'longer'])
            .default('better'),
        })
        .parse(req.body);

      const result = await grammarService.rewrite(text, style, language);

      res.json(result);
    } catch (error) {
      next(error);
    }
  }
);

// POST /api/v1/grammar/translate
router.post(
  '/translate',
  optionalAuth,
  userRateLimiter,
  async (req, res, next) => {
    try {
      const { text, targetLanguage } = z
        .object({
          text: z.string().min(1).max(5000),
          targetLanguage: z.enum(['PT_BR', 'EN_US', 'EN_GB', 'ES_ES', 'ES_MX']),
        })
        .parse(req.body);

      const result = await grammarService.translate(text, targetLanguage);

      res.json(result);
    } catch (error) {
      next(error);
    }
  }
);

// PATCH /api/v1/grammar/corrections/:id
router.patch(
  '/corrections/:id',
  authenticate,
  async (req, res, next) => {
    try {
      const { id } = req.params;
      const { action } = correctionActionSchema.parse(req.body);

      const correction = await prisma.correction.findFirst({
        where: { id, userId: req.user!.id },
      });

      if (!correction) {
        throw new ApiError(404, 'Correção não encontrada');
      }

      if (action === 'accept') {
        await prisma.correction.update({
          where: { id },
          data: { isAccepted: true },
        });

        await prisma.userStatistics.update({
          where: { userId: req.user!.id },
          data: { correctionsAccepted: { increment: 1 } },
        });
      } else {
        await prisma.correction.update({
          where: { id },
          data: { isIgnored: true },
        });

        await prisma.userStatistics.update({
          where: { userId: req.user!.id },
          data: { correctionsIgnored: { increment: 1 } },
        });
      }

      res.json({ message: 'Correção atualizada' });
    } catch (error) {
      next(error);
    }
  }
);

// GET /api/v1/grammar/languages
router.get('/languages', (_req, res) => {
  res.json({
    languages: [
      { code: 'PT_BR', name: 'Português (Brasil)', flag: '🇧🇷' },
      { code: 'EN_US', name: 'English (US)', flag: '🇺🇸' },
      { code: 'EN_GB', name: 'English (UK)', flag: '🇬🇧' },
      { code: 'ES_ES', name: 'Español (España)', flag: '🇪🇸' },
      { code: 'ES_MX', name: 'Español (México)', flag: '🇲🇽' },
    ],
  });
});

// GET /api/v1/grammar/tones
router.get('/tones', (_req, res) => {
  res.json({
    tones: [
      { code: 'FORMAL', name: 'Formal', description: 'Linguagem profissional e respeitosa' },
      { code: 'INFORMAL', name: 'Informal', description: 'Linguagem casual e descontraída' },
      { code: 'CONFIDENT', name: 'Confiante', description: 'Tom assertivo e seguro' },
      { code: 'NEUTRAL', name: 'Neutro', description: 'Tom equilibrado e objetivo' },
      { code: 'FRIENDLY', name: 'Amigável', description: 'Tom caloroso e acolhedor' },
      { code: 'PROFESSIONAL', name: 'Profissional', description: 'Tom corporativo e sério' },
      { code: 'DIRECT', name: 'Direto', description: 'Tom objetivo e sem rodeios' },
      { code: 'DIPLOMATIC', name: 'Diplomático', description: 'Tom cuidadoso e ponderado' },
    ],
  });
});

export default router;
