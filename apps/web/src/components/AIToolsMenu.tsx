import { useState } from 'react';
import {
  Sparkles,
  Minimize2,
  Maximize2,
  Languages,
  Wand2,
  X,
  Check,
  RefreshCw,
  ChevronRight,
  MessageSquare,
} from 'lucide-react';
import { grammarApi } from '../lib/api';

interface AIToolsMenuProps {
  selectedText: string;
  position: { x: number; y: number };
  language: string;
  onReplace: (newText: string) => void;
  onClose: () => void;
}

type RewriteStyle = 'better' | 'simplified' | 'shorter' | 'longer';
type ToneType = 'FORMAL' | 'INFORMAL' | 'CONFIDENT' | 'NEUTRAL' | 'FRIENDLY' | 'PROFESSIONAL' | 'DIRECT' | 'DIPLOMATIC';

interface AIOption {
  id: RewriteStyle | 'translate' | 'tone';
  label: string;
  icon: React.ReactNode;
  description: string;
}

const aiOptions: AIOption[] = [
  {
    id: 'better',
    label: 'Melhorar',
    icon: <Sparkles className="h-4 w-4" />,
    description: 'Melhora a clareza e elegância',
  },
  {
    id: 'simplified',
    label: 'Simplificar',
    icon: <Wand2 className="h-4 w-4" />,
    description: 'Torna mais fácil de entender',
  },
  {
    id: 'shorter',
    label: 'Encurtar',
    icon: <Minimize2 className="h-4 w-4" />,
    description: 'Reduz sem perder o sentido',
  },
  {
    id: 'longer',
    label: 'Expandir',
    icon: <Maximize2 className="h-4 w-4" />,
    description: 'Adiciona mais detalhes',
  },
  {
    id: 'tone',
    label: 'Ajustar Tom',
    icon: <MessageSquare className="h-4 w-4" />,
    description: 'Muda o tom da mensagem',
  },
  {
    id: 'translate',
    label: 'Traduzir',
    icon: <Languages className="h-4 w-4" />,
    description: 'Traduz para outro idioma',
  },
];

const toneOptions = [
  { code: 'FORMAL' as ToneType, label: 'Formal', emoji: '👔', description: 'Profissional e respeitoso' },
  { code: 'INFORMAL' as ToneType, label: 'Informal', emoji: '😊', description: 'Casual e descontraído' },
  { code: 'CONFIDENT' as ToneType, label: 'Confiante', emoji: '💪', description: 'Assertivo e seguro' },
  { code: 'FRIENDLY' as ToneType, label: 'Amigável', emoji: '🤝', description: 'Caloroso e acolhedor' },
  { code: 'PROFESSIONAL' as ToneType, label: 'Profissional', emoji: '💼', description: 'Corporativo e sério' },
  { code: 'DIRECT' as ToneType, label: 'Direto', emoji: '🎯', description: 'Objetivo e sem rodeios' },
  { code: 'DIPLOMATIC' as ToneType, label: 'Diplomático', emoji: '🕊️', description: 'Cuidadoso e ponderado' },
];

const targetLanguages = [
  { code: 'PT_BR', label: 'Português (BR)', flag: '🇧🇷' },
  { code: 'EN_US', label: 'English (US)', flag: '🇺🇸' },
  { code: 'EN_GB', label: 'English (UK)', flag: '🇬🇧' },
  { code: 'ES_ES', label: 'Español (ES)', flag: '🇪🇸' },
  { code: 'ES_MX', label: 'Español (MX)', flag: '🇲🇽' },
];

