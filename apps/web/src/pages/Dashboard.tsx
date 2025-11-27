import { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import {
  FileText,
  CheckCircle,
  TrendingUp,
  Clock,
  ArrowRight,
} from 'lucide-react';
import {
  AreaChart,
  Area,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  ResponsiveContainer,
} from 'recharts';
import { statsApi, documentsApi } from '../lib/api';

interface Stats {
  totalDocuments: number;
  totalCorrections: number;
  totalWordsChecked: number;
  acceptanceRate: number;
}

interface WeeklyData {
  date: string;
  count: number;
}

interface Document {
  id: string;
  title: string;
  wordCount: number;
  updatedAt: string;
}

export default function Dashboard() {
  const [stats, setStats] = useState<Stats | null>(null);
  const [weeklyData, setWeeklyData] = useState<WeeklyData[]>([]);
  const [recentDocs, setRecentDocs] = useState<Document[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    async function loadData() {
      try {
        const [statsRes, weeklyRes, docsRes] = await Promise.all([
          statsApi.getStats(),
          statsApi.getWeekly(),
          documentsApi.list({ limit: 5 }),
        ]);

        setStats(statsRes.data);
        setWeeklyData(weeklyRes.data.daily || []);
        setRecentDocs(docsRes.data.documents || []);
      } catch (error) {
        console.error('Failed to load dashboard data:', error);
      } finally {
        setLoading(false);
      }
    }

    loadData();
  }, []);

  if (loading) {
    return (
      <div className="flex h-full items-center justify-center">
        <div className="h-8 w-8 animate-spin rounded-full border-4 border-primary-200 border-t-primary-700" />
      </div>
    );
  }

  const statCards = [
    {
      label: 'Documentos',
      value: stats?.totalDocuments || 0,
      icon: FileText,
      color: 'bg-blue-500',
    },
    {
      label: 'Correções',
      value: stats?.totalCorrections || 0,
      icon: CheckCircle,
      color: 'bg-green-500',
    },
    {
      label: 'Palavras verificadas',
      value: formatNumber(stats?.totalWordsChecked || 0),
      icon: TrendingUp,
      color: 'bg-purple-500',
    },
    {
      label: 'Taxa de aceitação',
      value: `${stats?.acceptanceRate || 0}%`,
      icon: Clock,
      color: 'bg-amber-500',
    },
  ];

  return (
    <div className="space-y-6">
      {/* Header */}
      <div>
        <h1 className="text-2xl font-bold text-gray-900 dark:text-white">
          Dashboard
        </h1>
        <p className="text-gray-500 dark:text-gray-400">
          Visão geral das suas estatísticas de escrita
        </p>
      </div>

      {/* Stats Cards */}
      <div className="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">
        {statCards.map((stat) => (
          <div key={stat.label} className="card">
            <div className="flex items-center gap-4">
              <div
                className={`flex h-12 w-12 items-center justify-center rounded-lg ${stat.color}`}
              >
                <stat.icon className="h-6 w-6 text-white" />
              </div>
              <div>
                <p className="text-sm text-gray-500 dark:text-gray-400">
                  {stat.label}
                </p>
                <p className="text-2xl font-bold text-gray-900 dark:text-white">
                  {stat.value}
                </p>
              </div>
            </div>
          </div>
        ))}
      </div>

      {/* Charts and Recent Documents */}
      <div className="grid gap-6 lg:grid-cols-2">
        {/* Weekly Activity Chart */}
        <div className="card">
          <h2 className="mb-4 text-lg font-semibold text-gray-900 dark:text-white">
            Atividade semanal
          </h2>
          <div className="h-64">
            <ResponsiveContainer width="100%" height="100%">
              <AreaChart data={weeklyData}>
                <CartesianGrid strokeDasharray="3 3" stroke="#e5e7eb" />
                <XAxis
                  dataKey="date"
                  tick={{ fontSize: 12 }}
                  tickFormatter={(value) => {
                    const date = new Date(value);
                    return date.toLocaleDateString('pt-BR', {
                      weekday: 'short',
                    });
                  }}
                />
                <YAxis tick={{ fontSize: 12 }} />
                <Tooltip
                  contentStyle={{
                    backgroundColor: '#fff',
                    border: '1px solid #e5e7eb',
                    borderRadius: '8px',
                  }}
                  labelFormatter={(value) => {
                    const date = new Date(value);
                    return date.toLocaleDateString('pt-BR', {
                      weekday: 'long',
                      day: 'numeric',
                      month: 'short',
                    });
                  }}
                />
                <Area
                  type="monotone"
                  dataKey="count"
                  name="Correções"
                  stroke="#15803d"
                  fill="#dcfce7"
                />
              </AreaChart>
            </ResponsiveContainer>
          </div>
        </div>

        {/* Recent Documents */}
        <div className="card">
          <div className="mb-4 flex items-center justify-between">
            <h2 className="text-lg font-semibold text-gray-900 dark:text-white">
              Documentos recentes
            </h2>
            <Link
              to="/documents"
              className="flex items-center gap-1 text-sm text-primary-600 hover:text-primary-700"
            >
              Ver todos
              <ArrowRight className="h-4 w-4" />
            </Link>
          </div>

          {recentDocs.length === 0 ? (
            <div className="flex flex-col items-center justify-center py-8 text-center">
              <FileText className="mb-2 h-12 w-12 text-gray-300" />
              <p className="text-gray-500">Nenhum documento ainda</p>
              <Link
                to="/editor"
                className="mt-2 text-sm text-primary-600 hover:underline"
              >
                Criar primeiro documento
              </Link>
            </div>
          ) : (
            <div className="space-y-3">
              {recentDocs.map((doc) => (
                <Link
                  key={doc.id}
                  to={`/editor/${doc.id}`}
                  className="flex items-center justify-between rounded-lg border border-gray-200 p-3 transition-colors hover:bg-gray-50 dark:border-gray-700 dark:hover:bg-gray-700/50"
                >
                  <div className="flex items-center gap-3">
                    <FileText className="h-5 w-5 text-gray-400" />
                    <div>
                      <p className="font-medium text-gray-900 dark:text-white">
                        {doc.title}
                      </p>
                      <p className="text-sm text-gray-500">
                        {doc.wordCount} palavras
                      </p>
                    </div>
                  </div>
                  <span className="text-sm text-gray-400">
                    {formatDate(doc.updatedAt)}
                  </span>
                </Link>
              ))}
            </div>
          )}
        </div>
      </div>
    </div>
  );
}

function formatNumber(num: number): string {
  if (num >= 1000000) {
    return (num / 1000000).toFixed(1) + 'M';
  }
  if (num >= 1000) {
    return (num / 1000).toFixed(1) + 'K';
  }
  return num.toString();
}

function formatDate(dateString: string): string {
  const date = new Date(dateString);
  const now = new Date();
  const diff = now.getTime() - date.getTime();
  const days = Math.floor(diff / (1000 * 60 * 60 * 24));

  if (days === 0) return 'Hoje';
  if (days === 1) return 'Ontem';
  if (days < 7) return `${days} dias atrás`;

  return date.toLocaleDateString('pt-BR', {
    day: 'numeric',
    month: 'short',
  });
}
