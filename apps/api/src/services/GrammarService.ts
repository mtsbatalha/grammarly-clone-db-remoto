import {
  AIProvider,
  GrammarCorrection,
  GrammarCheckResult,
  GrammarCheckOptions,
  ToneAdjustResult,
  RewriteResult,
  Language,
  ToneType,
} from './ai/types.js';
import { logger } from '../config/logger.js';

/**
 * Grammar Service
 *
 * Handles all grammar checking, tone adjustment, and rewriting operations
 * using the configured AI provider.
 */
export class GrammarService {
  private provider: AIProvider;

  constructor(provider: AIProvider) {
    this.provider = provider;
  }

  /**
   * Perform grammar and style check on text
   */
  async check(
    text: string,
    language: Language = 'PT_BR',
    options?: GrammarCheckOptions
  ): Promise<GrammarCheckResult> {
    const systemPrompt = this.getGrammarSystemPrompt(language, options);
    const userPrompt = this.getGrammarUserPrompt(text, language, options);

    try {
      const response = await this.provider.complete(userPrompt, {
        systemPrompt,
        temperature: 0.2,
        maxTokens: 4096,
      });

      const corrections = this.parseCorrections(response, text);
      const stats = this.calculateStats(text);

      return {
        corrections,
        stats,
        processedAt: new Date().toISOString(),
      };
    } catch (error) {
      logger.error('Grammar check failed:', error);
      throw error;
    }
  }

  /**
   * Adjust the tone of the text
   */
  async adjustTone(
    text: string,
    targetTone: ToneType,
    _language: Language = 'PT_BR'
  ): Promise<ToneAdjustResult> {
    const toneDescriptions: Record<ToneType, string> = {
      FORMAL: 'formal e profissional',
      INFORMAL: 'casual e descontraído',
      CONFIDENT: 'assertivo e seguro',
      NEUTRAL: 'equilibrado e objetivo',
      FRIENDLY: 'caloroso e acolhedor',
      PROFESSIONAL: 'corporativo e sério',
      DIRECT: 'objetivo e sem rodeios',
      DIPLOMATIC: 'cuidadoso e ponderado',
    };

    const lineCount = text.split('\n').length;
    const hasCodeBlocks = text.includes('```') || text.includes('`');
    const hasList = /^[\s]*[-*•]\s/m.test(text) || /^[\s]*\d+\.\s/m.test(text);

    const systemPrompt = `You are a multilingual communication expert.
Your task is to adjust the tone of texts while maintaining the original meaning AND structure.

CRITICAL RULE - NEVER TRANSLATE:
- If the input is in English, your output MUST be in English
- If the input is in Portuguese, your output MUST be in Portuguese
- NEVER change the language of the text

CRITICAL RULE - PRESERVE EXACT STRUCTURE:
- The input has EXACTLY ${lineCount} lines - your output MUST have EXACTLY ${lineCount} lines
- Each line break in the input MUST appear in the exact same position in the output
- Use \\n (escaped newline) in the JSON string for each line break
- Do NOT merge multiple lines into one
- Do NOT split one line into multiple lines
${hasCodeBlocks ? '- Preserve all code blocks exactly as they are' : ''}
${hasList ? '- Preserve all list formatting (bullets, numbers) exactly' : ''}

Respond ONLY with valid JSON.`;

    const userPrompt = `Adjust the tone of the following text to be more ${toneDescriptions[targetTone]}.

STRUCTURE INFO:
- Total lines: ${lineCount}
- Has code blocks: ${hasCodeBlocks}
- Has lists: ${hasList}

ORIGINAL TEXT (between triple backticks):
\`\`\`
${text}
\`\`\`

MANDATORY RULES:
1. KEEP THE SAME LANGUAGE - DO NOT TRANSLATE
2. Output MUST have EXACTLY ${lineCount} lines (same as input)
3. Each line break position must be preserved
4. In the JSON, use \\n for each line break

Respond with JSON:
{
  "adjusted": "text with EXACTLY ${lineCount} lines, using \\n for line breaks",
  "changes": [{"original": "phrase", "adjusted": "phrase", "reason": "reason"}]
}`;

    try {
      const response = await this.provider.complete(userPrompt, {
        systemPrompt,
        temperature: 0.4,
        maxTokens: 2048,
      });

      const parsed = this.parseJSON(response) as {
        adjusted?: string;
        changes?: { original: string; adjusted: string; reason: string }[];
      };

      return {
        original: text,
        adjusted: parsed.adjusted || text,
        targetTone,
        changes: parsed.changes || [],
      };
    } catch (error) {
      logger.error('Tone adjustment failed:', error);
      throw error;
    }
  }

