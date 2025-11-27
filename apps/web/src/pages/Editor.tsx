import { useEffect, useState, useCallback, useRef } from 'react';
import { useParams, useNavigate } from 'react-router-dom';
import { useEditor, EditorContent } from '@tiptap/react';
import StarterKit from '@tiptap/starter-kit';
import Placeholder from '@tiptap/extension-placeholder';
import Underline from '@tiptap/extension-underline';
import {
  Save,
  Check,
  AlertTriangle,
  Lightbulb,
  Info,
  RefreshCw,
  Wand2,
} from 'lucide-react';
import { grammarApi, documentsApi } from '../lib/api';
import AIToolsMenu from '../components/AIToolsMenu';

interface Correction {
  id?: string;
  originalText: string;
  suggestion: string;
  explanation?: string;
  type: string;
  severity: string;
  startOffset: number;
  endOffset: number;
}

interface Stats {
  wordCount: number;
  charCount: number;
  sentenceCount: number;
  readabilityScore: number;
}

interface AIMenuState {
  isOpen: boolean;
  selectedText: string;
  position: { x: number; y: number };
  selectionRange: { from: number; to: number } | null;
}

export default function Editor() {
  const { documentId } = useParams();
  const navigate = useNavigate();
  const editorContainerRef = useRef<HTMLDivElement>(null);

  const [title, setTitle] = useState('Sem título');
  const [language, setLanguage] = useState('PT_BR');
  const [corrections, setCorrections] = useState<Correction[]>([]);
  const [stats, setStats] = useState<Stats | null>(null);
  const [isChecking, setIsChecking] = useState(false);
  const [isSaving, setIsSaving] = useState(false);
  const [lastSaved, setLastSaved] = useState<Date | null>(null);
  const [aiMenu, setAiMenu] = useState<AIMenuState>({
    isOpen: false,
    selectedText: '',
    position: { x: 0, y: 0 },
    selectionRange: null,
  });

  const editor = useEditor({
    extensions: [
      StarterKit,
      Underline,
      Placeholder.configure({
        placeholder: 'Comece a escrever...',
      }),
    ],
    content: '',
    onUpdate: ({ editor }) => {
      // Auto-save after 2 seconds of inactivity
      debouncedSave(editor.getText(), editor.getHTML());
    },
  });

  // Load document if editing existing
  useEffect(() => {
    if (documentId && editor) {
      loadDocument(documentId);
    }
  }, [documentId, editor]);

  const loadDocument = async (id: string) => {
    try {
      const response = await documentsApi.get(id);
      const doc = response.data.document;
      setTitle(doc.title);
      setLanguage(doc.language);
      editor?.commands.setContent(doc.content);
      setCorrections(doc.corrections || []);
    } catch (error) {
      console.error('Failed to load document:', error);
      navigate('/editor');
    }
  };

  const saveDocument = useCallback(
    async (text: string, html: string) => {
      if (!text.trim()) return;

      setIsSaving(true);
      try {
        if (documentId) {
          await documentsApi.update(documentId, { title, content: html });
        } else {
          const response = await documentsApi.create({
            title,
            content: html,
            language,
          });
          navigate(`/editor/${response.data.document.id}`, { replace: true });
        }
        setLastSaved(new Date());
      } catch (error) {
        console.error('Failed to save:', error);
      } finally {
        setIsSaving(false);
      }
    },
    [documentId, title, language, navigate]
  );

  // Debounced save
  const debouncedSave = useCallback(
    debounce((text: string, html: string) => {
      saveDocument(text, html);
    }, 2000),
    [saveDocument]
  );

  const checkGrammar = async () => {
    if (!editor) return;

    const text = editor.getText();
    if (!text.trim()) return;

    setIsChecking(true);
    try {
      const response = await grammarApi.check(text, language);
      setCorrections(response.data.corrections || []);
      setStats(response.data.stats);
    } catch (error) {
      console.error('Grammar check failed:', error);
    } finally {
      setIsChecking(false);
    }
  };

  const acceptCorrection = (correction: Correction) => {
    if (!editor) return;

    const text = editor.getText();
    const newText =
      text.substring(0, correction.startOffset) +
      correction.suggestion +
      text.substring(correction.endOffset);

    editor.commands.setContent(`<p>${newText}</p>`);

    // Remove from list
    setCorrections(corrections.filter((c) => c !== correction));
  };

  const ignoreCorrection = (correction: Correction) => {
    setCorrections(corrections.filter((c) => c !== correction));
  };

  // Handle text selection for AI menu
  const handleTextSelection = useCallback(() => {
    if (!editor) return;

    // Don't update selection if AI menu is already open (prevents losing range when clicking menu)
    if (aiMenu.isOpen) return;

    const { from, to } = editor.state.selection;
    const selectedText = editor.state.doc.textBetween(from, to, ' ');

    if (selectedText && selectedText.trim().length > 2) {
      // Get selection coordinates
      const { view } = editor;
      const coords = view.coordsAtPos(from);

      setAiMenu({
        isOpen: true,
        selectedText: selectedText.trim(),
        position: { x: coords.left, y: coords.bottom },
        selectionRange: { from, to },
      });
    }
  }, [editor, aiMenu.isOpen]);

  // Handle AI suggestion replacement
  const handleAIReplace = useCallback(
    (newText: string) => {
      if (!editor || !aiMenu.selectionRange) return;

      const { from, to } = aiMenu.selectionRange;

      editor
        .chain()
        .focus()
        .deleteRange({ from, to })
        .insertContentAt(from, newText)
        .run();

      setAiMenu((prev) => ({ ...prev, isOpen: false }));
    },
    [editor, aiMenu.selectionRange]
  );

  // Close AI menu
  const closeAIMenu = useCallback(() => {
    setAiMenu((prev) => ({ ...prev, isOpen: false }));
  }, []);

  // Listen for selection changes
  useEffect(() => {
    if (!editor) return;

    const handleSelectionUpdate = () => {
      // Delay to ensure selection is complete
      setTimeout(handleTextSelection, 100);
    };

    editor.on('selectionUpdate', handleSelectionUpdate);

    return () => {
      editor.off('selectionUpdate', handleSelectionUpdate);
    };
  }, [editor, handleTextSelection]);

  // Close AI menu on click outside
  useEffect(() => {
    const handleClickOutside = (e: MouseEvent) => {
      if (aiMenu.isOpen && editorContainerRef.current) {
        const target = e.target as Node;
        const aiMenuElement = document.querySelector('[data-ai-menu]');
        if (aiMenuElement && !aiMenuElement.contains(target)) {
          // Don't close if clicking inside editor (might be selecting more text)
          if (!editorContainerRef.current.contains(target)) {
            closeAIMenu();
          }
        }
      }
    };

    document.addEventListener('mousedown', handleClickOutside);
    return () => document.removeEventListener('mousedown', handleClickOutside);
  }, [aiMenu.isOpen, closeAIMenu]);

  const getSeverityIcon = (severity: string) => {
    switch (severity) {
      case 'ERROR':
        return <AlertTriangle className="h-4 w-4 text-red-500" />;
      case 'WARNING':
        return <AlertTriangle className="h-4 w-4 text-amber-500" />;
      case 'SUGGESTION':
        return <Lightbulb className="h-4 w-4 text-blue-500" />;
      default:
        return <Info className="h-4 w-4 text-gray-500" />;
    }
  };

  const getSeverityColor = (severity: string) => {
    switch (severity) {
      case 'ERROR':
        return 'border-l-red-500 bg-red-50 dark:bg-red-900/20';
      case 'WARNING':
        return 'border-l-amber-500 bg-amber-50 dark:bg-amber-900/20';
      case 'SUGGESTION':
        return 'border-l-blue-500 bg-blue-50 dark:bg-blue-900/20';
      default:
        return 'border-l-gray-500 bg-gray-50 dark:bg-gray-800';
    }
  };

  return (
    <div className="flex h-full gap-6">
      {/* Editor Panel */}
      <div className="flex flex-1 flex-col">
        {/* Toolbar */}
        <div className="mb-4 flex items-center justify-between">
          <input
            type="text"
            value={title}
            onChange={(e) => setTitle(e.target.value)}
            className="border-0 bg-transparent text-xl font-semibold text-gray-900 outline-none dark:text-white"
            placeholder="Título do documento"
          />

          <div className="flex items-center gap-3">
            <select
              value={language}
              onChange={(e) => setLanguage(e.target.value)}
              className="rounded-lg border border-gray-300 bg-white px-3 py-2 text-sm dark:border-gray-600 dark:bg-gray-800"
            >
              <option value="PT_BR">Português (BR)</option>
              <option value="EN_US">English (US)</option>
              <option value="EN_GB">English (UK)</option>
              <option value="ES_ES">Español (ES)</option>
              <option value="ES_MX">Español (MX)</option>
            </select>

            <button
              onClick={checkGrammar}
              disabled={isChecking}
              className="btn btn-primary btn-md"
            >
              {isChecking ? (
                <RefreshCw className="h-4 w-4 animate-spin" />
              ) : (
                <Wand2 className="h-4 w-4" />
              )}
              Verificar
            </button>

            <button
              onClick={() => editor && saveDocument(editor.getText(), editor.getHTML())}
              disabled={isSaving}
              className="btn btn-secondary btn-md"
            >
              {isSaving ? (
                <RefreshCw className="h-4 w-4 animate-spin" />
              ) : (
                <Save className="h-4 w-4" />
              )}
              Salvar
            </button>
          </div>
        </div>

        {/* Editor */}
        <div className="card flex-1" ref={editorContainerRef}>
          <EditorContent
            editor={editor}
            className="prose prose-lg max-w-none dark:prose-invert"
          />
        </div>

        {/* AI Tools Menu */}
        {aiMenu.isOpen && (
          <div data-ai-menu>
            <AIToolsMenu
              selectedText={aiMenu.selectedText}
              position={aiMenu.position}
              language={language}
              onReplace={handleAIReplace}
              onClose={closeAIMenu}
            />
          </div>
        )}

        {/* Stats Bar */}
        {stats && (
          <div className="mt-4 flex items-center gap-6 text-sm text-gray-500">
            <span>{stats.wordCount} palavras</span>
            <span>{stats.charCount} caracteres</span>
            <span>{stats.sentenceCount} sentenças</span>
            <span>Legibilidade: {stats.readabilityScore}%</span>
            {lastSaved && (
              <span className="ml-auto">
                Salvo às {lastSaved.toLocaleTimeString('pt-BR', { hour: '2-digit', minute: '2-digit' })}
              </span>
            )}
          </div>
        )}
      </div>

      {/* Corrections Panel */}
      <div className="w-80 flex-shrink-0">
        <div className="card sticky top-0 max-h-[calc(100vh-150px)] overflow-auto">
          <h2 className="mb-4 flex items-center justify-between text-lg font-semibold text-gray-900 dark:text-white">
            Correções
            {corrections.length > 0 && (
              <span className="rounded-full bg-primary-100 px-2 py-0.5 text-sm font-normal text-primary-700">
                {corrections.length}
              </span>
            )}
          </h2>

          {corrections.length === 0 ? (
            <div className="flex flex-col items-center justify-center py-8 text-center">
              <Check className="mb-2 h-12 w-12 text-green-500" />
              <p className="font-medium text-gray-900 dark:text-white">
                Tudo certo!
              </p>
              <p className="text-sm text-gray-500">
                Nenhum problema encontrado
              </p>
            </div>
          ) : (
            <div className="space-y-3">
              {corrections.map((correction, index) => (
                <div
                  key={index}
                  className={`rounded-lg border-l-4 p-3 ${getSeverityColor(correction.severity)}`}
                >
                  <div className="mb-2 flex items-center gap-2">
                    {getSeverityIcon(correction.severity)}
                    <span className="text-xs font-medium uppercase text-gray-500">
                      {correction.type}
                    </span>
                  </div>

                  <p className="text-sm text-red-600 line-through">
                    {correction.originalText}
                  </p>
                  <p className="font-medium text-green-600">
                    {correction.suggestion}
                  </p>

                  {correction.explanation && (
                    <p className="mt-1 text-xs text-gray-500">
                      {correction.explanation}
                    </p>
                  )}

                  <div className="mt-2 flex gap-2">
                    <button
                      onClick={() => acceptCorrection(correction)}
                      className="btn btn-primary btn-sm flex-1"
                    >
                      Aceitar
                    </button>
                    <button
                      onClick={() => ignoreCorrection(correction)}
                      className="btn btn-secondary btn-sm flex-1"
                    >
                      Ignorar
                    </button>
                  </div>
                </div>
              ))}
            </div>
          )}
        </div>
      </div>
    </div>
  );
}

// Debounce utility
function debounce<T extends (...args: Parameters<T>) => void>(
  func: T,
  wait: number
): (...args: Parameters<T>) => void {
  let timeout: ReturnType<typeof setTimeout>;
  return (...args: Parameters<T>) => {
    clearTimeout(timeout);
    timeout = setTimeout(() => func(...args), wait);
  };
}
