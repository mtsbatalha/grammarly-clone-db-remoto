import { Router } from 'express';
import { z } from 'zod';
import { prisma } from '../config/database.js';
import { cache, cacheKeys } from '../config/redis.js';
import { ApiError } from '../utils/ApiError.js';
import { authenticate } from '../middleware/auth.js';

const router = Router();

router.use(authenticate);

// Schemas
const createDocumentSchema = z.object({
  title: z.string().max(255).optional(),
  content: z.string(),
  language: z.enum(['PT_BR', 'EN_US', 'EN_GB']).optional(),
});

const updateDocumentSchema = z.object({
  title: z.string().max(255).optional(),
  content: z.string().optional(),
  language: z.enum(['PT_BR', 'EN_US', 'EN_GB']).optional(),
});

const listQuerySchema = z.object({
  page: z.coerce.number().min(1).default(1),
  limit: z.coerce.number().min(1).max(100).default(20),
  search: z.string().optional(),
  orderBy: z.enum(['createdAt', 'updatedAt', 'title']).default('updatedAt'),
  order: z.enum(['asc', 'desc']).default('desc'),
});

// Helper to count words and chars
function countText(content: string) {
  const text = content.trim();
  const words = text ? text.split(/\s+/).length : 0;
  const chars = text.length;
  return { wordCount: words, charCount: chars };
}

// GET /api/v1/documents
router.get('/', async (req, res, next) => {
  try {
    const query = listQuerySchema.parse(req.query);
    const skip = (query.page - 1) * query.limit;

    const where = {
      userId: req.user!.id,
      ...(query.search && {
        OR: [
          { title: { contains: query.search, mode: 'insensitive' as const } },
          { content: { contains: query.search, mode: 'insensitive' as const } },
        ],
      }),
    };

    const [documents, total] = await Promise.all([
      prisma.document.findMany({
        where,
        select: {
          id: true,
          title: true,
          language: true,
          wordCount: true,
          charCount: true,
          createdAt: true,
          updatedAt: true,
          _count: {
            select: { corrections: true },
          },
        },
        orderBy: { [query.orderBy]: query.order },
        skip,
        take: query.limit,
      }),
      prisma.document.count({ where }),
    ]);

    res.json({
      documents,
      pagination: {
        page: query.page,
        limit: query.limit,
        total,
        totalPages: Math.ceil(total / query.limit),
      },
    });
  } catch (error) {
    next(error);
  }
});

// GET /api/v1/documents/:id
router.get('/:id', async (req, res, next) => {
  try {
    const { id } = req.params;

    // Check cache first
    const cached = await cache.get(cacheKeys.document(id));

    if (cached) {
      return res.json({ document: cached });
    }

    const document = await prisma.document.findFirst({
      where: {
        id,
        userId: req.user!.id,
      },
      include: {
        corrections: {
          where: { isIgnored: false },
          orderBy: { startOffset: 'asc' },
        },
        revisions: {
          orderBy: { createdAt: 'desc' },
          take: 10,
        },
      },
    });

    if (!document) {
      throw new ApiError(404, 'Documento não encontrado');
    }

    await cache.set(cacheKeys.document(id), document, 300);

    res.json({ document });
  } catch (error) {
    next(error);
  }
});

// POST /api/v1/documents
router.post('/', async (req, res, next) => {
  try {
    const body = createDocumentSchema.parse(req.body);
    const { wordCount, charCount } = countText(body.content);

    const document = await prisma.document.create({
      data: {
        userId: req.user!.id,
        title: body.title || 'Sem título',
        content: body.content,
        language: body.language || 'PT_BR',
        wordCount,
        charCount,
      },
    });

    // Update statistics
    await prisma.userStatistics.upsert({
      where: { userId: req.user!.id },
      update: {
        totalDocuments: { increment: 1 },
      },
      create: {
        userId: req.user!.id,
        totalDocuments: 1,
      },
    });

    res.status(201).json({
      message: 'Documento criado com sucesso',
      document,
    });
  } catch (error) {
    next(error);
  }
});