  /**
   * Rewrite text in a specific style
   */
  async rewrite(
    text: string,
    style: 'concise' | 'expanded' | 'simplified' | 'formal' | 'better' | 'shorter' | 'longer',
    _language: Language = 'PT_BR'
  ): Promise<RewriteResult> {
    const styleDescriptions = {
      concise: 'mais conciso e direto, removendo redundâncias',
      expanded: 'mais detalhado e explicativo',
      simplified: 'mais simples e fácil de entender',
      formal: 'mais formal e profissional',
      better: 'melhor escrito, mais claro e elegante, mantendo o significado original',
      shorter: 'mais curto e direto ao ponto, sem perder informações essenciais',
      longer: 'mais elaborado e detalhado, expandindo as ideias apresentadas',
    };

    const lineCount = text.split('\n').length;
    const hasCodeBlocks = text.includes('```') || text.includes('`');
    const hasList = /^[\s]*[-*•]\s/m.test(text) || /^[\s]*\d+\.\s/m.test(text);

    const systemPrompt = `You are a multilingual writing expert.
Your task is to rewrite texts according to the requested style while preserving structure.

CRITICAL RULE - NEVER TRANSLATE:
- If the input is in English, your output MUST be in English
- If the input is in Portuguese, your output MUST be in Portuguese
- NEVER change the language of the text

CRITICAL RULE - PRESERVE EXACT STRUCTURE:
- The input has EXACTLY ${lineCount} lines - your output MUST have EXACTLY ${lineCount} lines
- Each line break in the input MUST appear in the exact same position in the output
- Use \\n (escaped newline) in the JSON string for each line break
- Do NOT merge multiple lines into one
- Do NOT split one line into multiple lines
${hasCodeBlocks ? '- Preserve all code blocks exactly as they are - do not modify code' : ''}
${hasList ? '- Preserve all list formatting (bullets, numbers) exactly' : ''}

Respond ONLY with valid JSON.`;

    const userPrompt = `Rewrite the following text to be ${styleDescriptions[style]}.

STRUCTURE INFO:
- Total lines: ${lineCount}
- Has code blocks: ${hasCodeBlocks}
- Has lists: ${hasList}

ORIGINAL TEXT (between triple backticks):
\`\`\`
${text}
\`\`\`

MANDATORY RULES:
1. KEEP THE SAME LANGUAGE - DO NOT TRANSLATE
2. Output MUST have EXACTLY ${lineCount} lines (same as input)
3. Each line break position must be preserved exactly
4. In the JSON, use \\n for each line break
5. Do NOT modify any code - only improve surrounding text

Respond with JSON:
{
  "rewritten": "text with EXACTLY ${lineCount} lines, using \\n for line breaks",
  "improvements": ["improvement 1", "improvement 2"]
}`;

    try {
      const response = await this.provider.complete(userPrompt, {
        systemPrompt,
        temperature: 0.5,
        maxTokens: 2048,
      });

      const parsed = this.parseJSON(response) as {
        rewritten?: string;
        improvements?: string[];
      };

      return {
        original: text,
        rewritten: parsed.rewritten || text,
        style,
        improvements: parsed.improvements || [],
      };
    } catch (error) {
      logger.error('Rewrite failed:', error);
      throw error;
    }
  }

