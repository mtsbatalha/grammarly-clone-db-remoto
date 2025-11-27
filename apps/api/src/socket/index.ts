import { Server, Socket } from 'socket.io';
import jwt from 'jsonwebtoken';
import { env } from '../config/env.js';
import { logger } from '../config/logger.js';
import { AIProviderFactory } from '../services/ai/AIProviderFactory.js';
import { GrammarService } from '../services/GrammarService.js';

interface AuthenticatedSocket extends Socket {
  userId?: string;
  userPlan?: string;
}

export function setupSocketHandlers(io: Server): void {
  // Authentication middleware
  io.use((socket: AuthenticatedSocket, next) => {
    const token = socket.handshake.auth.token;

    if (!token) {
      // Allow anonymous connections with limited features
      return next();
    }

    try {
      const payload = jwt.verify(token, env.JWT_SECRET) as {
        userId: string;
        plan: string;
      };
      socket.userId = payload.userId;
      socket.userPlan = payload.plan;
      next();
    } catch {
      next(new Error('Invalid token'));
    }
  });

  io.on('connection', (socket: AuthenticatedSocket) => {
    logger.info(
      `Client connected: ${socket.id} (user: ${socket.userId || 'anonymous'})`
    );

    // Join user-specific room if authenticated
    if (socket.userId) {
      socket.join(`user:${socket.userId}`);
    }

    // Real-time grammar checking
    socket.on('grammar:check', async (data, callback) => {
      try {
        const { text, language, options } = data;

        if (!text || typeof text !== 'string') {
          return callback({ error: 'Text is required' });
        }

        // Rate limit for anonymous users
        if (!socket.userId) {
          const key = `socket:${socket.id}:checks`;
          // Simple in-memory rate limiting for sockets
          const checks = (socket.data.checks || 0) + 1;
          socket.data.checks = checks;

          if (checks > 10) {
            return callback({
              error: 'Rate limit exceeded. Please sign in for more checks.',
            });
          }
        }

        const provider = AIProviderFactory.create();
        const grammarService = new GrammarService(provider);

        const result = await grammarService.check(
          text.substring(0, 5000), // Limit text size for real-time
          language || 'PT_BR',
          options
        );

        callback({ success: true, result });
      } catch (error) {
        logger.error('Socket grammar check error:', error);
        callback({
          error: error instanceof Error ? error.message : 'Check failed',
        });
      }
    });

    // Real-time tone adjustment
    socket.on('grammar:tone', async (data, callback) => {
      try {
        if (!socket.userId) {
          return callback({ error: 'Authentication required' });
        }

        const { text, targetTone, language } = data;

        if (!text || !targetTone) {
          return callback({ error: 'Text and targetTone are required' });
        }

        const provider = AIProviderFactory.create();
        const grammarService = new GrammarService(provider);

        const result = await grammarService.adjustTone(
          text.substring(0, 2000),
          targetTone,
          language || 'PT_BR'
        );

        callback({ success: true, result });
      } catch (error) {
        logger.error('Socket tone adjustment error:', error);
        callback({
          error: error instanceof Error ? error.message : 'Adjustment failed',
        });
      }
    });

    // Streaming grammar check
    socket.on('grammar:stream', async (data) => {
      try {
        const { text, language } = data;

        if (!text) {
          socket.emit('grammar:stream:error', { error: 'Text is required' });
          return;
        }

        const provider = AIProviderFactory.create();

        if (!provider.stream) {
          socket.emit('grammar:stream:error', {
            error: 'Streaming not supported',
          });
          return;
        }

        socket.emit('grammar:stream:start');

        const systemPrompt = `Você é um corretor gramatical. Analise o texto e forneça correções em tempo real.`;
        const userPrompt = `Analise: "${text}"`;

        for await (const chunk of provider.stream(userPrompt, { systemPrompt })) {
          socket.emit('grammar:stream:chunk', { chunk });
        }

        socket.emit('grammar:stream:end');
      } catch (error) {
        logger.error('Socket stream error:', error);
        socket.emit('grammar:stream:error', {
          error: error instanceof Error ? error.message : 'Stream failed',
        });
      }
    });

    // Document collaboration (for future features)
    socket.on('document:join', (documentId) => {
      if (socket.userId) {
        socket.join(`document:${documentId}`);
        logger.info(`User ${socket.userId} joined document ${documentId}`);
      }
    });

    socket.on('document:leave', (documentId) => {
      socket.leave(`document:${documentId}`);
    });

    socket.on('document:update', (data) => {
      const { documentId, content, cursorPosition } = data;
      socket.to(`document:${documentId}`).emit('document:updated', {
        userId: socket.userId,
        content,
        cursorPosition,
      });
    });

    socket.on('disconnect', () => {
      logger.info(`Client disconnected: ${socket.id}`);
    });
  });
}
