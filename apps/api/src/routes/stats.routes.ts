import { Router } from 'express';
import { prisma } from '../config/database.js';
import { authenticate } from '../middleware/auth.js';

const router = Router();

router.use(authenticate);

// GET /api/v1/stats
router.get('/', async (req, res, next) => {
  try {
    const stats = await prisma.userStatistics.findUnique({
      where: { userId: req.user!.id },
    });

    if (!stats) {
      return res.json({
        totalDocuments: 0,
        totalCorrections: 0,
        totalWordsChecked: 0,
        grammarErrors: 0,
        spellingErrors: 0,
        punctuationErrors: 0,
        styleIssues: 0,
        toneAdjustments: 0,
        correctionsAccepted: 0,
        correctionsIgnored: 0,
        acceptanceRate: 0,
        currentStreak: 0,
        longestStreak: 0,
      });
    }

    const totalResponded = stats.correctionsAccepted + stats.correctionsIgnored;
    const acceptanceRate =
      totalResponded > 0
        ? Math.round((stats.correctionsAccepted / totalResponded) * 100)
        : 0;

    res.json({
      ...stats,
      acceptanceRate,
    });
  } catch (error) {
    next(error);
  }
});

// GET /api/v1/stats/weekly
router.get('/weekly', async (req, res, next) => {
  try {
    const sevenDaysAgo = new Date();
    sevenDaysAgo.setDate(sevenDaysAgo.getDate() - 7);

    const corrections = await prisma.correction.groupBy({
      by: ['createdAt'],
      where: {
        userId: req.user!.id,
        createdAt: { gte: sevenDaysAgo },
      },
      _count: true,
    });

    // Group by date
    const daily: Record<string, number> = {};
    for (let i = 0; i < 7; i++) {
      const date = new Date();
      date.setDate(date.getDate() - i);
      const key = date.toISOString().split('T')[0];
      daily[key] = 0;
    }

    corrections.forEach((c) => {
      const key = new Date(c.createdAt).toISOString().split('T')[0];
      if (daily[key] !== undefined) {
        daily[key] += c._count;
      }
    });

    res.json({
      daily: Object.entries(daily)
        .map(([date, count]) => ({ date, count }))
        .reverse(),
    });
  } catch (error) {
    next(error);
  }
});

// GET /api/v1/stats/corrections-by-type
router.get('/corrections-by-type', async (req, res, next) => {
  try {
    const byType = await prisma.correction.groupBy({
      by: ['type'],
      where: { userId: req.user!.id },
      _count: true,
    });

    const result = byType.map((item) => ({
      type: item.type,
      count: item._count,
    }));

    res.json({ byType: result });
  } catch (error) {
    next(error);
  }
});

// GET /api/v1/stats/recent-activity
router.get('/recent-activity', async (req, res, next) => {
  try {
    const [recentDocuments, recentCorrections] = await Promise.all([
      prisma.document.findMany({
        where: { userId: req.user!.id },
        orderBy: { updatedAt: 'desc' },
        take: 5,
        select: {
          id: true,
          title: true,
          wordCount: true,
          updatedAt: true,
        },
      }),
      prisma.correction.findMany({
        where: { userId: req.user!.id },
        orderBy: { createdAt: 'desc' },
        take: 10,
        select: {
          id: true,
          type: true,
          originalText: true,
          suggestion: true,
          isAccepted: true,
          createdAt: true,
        },
      }),
    ]);

    res.json({
      recentDocuments,
      recentCorrections,
    });
  } catch (error) {
    next(error);
  }
});

// GET /api/v1/stats/usage
router.get('/usage', async (req, res, next) => {
  try {
    const user = await prisma.user.findUnique({
      where: { id: req.user!.id },
      select: {
        plan: true,
        dailyChecks: true,
        dailyChecksLimit: true,
        lastCheckReset: true,
      },
    });

    if (!user) {
      return res.status(404).json({ error: 'Usuário não encontrado' });
    }

    // Check if reset is needed
    const today = new Date();
    today.setHours(0, 0, 0, 0);

    let checksUsed = user.dailyChecks;
    if (user.lastCheckReset < today) {
      checksUsed = 0;
    }

    const checksRemaining = Math.max(0, user.dailyChecksLimit - checksUsed);
    const usagePercentage = Math.round(
      (checksUsed / user.dailyChecksLimit) * 100
    );

    res.json({
      plan: user.plan,
      checksUsed,
      checksLimit: user.dailyChecksLimit,
      checksRemaining,
      usagePercentage,
      resetsAt: new Date(today.getTime() + 24 * 60 * 60 * 1000).toISOString(),
    });
  } catch (error) {
    next(error);
  }
});

export default router;