  /**
   * Translate text to another language
   */
  async translate(
    text: string,
    targetLanguage: Language
  ): Promise<{ original: string; translated: string; targetLanguage: Language }> {
    const langNames: Record<Language, string> = {
      PT_BR: 'português brasileiro',
      EN_US: 'inglês americano',
      EN_GB: 'inglês britânico',
      ES_ES: 'español de España',
      ES_MX: 'español de México',
    };

    const lineCount = text.split('\n').length;
    const hasCodeBlocks = text.includes('```') || text.includes('`');
    const hasList = /^[\s]*[-*•]\s/m.test(text) || /^[\s]*\d+\.\s/m.test(text);

    const systemPrompt = `Você é um tradutor profissional especializado.
Traduza textos de forma natural e fluente, mantendo o tom, estilo E ESTRUTURA original.

REGRA CRÍTICA - PRESERVAR ESTRUTURA EXATA:
- O texto tem EXATAMENTE ${lineCount} linhas - sua saída DEVE ter EXATAMENTE ${lineCount} linhas
- Cada quebra de linha DEVE aparecer na mesma posição
- Use \\n no JSON para cada quebra de linha
- NÃO junte várias linhas em uma
- NÃO divida uma linha em várias
${hasCodeBlocks ? '- Preserve blocos de código exatamente - NÃO traduza código' : ''}
${hasList ? '- Preserve formatação de listas (bullets, números) exatamente' : ''}

Responda APENAS com JSON válido.`;

    const userPrompt = `Traduza o seguinte texto para ${langNames[targetLanguage]}.

INFORMAÇÕES DE ESTRUTURA:
- Total de linhas: ${lineCount}
- Tem blocos de código: ${hasCodeBlocks}
- Tem listas: ${hasList}

TEXTO ORIGINAL (entre crases triplas):
\`\`\`
${text}
\`\`\`

REGRAS OBRIGATÓRIAS:
1. Traduza o conteúdo mantendo o significado original
2. Saída DEVE ter EXATAMENTE ${lineCount} linhas (igual à entrada)
3. Cada posição de quebra de linha deve ser preservada
4. No JSON, use \\n para cada quebra de linha
5. NÃO traduza código - apenas texto ao redor

Responda em JSON:
{
  "translated": "texto com EXATAMENTE ${lineCount} linhas, usando \\n para quebras"
}`;

    try {
      const response = await this.provider.complete(userPrompt, {
        systemPrompt,
        temperature: 0.3,
        maxTokens: 2048,
      });

      const parsed = this.parseJSON(response) as {
        translated?: string;
      };

      return {
        original: text,
        translated: parsed.translated || text,
        targetLanguage,
      };
    } catch (error) {
      logger.error('Translation failed:', error);
      throw error;
    }
  }

  private getGrammarSystemPrompt(
    language: Language,
    options?: GrammarCheckOptions
  ): string {
    const langNames: Record<Language, string> = {
      PT_BR: 'português brasileiro',
      EN_US: 'inglês americano',
      EN_GB: 'inglês britânico',
      ES_ES: 'español de España',
      ES_MX: 'español de México',
    };
    const langName = langNames[language];

    const enabledChecks = [];
    if (options?.enableGrammar !== false) enabledChecks.push('gramática');
    if (options?.enableSpelling !== false) enabledChecks.push('ortografia');
    if (options?.enablePunctuation !== false) enabledChecks.push('pontuação');
    if (options?.enableStyle !== false) enabledChecks.push('estilo');
    if (options?.enableClarity !== false) enabledChecks.push('clareza');
    if (options?.enableTone) enabledChecks.push('tom');

    return `Você é um especialista em ${langName} e correção gramatical.
Analise textos identificando problemas de: ${enabledChecks.join(', ')}.

IMPORTANTE:
- Responda APENAS com JSON válido
- Use o formato EXATO especificado
- Não adicione texto antes ou depois do JSON
- Se não houver erros, retorne um array vazio
- Identifique a posição EXATA do erro no texto (offset em caracteres)`;
  }

  private getGrammarUserPrompt(
    text: string,
    language: Language,
    options?: GrammarCheckOptions
  ): string {
    return `Analise o seguinte texto e identifique TODOS os erros e sugestões de melhoria.

TEXTO:
"${text}"

Responda com um JSON no formato:
{
  "corrections": [
    {
      "originalText": "texto com erro",
      "startOffset": 0,
      "endOffset": 10,
      "type": "GRAMMAR|SPELLING|PUNCTUATION|STYLE|CLARITY|TONE",
      "severity": "ERROR|WARNING|SUGGESTION|INFO",
      "suggestion": "texto corrigido",
      "explanation": "explicação da correção",
      "rule": "identificador da regra (ex: CONCORDANCIA_VERBAL)"
    }
  ]
}

Tipos de correção:
- GRAMMAR: erros gramaticais (concordância, regência, etc)
- SPELLING: erros de ortografia
- PUNCTUATION: erros de pontuação
- STYLE: sugestões de estilo
- CLARITY: problemas de clareza
- TONE: ajustes de tom

Severidade:
- ERROR: erro que deve ser corrigido
- WARNING: problema que provavelmente é um erro
- SUGGESTION: sugestão de melhoria
- INFO: informação útil`;
  }

