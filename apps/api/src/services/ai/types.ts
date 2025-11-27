// ===========================================
// AI PROVIDER TYPES
// ===========================================

export interface AIProvider {
  name: string;

  /**
   * Check if the provider is available and ready
   */
  isAvailable(): Promise<boolean>;

  /**
   * Generate a completion for grammar checking
   */
  complete(prompt: string, options?: CompletionOptions): Promise<string>;

  /**
   * Generate a streaming completion
   */
  stream?(
    prompt: string,
    options?: CompletionOptions
  ): AsyncGenerator<string, void, unknown>;
}

export interface CompletionOptions {
  temperature?: number;
  maxTokens?: number;
  topP?: number;
  stopSequences?: string[];
  systemPrompt?: string;
}

export interface GrammarCorrection {
  originalText: string;
  context?: string;
  startOffset: number;
  endOffset: number;
  type: CorrectionType;
  severity: CorrectionSeverity;
  suggestion: string;
  explanation?: string;
  rule?: string;
}

export type CorrectionType =
  | 'GRAMMAR'
  | 'SPELLING'
  | 'PUNCTUATION'
  | 'STYLE'
  | 'TONE'
  | 'CLARITY'
  | 'CONCISENESS';

export type CorrectionSeverity = 'ERROR' | 'WARNING' | 'SUGGESTION' | 'INFO';

export interface GrammarCheckResult {
  corrections: GrammarCorrection[];
  stats: {
    wordCount: number;
    charCount: number;
    sentenceCount: number;
    readabilityScore: number;
  };
  processedAt: string;
}

export interface ToneAdjustResult {
  original: string;
  adjusted: string;
  targetTone: string;
  changes: {
    original: string;
    adjusted: string;
    reason: string;
  }[];
}

export interface RewriteResult {
  original: string;
  rewritten: string;
  style: string;
  improvements: string[];
}

export type Language = 'PT_BR' | 'EN_US' | 'EN_GB' | 'ES_ES' | 'ES_MX';

export type ToneType =
  | 'FORMAL'
  | 'INFORMAL'
  | 'CONFIDENT'
  | 'NEUTRAL'
  | 'FRIENDLY'
  | 'PROFESSIONAL'
  | 'DIRECT'
  | 'DIPLOMATIC';

export interface GrammarCheckOptions {
  enableGrammar?: boolean;
  enableSpelling?: boolean;
  enablePunctuation?: boolean;
  enableStyle?: boolean;
  enableTone?: boolean;
  enableClarity?: boolean;
  targetTone?: ToneType;
}
