import { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import {
  FileText,
  Search,
  Plus,
  Trash2,
  MoreVertical,
  Calendar,
} from 'lucide-react';
import { documentsApi } from '../lib/api';

interface Document {
  id: string;
  title: string;
  wordCount: number;
  charCount: number;
  language: string;
  createdAt: string;
  updatedAt: string;
  _count: {
    corrections: number;
  };
}

export default function Documents() {
  const [documents, setDocuments] = useState<Document[]>([]);
  const [loading, setLoading] = useState(true);
  const [search, setSearch] = useState('');
  const [page, setPage] = useState(1);
  const [totalPages, setTotalPages] = useState(1);

  useEffect(() => {
    loadDocuments();
  }, [page, search]);

  const loadDocuments = async () => {
    setLoading(true);
    try {
      const response = await documentsApi.list({
        page,
        limit: 10,
        search: search || undefined,
      });
      setDocuments(response.data.documents);
      setTotalPages(response.data.pagination.totalPages);
    } catch (error) {
      console.error('Failed to load documents:', error);
    } finally {
      setLoading(false);
    }
  };

  const deleteDocument = async (id: string) => {
    if (!confirm('Tem certeza que deseja excluir este documento?')) return;

    try {
      await documentsApi.delete(id);
      setDocuments(documents.filter((d) => d.id !== id));
    } catch (error) {
      console.error('Failed to delete document:', error);
    }
  };

  const formatDate = (dateString: string) => {
    const date = new Date(dateString);
    const dateFormatted = date.toLocaleDateString('pt-BR', {
      day: 'numeric',
      month: 'short',
      year: 'numeric',
    });
    const timeFormatted = date.toLocaleTimeString('pt-BR', {
      hour: '2-digit',
      minute: '2-digit',
    });
    return `${dateFormatted} às ${timeFormatted}`;
  };

  const getLanguageFlag = (lang: string) => {
    const flags: Record<string, string> = {
      PT_BR: '🇧🇷',
      EN_US: '🇺🇸',
      EN_GB: '🇬🇧',
      ES_ES: '🇪🇸',
      ES_MX: '🇲🇽',
    };
    return flags[lang] || '🌐';
  };

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold text-gray-900 dark:text-white">
            Documentos
          </h1>
          <p className="text-gray-500 dark:text-gray-400">
            Gerencie seus documentos salvos
          </p>
        </div>
        <Link to="/editor" className="btn btn-primary btn-md">
          <Plus className="h-4 w-4" />
          Novo documento
        </Link>
      </div>

      {/* Search */}
      <div className="relative">
        <Search className="absolute left-3 top-1/2 h-5 w-5 -translate-y-1/2 text-gray-400" />
        <input
          type="text"
          value={search}
          onChange={(e) => {
            setSearch(e.target.value);
            setPage(1);
          }}
          className="input pl-10"
          placeholder="Buscar documentos..."
        />
      </div>

      {/* Documents List */}
      {loading ? (
        <div className="flex justify-center py-12">
          <div className="h-8 w-8 animate-spin rounded-full border-4 border-primary-200 border-t-primary-700" />
        </div>
      ) : documents.length === 0 ? (
        <div className="card flex flex-col items-center justify-center py-12 text-center">
          <FileText className="mb-4 h-16 w-16 text-gray-300" />
          <h3 className="text-lg font-medium text-gray-900 dark:text-white">
            {search ? 'Nenhum documento encontrado' : 'Nenhum documento ainda'}
          </h3>
          <p className="text-gray-500">
            {search
              ? 'Tente uma busca diferente'
              : 'Crie seu primeiro documento para começar'}
          </p>
          {!search && (
            <Link to="/editor" className="btn btn-primary btn-md mt-4">
              Criar documento
            </Link>
          )}
        </div>
      ) : (
        <>
          <div className="space-y-3">
            {documents.map((doc) => (
              <div
                key={doc.id}
                className="card flex items-center justify-between transition-shadow hover:shadow-md"
              >
                <Link
                  to={`/editor/${doc.id}`}
                  className="flex flex-1 items-center gap-4"
                >
                  <div className="flex h-12 w-12 items-center justify-center rounded-lg bg-primary-100 text-primary-700 dark:bg-primary-900 dark:text-primary-300">
                    <FileText className="h-6 w-6" />
                  </div>
                  <div className="flex-1">
                    <div className="flex items-center gap-2">
                      <h3 className="font-medium text-gray-900 dark:text-white">
                        {doc.title}
                      </h3>
                      <span className="text-lg">
                        {getLanguageFlag(doc.language)}
                      </span>
                    </div>
                    <div className="flex items-center gap-4 text-sm text-gray-500">
                      <span>{doc.wordCount} palavras</span>
                      <span className="flex items-center gap-1">
                        <Calendar className="h-3 w-3" />
                        {formatDate(doc.updatedAt)}
                      </span>
                      {doc._count.corrections > 0 && (
                        <span className="rounded bg-amber-100 px-2 py-0.5 text-xs text-amber-700 dark:bg-amber-900 dark:text-amber-300">
                          {doc._count.corrections} correções
                        </span>
                      )}
                    </div>
                  </div>
                </Link>

                <div className="flex items-center gap-2">
                  <button
                    onClick={() => deleteDocument(doc.id)}
                    className="rounded-lg p-2 text-gray-400 hover:bg-red-50 hover:text-red-500 dark:hover:bg-red-900/20"
                    title="Excluir"
                  >
                    <Trash2 className="h-5 w-5" />
                  </button>
                  <button className="rounded-lg p-2 text-gray-400 hover:bg-gray-100 dark:hover:bg-gray-700">
                    <MoreVertical className="h-5 w-5" />
                  </button>
                </div>
              </div>
            ))}
          </div>

          {/* Pagination */}
          {totalPages > 1 && (
            <div className="flex items-center justify-center gap-2">
              <button
                onClick={() => setPage(Math.max(1, page - 1))}
                disabled={page === 1}
                className="btn btn-secondary btn-sm"
              >
                Anterior
              </button>
              <span className="px-4 text-sm text-gray-500">
                Página {page} de {totalPages}
              </span>
              <button
                onClick={() => setPage(Math.min(totalPages, page + 1))}
                disabled={page === totalPages}
                className="btn btn-secondary btn-sm"
              >
                Próxima
              </button>
            </div>
          )}
        </>
      )}
    </div>
  );
}