  private parseCorrections(
    response: string,
    originalText: string
  ): GrammarCorrection[] {
    try {
      const parsed = this.parseJSON(response) as {
        corrections?: Record<string, unknown>[];
      };
      const corrections = parsed.corrections || [];

      return corrections
        .map((c) => {
          // Validate and fix offsets
          let startOffset = Number(c.startOffset) || 0;
          let endOffset = Number(c.endOffset) || startOffset + 1;

          // Try to find the actual position if the AI didn't provide correct offsets
          if (c.originalText && typeof c.originalText === 'string') {
            const foundIndex = originalText.indexOf(c.originalText as string);
            if (foundIndex !== -1) {
              startOffset = foundIndex;
              endOffset = foundIndex + (c.originalText as string).length;
            }
          }

          // Ensure offsets are within bounds
          startOffset = Math.max(0, Math.min(startOffset, originalText.length));
          endOffset = Math.max(startOffset, Math.min(endOffset, originalText.length));

          return {
            originalText: String(c.originalText || ''),
            context: this.getContext(originalText, startOffset, endOffset),
            startOffset,
            endOffset,
            type: this.validateType(String(c.type || 'GRAMMAR')),
            severity: this.validateSeverity(String(c.severity || 'WARNING')),
            suggestion: String(c.suggestion || ''),
            explanation: c.explanation ? String(c.explanation) : undefined,
            rule: c.rule ? String(c.rule) : undefined,
          };
        })
        .filter(
          (c: GrammarCorrection) =>
            c.originalText && c.suggestion && c.originalText !== c.suggestion
        );
    } catch (error) {
      logger.error('Failed to parse corrections:', error);
      return [];
    }
  }

  private parseJSON(response: string): Record<string, unknown> {
    // Try to extract JSON from the response
    const jsonMatch = response.match(/\{[\s\S]*\}/);
    if (jsonMatch) {
      try {
        return JSON.parse(jsonMatch[0]);
      } catch {
        // Try to fix common JSON issues
        const fixed = jsonMatch[0]
          .replace(/,\s*}/g, '}')
          .replace(/,\s*]/g, ']')
          .replace(/'/g, '"');
        return JSON.parse(fixed);
      }
    }
    return {};
  }

  private getContext(text: string, start: number, end: number): string {
    const contextSize = 50;
    const contextStart = Math.max(0, start - contextSize);
    const contextEnd = Math.min(text.length, end + contextSize);
    return text.substring(contextStart, contextEnd);
  }

  private validateType(type: string): GrammarCorrection['type'] {
    const validTypes = [
      'GRAMMAR',
      'SPELLING',
      'PUNCTUATION',
      'STYLE',
      'TONE',
      'CLARITY',
      'CONCISENESS',
    ];
    return validTypes.includes(type)
      ? (type as GrammarCorrection['type'])
      : 'GRAMMAR';
  }

  private validateSeverity(severity: string): GrammarCorrection['severity'] {
    const validSeverities = ['ERROR', 'WARNING', 'SUGGESTION', 'INFO'];
    return validSeverities.includes(severity)
      ? (severity as GrammarCorrection['severity'])
      : 'WARNING';
  }

  private calculateStats(text: string): GrammarCheckResult['stats'] {
    const words = text.trim().split(/\s+/).filter(Boolean);
    const sentences = text.split(/[.!?]+/).filter(Boolean);
    const avgWordsPerSentence =
      sentences.length > 0 ? words.length / sentences.length : 0;

    // Simple readability score (0-100)
    // Lower average words per sentence = more readable
    const readabilityScore = Math.max(
      0,
      Math.min(100, 100 - (avgWordsPerSentence - 10) * 2)
    );

    return {
      wordCount: words.length,
      charCount: text.length,
      sentenceCount: sentences.length,
      readabilityScore: Math.round(readabilityScore),
    };
  }
}