// PATCH /api/v1/documents/:id
router.patch('/:id', async (req, res, next) => {
  try {
    const { id } = req.params;
    const body = updateDocumentSchema.parse(req.body);

    // Verify ownership
    const existing = await prisma.document.findFirst({
      where: { id, userId: req.user!.id },
    });

    if (!existing) {
      throw new ApiError(404, 'Documento não encontrado');
    }

    // Calculate new counts if content changed
    const updates: Record<string, unknown> = { ...body };
    if (body.content) {
      const { wordCount, charCount } = countText(body.content);
      updates.wordCount = wordCount;
      updates.charCount = charCount;

      // Save revision
      await prisma.revision.create({
        data: {
          documentId: id,
          content: existing.content,
          wordCount: existing.wordCount,
          charCount: existing.charCount,
        },
      });
    }

    const document = await prisma.document.update({
      where: { id },
      data: updates,
    });

    // Clear cache
    await cache.del(cacheKeys.document(id));

    res.json({
      message: 'Documento atualizado com sucesso',
      document,
    });
  } catch (error) {
    next(error);
  }
});

// DELETE /api/v1/documents/:id
router.delete('/:id', async (req, res, next) => {
  try {
    const { id } = req.params;

    const document = await prisma.document.findFirst({
      where: { id, userId: req.user!.id },
    });

    if (!document) {
      throw new ApiError(404, 'Documento não encontrado');
    }

    await prisma.document.delete({ where: { id } });

    // Update statistics
    await prisma.userStatistics.update({
      where: { userId: req.user!.id },
      data: {
        totalDocuments: { decrement: 1 },
      },
    });

    // Clear cache
    await cache.del(cacheKeys.document(id));

    res.json({ message: 'Documento excluído com sucesso' });
  } catch (error) {
    next(error);
  }
});

// GET /api/v1/documents/:id/revisions
router.get('/:id/revisions', async (req, res, next) => {
  try {
    const { id } = req.params;
    const { page = 1, limit = 20 } = req.query;

    const document = await prisma.document.findFirst({
      where: { id, userId: req.user!.id },
    });

    if (!document) {
      throw new ApiError(404, 'Documento não encontrado');
    }

    const skip = (Number(page) - 1) * Number(limit);

    const [revisions, total] = await Promise.all([
      prisma.revision.findMany({
        where: { documentId: id },
        orderBy: { createdAt: 'desc' },
        skip,
        take: Number(limit),
      }),
      prisma.revision.count({ where: { documentId: id } }),
    ]);

    res.json({
      revisions,
      pagination: {
        page: Number(page),
        limit: Number(limit),
        total,
        totalPages: Math.ceil(total / Number(limit)),
      },
    });
  } catch (error) {
    next(error);
  }
});

// POST /api/v1/documents/:id/restore/:revisionId
router.post('/:id/restore/:revisionId', async (req, res, next) => {
  try {
    const { id, revisionId } = req.params;

    const document = await prisma.document.findFirst({
      where: { id, userId: req.user!.id },
    });

    if (!document) {
      throw new ApiError(404, 'Documento não encontrado');
    }

    const revision = await prisma.revision.findFirst({
      where: { id: revisionId, documentId: id },
    });

    if (!revision) {
      throw new ApiError(404, 'Revisão não encontrada');
    }

    // Save current state as revision
    await prisma.revision.create({
      data: {
        documentId: id,
        content: document.content,
        wordCount: document.wordCount,
        charCount: document.charCount,
      },
    });

    // Restore revision
    const restored = await prisma.document.update({
      where: { id },
      data: {
        content: revision.content,
        wordCount: revision.wordCount,
        charCount: revision.charCount,
      },
    });

    // Clear cache
    await cache.del(cacheKeys.document(id));

    res.json({
      message: 'Documento restaurado com sucesso',
      document: restored,
    });
  } catch (error) {
    next(error);
  }
});

export default router;