export default function AIToolsMenu({
  selectedText,
  position,
  language,
  onReplace,
  onClose,
}: AIToolsMenuProps) {
  const [isLoading, setIsLoading] = useState(false);
  const [suggestion, setSuggestion] = useState<string | null>(null);
  const [showTranslateMenu, setShowTranslateMenu] = useState(false);
  const [showToneMenu, setShowToneMenu] = useState(false);
  const [activeOption, setActiveOption] = useState<string | null>(null);

  const handleRewrite = async (style: RewriteStyle) => {
    setIsLoading(true);
    setActiveOption(style);
    setSuggestion(null);
    setShowToneMenu(false);
    setShowTranslateMenu(false);

    try {
      const response = await grammarApi.rewrite(selectedText, style, language);
      setSuggestion(response.data.rewritten);
    } catch (error) {
      console.error('Rewrite failed:', error);
      setSuggestion(null);
    } finally {
      setIsLoading(false);
    }
  };

  const handleToneAdjust = async (targetTone: ToneType) => {
    setIsLoading(true);
    setActiveOption('tone');
    setShowToneMenu(false);
    setSuggestion(null);

    try {
      const response = await grammarApi.adjustTone(selectedText, targetTone, language);
      setSuggestion(response.data.adjusted);
    } catch (error) {
      console.error('Tone adjustment failed:', error);
      setSuggestion(null);
    } finally {
      setIsLoading(false);
    }
  };

  const handleTranslate = async (targetLanguage: string) => {
    setIsLoading(true);
    setActiveOption('translate');
    setShowTranslateMenu(false);
    setShowToneMenu(false);
    setSuggestion(null);

    try {
      const response = await grammarApi.translate(selectedText, targetLanguage);
      setSuggestion(response.data.translated);
    } catch (error) {
      console.error('Translation failed:', error);
      setSuggestion(null);
    } finally {
      setIsLoading(false);
    }
  };

  const handleAccept = () => {
    if (suggestion) {
      onReplace(suggestion);
    }
    onClose();
  };

  const handleDiscard = () => {
    setSuggestion(null);
    setActiveOption(null);
  };

  // Calculate position to keep menu in viewport
  const menuStyle = {
    left: Math.min(position.x, window.innerWidth - 320),
    top: position.y + 10,
  };

  return (
    <div
      className="fixed z-50 w-72 rounded-xl border border-gray-200 bg-white shadow-2xl dark:border-gray-700 dark:bg-gray-800"
      style={menuStyle}
    >
      {/* Header */}
      <div className="flex items-center justify-between border-b border-gray-100 px-3 py-2 dark:border-gray-700">
        <div className="flex items-center gap-2">
          <div className="flex h-6 w-6 items-center justify-center rounded-md bg-gradient-to-br from-purple-500 to-indigo-600">
            <Sparkles className="h-3.5 w-3.5 text-white" />
          </div>
          <span className="text-sm font-semibold text-gray-900 dark:text-white">
            Assistente IA
          </span>
        </div>
        <button
          onClick={onClose}
          className="rounded-md p-1 text-gray-400 hover:bg-gray-100 hover:text-gray-600 dark:hover:bg-gray-700"
        >
          <X className="h-4 w-4" />
        </button>
      </div>

      {/* Suggestion Preview */}
      {(suggestion || isLoading) && (
        <div className="border-b border-gray-100 p-3 dark:border-gray-700">
          {isLoading ? (
            <div className="flex items-center gap-2 text-sm text-gray-500">
              <RefreshCw className="h-4 w-4 animate-spin" />
              <span>Processando...</span>
            </div>
          ) : (
            <>
              <p className="mb-3 text-sm text-gray-700 dark:text-gray-300">
                {suggestion}
              </p>
              <div className="flex gap-2">
                <button
                  onClick={handleDiscard}
                  className="flex flex-1 items-center justify-center gap-1.5 rounded-lg border border-gray-200 px-3 py-1.5 text-sm font-medium text-gray-600 transition-colors hover:bg-gray-50 dark:border-gray-600 dark:text-gray-400 dark:hover:bg-gray-700"
                >
                  <X className="h-3.5 w-3.5" />
                  Descartar
                </button>
                <button
                  onClick={handleAccept}
                  className="flex flex-1 items-center justify-center gap-1.5 rounded-lg bg-purple-600 px-3 py-1.5 text-sm font-medium text-white transition-colors hover:bg-purple-700"
                >
                  <Check className="h-3.5 w-3.5" />
                  Substituir
                </button>
              </div>
            </>
          )}
        </div>
      )}

      {/* Options List */}
      <div className="p-2">
        {aiOptions.map((option) => (
          <div key={option.id} className="relative">
            {option.id === 'translate' || option.id === 'tone' ? (
              <button
                onClick={() => {
                  if (option.id === 'translate') {
                    setShowTranslateMenu(!showTranslateMenu);
                    setShowToneMenu(false);
                  } else {
                    setShowToneMenu(!showToneMenu);
                    setShowTranslateMenu(false);
                  }
                }}
                disabled={isLoading}
                className={`flex w-full items-center justify-between rounded-lg px-3 py-2 text-left transition-colors ${
                  activeOption === option.id
                    ? 'bg-purple-50 text-purple-700 dark:bg-purple-900/30 dark:text-purple-300'
                    : 'text-gray-700 hover:bg-gray-50 dark:text-gray-300 dark:hover:bg-gray-700/50'
                } disabled:cursor-not-allowed disabled:opacity-50`}
              >
                <div className="flex items-center gap-3">
                  <span className="text-purple-500">{option.icon}</span>
                  <div>
                    <p className="text-sm font-medium">{option.label}</p>
                    <p className="text-xs text-gray-500 dark:text-gray-400">
                      {option.description}
                    </p>
                  </div>
                </div>
                <ChevronRight className="h-4 w-4 text-gray-400" />
              </button>
            ) : (
              <button
                onClick={() => handleRewrite(option.id as RewriteStyle)}
                disabled={isLoading}
                className={`flex w-full items-center gap-3 rounded-lg px-3 py-2 text-left transition-colors ${
                  activeOption === option.id
                    ? 'bg-purple-50 text-purple-700 dark:bg-purple-900/30 dark:text-purple-300'
                    : 'text-gray-700 hover:bg-gray-50 dark:text-gray-300 dark:hover:bg-gray-700/50'
                } disabled:cursor-not-allowed disabled:opacity-50`}
              >
                <span className="text-purple-500">{option.icon}</span>
                <div>
                  <p className="text-sm font-medium">{option.label}</p>
                  <p className="text-xs text-gray-500 dark:text-gray-400">
                    {option.description}
                  </p>
                </div>
              </button>
            )}

            {/* Tone submenu */}
            {option.id === 'tone' && showToneMenu && (
              <div className="absolute left-full top-0 ml-1 w-56 rounded-lg border border-gray-200 bg-white p-1 shadow-lg dark:border-gray-700 dark:bg-gray-800">
                {toneOptions.map((tone) => (
                  <button
                    key={tone.code}
                    onClick={() => handleToneAdjust(tone.code)}
                    className="flex w-full items-center gap-2 rounded-md px-3 py-2 text-sm text-gray-700 hover:bg-gray-50 dark:text-gray-300 dark:hover:bg-gray-700"
                  >
                    <span>{tone.emoji}</span>
                    <div>
                      <p className="font-medium">{tone.label}</p>
                      <p className="text-xs text-gray-500">{tone.description}</p>
                    </div>
                  </button>
                ))}
              </div>
            )}

            {/* Translate submenu */}
            {option.id === 'translate' && showTranslateMenu && (
              <div className="absolute left-full top-0 ml-1 w-48 rounded-lg border border-gray-200 bg-white p-1 shadow-lg dark:border-gray-700 dark:bg-gray-800">
                {targetLanguages.map((lang) => (
                    <button
                      key={lang.code}
                      onClick={() => handleTranslate(lang.code)}
                      className="flex w-full items-center gap-2 rounded-md px-3 py-2 text-sm text-gray-700 hover:bg-gray-50 dark:text-gray-300 dark:hover:bg-gray-700"
                    >
                      <span>{lang.flag}</span>
                      <span>{lang.label}</span>
                    </button>
                  ))}
              </div>
            )}
          </div>
        ))}
      </div>
    </div>
  );
}
