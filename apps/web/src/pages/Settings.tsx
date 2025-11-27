import { useEffect, useState } from 'react';
import { User, Globe, Shield, Trash2, Bot, ExternalLink, CheckCircle, XCircle } from 'lucide-react';
import { useAuthStore } from '../stores/authStore';
import { userApi } from '../lib/api';

interface Settings {
  enableGrammar: boolean;
  enableSpelling: boolean;
  enablePunctuation: boolean;
  enableStyle: boolean;
  enableTone: boolean;
  enableClarity: boolean;
  preferredTone: string;
  showInlineCorrections: boolean;
  autoCorrect: boolean;
  darkMode: boolean;
}

interface AIProvider {
  id: string;
  name: string;
  description: string;
  website: string;
  configured: boolean;
  apiKey?: string | null;
  model?: string;
}

interface AIConfig {
  currentProvider: string;
  providers: AIProvider[];
  note: string;
}

export default function Settings() {
  const { user, updateUser, logout } = useAuthStore();
  const [activeTab, setActiveTab] = useState('profile');
  const [loading, setLoading] = useState(false);
  const [message, setMessage] = useState<{ type: 'success' | 'error'; text: string } | null>(null);

  // Profile form
  const [name, setName] = useState(user?.name || '');
  const [preferredLanguage, setPreferredLanguage] = useState(user?.preferredLanguage || 'PT_BR');

  // Password form
  const [currentPassword, setCurrentPassword] = useState('');
  const [newPassword, setNewPassword] = useState('');
  const [confirmPassword, setConfirmPassword] = useState('');

  // AI Config
  const [aiConfig, setAiConfig] = useState<AIConfig | null>(null);
  const [aiLoading, setAiLoading] = useState(false);

  // Settings
  const [settings, setSettings] = useState<Settings>({
    enableGrammar: true,
    enableSpelling: true,
    enablePunctuation: true,
    enableStyle: true,
    enableTone: false,
    enableClarity: true,
    preferredTone: 'NEUTRAL',
    showInlineCorrections: true,
    autoCorrect: false,
    darkMode: false,
  });

  useEffect(() => {
    loadSettings();
    loadAIConfig();
  }, []);

  const loadSettings = async () => {
    try {
      const response = await userApi.getSettings();
      if (response.data.settings) {
        setSettings(response.data.settings);
      }
    } catch (error) {
      console.error('Failed to load settings:', error);
    }
  };

  const loadAIConfig = async () => {
    setAiLoading(true);
    try {
      const response = await userApi.getAIConfig();
      setAiConfig(response.data);
    } catch (error) {
      console.error('Failed to load AI config:', error);
    } finally {
      setAiLoading(false);
    }
  };

  const showMessage = (type: 'success' | 'error', text: string) => {
    setMessage({ type, text });
    setTimeout(() => setMessage(null), 3000);
  };

  const handleUpdateProfile = async (e: React.FormEvent) => {
    e.preventDefault();
    setLoading(true);
    try {
      await userApi.updateProfile({ name, preferredLanguage });
      updateUser({ name, preferredLanguage });
      showMessage('success', 'Perfil atualizado com sucesso!');
    } catch {
      showMessage('error', 'Erro ao atualizar perfil');
    } finally {
      setLoading(false);
    }
  };

  const handleUpdatePassword = async (e: React.FormEvent) => {
    e.preventDefault();
    if (newPassword !== confirmPassword) {
      showMessage('error', 'As senhas não coincidem');
      return;
    }
    setLoading(true);
    try {
      await userApi.updatePassword({ currentPassword, newPassword });
      setCurrentPassword('');
      setNewPassword('');
      setConfirmPassword('');
      showMessage('success', 'Senha alterada com sucesso!');
    } catch {
      showMessage('error', 'Erro ao alterar senha');
    } finally {
      setLoading(false);
    }
  };

  const handleUpdateSettings = async (key: keyof Settings, value: boolean | string) => {
    const newSettings = { ...settings, [key]: value };
    setSettings(newSettings);
    try {
      await userApi.updateSettings({ [key]: value });
    } catch {
      showMessage('error', 'Erro ao atualizar configuração');
    }
  };

  const handleDeleteAccount = async () => {
    const password = prompt('Digite sua senha para confirmar a exclusão da conta:');
    if (!password) return;

    if (!confirm('Esta ação é irreversível. Deseja realmente excluir sua conta?')) return;

    try {
      await userApi.deleteAccount(password);
      await logout();
    } catch {
      showMessage('error', 'Erro ao excluir conta. Verifique sua senha.');
    }
  };

  const tabs = [
    { id: 'profile', label: 'Perfil', icon: User },
    { id: 'preferences', label: 'Preferências', icon: Globe },
    { id: 'ai', label: 'Inteligência Artificial', icon: Bot },
    { id: 'security', label: 'Segurança', icon: Shield },
  ];

  return (
    <div className="space-y-6">
      {/* Header */}
      <div>
        <h1 className="text-2xl font-bold text-gray-900 dark:text-white">
          Configurações
        </h1>
        <p className="text-gray-500 dark:text-gray-400">
          Gerencie sua conta e preferências
        </p>
      </div>

      {/* Message */}
      {message && (
        <div
          className={`rounded-lg p-3 text-sm ${
            message.type === 'success'
              ? 'bg-green-50 text-green-600 dark:bg-green-900/30 dark:text-green-400'
              : 'bg-red-50 text-red-600 dark:bg-red-900/30 dark:text-red-400'
          }`}
        >
          {message.text}
        </div>
      )}

      <div className="flex gap-6">
        {/* Tabs */}
        <nav className="w-48 space-y-1">
          {tabs.map((tab) => (
            <button
              key={tab.id}
              onClick={() => setActiveTab(tab.id)}
              className={`flex w-full items-center gap-3 rounded-lg px-3 py-2.5 text-sm font-medium transition-colors ${
                activeTab === tab.id
                  ? 'bg-primary-50 text-primary-700 dark:bg-primary-900/30 dark:text-primary-400'
                  : 'text-gray-600 hover:bg-gray-100 dark:text-gray-300 dark:hover:bg-gray-700'
              }`}
            >
              <tab.icon className="h-5 w-5" />
              {tab.label}
            </button>
          ))}
        </nav>

        {/* Content */}
        <div className="flex-1">
          {activeTab === 'profile' && (
            <div className="card">
              <h2 className="mb-6 text-lg font-semibold">Informações do perfil</h2>
              <form onSubmit={handleUpdateProfile} className="space-y-4">
                <div>
                  <label className="mb-1 block text-sm font-medium text-gray-700 dark:text-gray-300">
                    Email
                  </label>
                  <input
                    type="email"
                    value={user?.email || ''}
                    disabled
                    className="input bg-gray-100 dark:bg-gray-700"
                  />
                </div>
                <div>
                  <label className="mb-1 block text-sm font-medium text-gray-700 dark:text-gray-300">
                    Nome
                  </label>
                  <input
                    type="text"
                    value={name}
                    onChange={(e) => setName(e.target.value)}
                    className="input"
                  />
                </div>
                <div>
                  <label className="mb-1 block text-sm font-medium text-gray-700 dark:text-gray-300">
                    Idioma preferido
                  </label>
                  <select
                    value={preferredLanguage}
                    onChange={(e) => setPreferredLanguage(e.target.value)}
                    className="input"
                  >
                    <option value="PT_BR">Português (Brasil)</option>
                    <option value="EN_US">English (US)</option>
                    <option value="EN_GB">English (UK)</option>
                  </select>
                </div>
                <div>
                  <label className="mb-1 block text-sm font-medium text-gray-700 dark:text-gray-300">
                    Plano atual
                  </label>
                  <div className="flex items-center gap-2">
                    <span className="rounded-full bg-primary-100 px-3 py-1 text-sm font-medium text-primary-700">
                      {user?.plan}
                    </span>
                    {user?.plan === 'FREE' && (
                      <button type="button" className="text-sm text-primary-600 hover:underline">
                        Fazer upgrade
                      </button>
                    )}
                  </div>
                </div>
                <button type="submit" disabled={loading} className="btn btn-primary btn-md">
                  Salvar alterações
                </button>
              </form>
            </div>
          )}

          {activeTab === 'preferences' && (
            <div className="card">
              <h2 className="mb-6 text-lg font-semibold">Preferências de correção</h2>
              <div className="space-y-4">
                {[
                  { key: 'enableGrammar', label: 'Gramática', desc: 'Correções gramaticais' },
                  { key: 'enableSpelling', label: 'Ortografia', desc: 'Erros de escrita' },
                  { key: 'enablePunctuation', label: 'Pontuação', desc: 'Vírgulas e pontos' },
                  { key: 'enableStyle', label: 'Estilo', desc: 'Sugestões de estilo' },
                  { key: 'enableClarity', label: 'Clareza', desc: 'Clareza do texto' },
                  { key: 'enableTone', label: 'Tom', desc: 'Ajustes de tom' },
                ].map(({ key, label, desc }) => (
                  <div key={key} className="flex items-center justify-between">
                    <div>
                      <p className="font-medium text-gray-900 dark:text-white">{label}</p>
                      <p className="text-sm text-gray-500">{desc}</p>
                    </div>
                    <label className="relative inline-flex cursor-pointer items-center">
                      <input
                        type="checkbox"
                        checked={settings[key as keyof Settings] as boolean}
                        onChange={(e) => handleUpdateSettings(key as keyof Settings, e.target.checked)}
                        className="peer sr-only"
                      />
                      <div className="peer h-6 w-11 rounded-full bg-gray-200 after:absolute after:left-[2px] after:top-[2px] after:h-5 after:w-5 after:rounded-full after:bg-white after:transition-all peer-checked:bg-primary-600 peer-checked:after:translate-x-full dark:bg-gray-700"></div>
                    </label>
                  </div>
                ))}
              </div>
            </div>
          )}

          {activeTab === 'ai' && (
            <div className="space-y-6">
              <div className="card">
                <h2 className="mb-6 text-lg font-semibold">Configuração de IA</h2>

                {aiLoading ? (
                  <div className="flex justify-center py-8">
                    <div className="h-8 w-8 animate-spin rounded-full border-4 border-primary-200 border-t-primary-700" />
                  </div>
                ) : aiConfig ? (
                  <div className="space-y-6">
                    {/* Current Provider */}
                    <div className="rounded-lg border border-primary-200 bg-primary-50 p-4 dark:border-primary-800 dark:bg-primary-900/20">
                      <div className="flex items-center gap-2 text-primary-700 dark:text-primary-300">
                        <CheckCircle className="h-5 w-5" />
                        <span className="font-medium">Provedor atual:</span>
                        <span className="font-bold uppercase">{aiConfig.currentProvider}</span>
                      </div>
                    </div>

                    {/* Providers List */}
                    <div className="space-y-4">
                      <h3 className="text-sm font-medium text-gray-700 dark:text-gray-300">
                        Provedores disponíveis
                      </h3>
                      {aiConfig.providers.map((provider) => (
                        <div
                          key={provider.id}
                          className={`rounded-lg border p-4 ${
                            aiConfig.currentProvider === provider.id
                              ? 'border-primary-300 bg-primary-50 dark:border-primary-700 dark:bg-primary-900/20'
                              : 'border-gray-200 dark:border-gray-700'
                          }`}
                        >
                          <div className="flex items-start justify-between">
                            <div className="flex-1">
                              <div className="flex items-center gap-2">
                                <h4 className="font-medium text-gray-900 dark:text-white">
                                  {provider.name}
                                </h4>
                                {aiConfig.currentProvider === provider.id && (
                                  <span className="rounded-full bg-primary-600 px-2 py-0.5 text-xs text-white">
                                    Ativo
                                  </span>
                                )}
                              </div>
                              <p className="mt-1 text-sm text-gray-500">{provider.description}</p>
                              <div className="mt-2 flex items-center gap-4 text-sm">
                                <span className="flex items-center gap-1">
                                  {provider.configured ? (
                                    <CheckCircle className="h-4 w-4 text-green-500" />
                                  ) : (
                                    <XCircle className="h-4 w-4 text-red-500" />
                                  )}
                                  <span className={provider.configured ? 'text-green-600' : 'text-red-600'}>
                                    {provider.configured ? 'Configurado' : 'Não configurado'}
                                  </span>
                                </span>
                                {provider.apiKey && (
                                  <span className="text-gray-500">
                                    API Key: <code className="rounded bg-gray-100 px-1 dark:bg-gray-700">{provider.apiKey}</code>
                                  </span>
                                )}
                                {provider.model && (
                                  <span className="text-gray-500">
                                    Modelo: <code className="rounded bg-gray-100 px-1 dark:bg-gray-700">{provider.model}</code>
                                  </span>
                                )}
                              </div>
                            </div>
                            <a
                              href={provider.website}
                              target="_blank"
                              rel="noopener noreferrer"
                              className="flex items-center gap-1 text-sm text-primary-600 hover:text-primary-700"
                            >
                              <ExternalLink className="h-4 w-4" />
                              Site
                            </a>
                          </div>
                        </div>
                      ))}
                    </div>

                    {/* Configuration Note */}
                    <div className="rounded-lg border border-amber-200 bg-amber-50 p-4 dark:border-amber-800 dark:bg-amber-900/20">
                      <p className="text-sm text-amber-700 dark:text-amber-300">
                        <strong>Nota:</strong> {aiConfig.note}
                      </p>
                    </div>
                  </div>
                ) : (
                  <p className="text-gray-500">Não foi possível carregar as configurações de IA.</p>
                )}
              </div>
            </div>
          )}

          {activeTab === 'security' && (
            <div className="space-y-6">
              <div className="card">
                <h2 className="mb-6 text-lg font-semibold">Alterar senha</h2>
                <form onSubmit={handleUpdatePassword} className="space-y-4">
                  <div>
                    <label className="mb-1 block text-sm font-medium">Senha atual</label>
                    <input
                      type="password"
                      value={currentPassword}
                      onChange={(e) => setCurrentPassword(e.target.value)}
                      className="input"
                      required
                    />
                  </div>
                  <div>
                    <label className="mb-1 block text-sm font-medium">Nova senha</label>
                    <input
                      type="password"
                      value={newPassword}
                      onChange={(e) => setNewPassword(e.target.value)}
                      className="input"
                      required
                      minLength={8}
                    />
                  </div>
                  <div>
                    <label className="mb-1 block text-sm font-medium">Confirmar nova senha</label>
                    <input
                      type="password"
                      value={confirmPassword}
                      onChange={(e) => setConfirmPassword(e.target.value)}
                      className="input"
                      required
                      minLength={8}
                    />
                  </div>
                  <button type="submit" disabled={loading} className="btn btn-primary btn-md">
                    Alterar senha
                  </button>
                </form>
              </div>

              <div className="card border-red-200 dark:border-red-800">
                <h2 className="mb-2 text-lg font-semibold text-red-600">Zona de perigo</h2>
                <p className="mb-4 text-sm text-gray-500">
                  Ao excluir sua conta, todos os seus dados serão permanentemente removidos.
                </p>
                <button onClick={handleDeleteAccount} className="btn btn-danger btn-md">
                  <Trash2 className="h-4 w-4" />
                  Excluir conta
                </button>
              </div>
            </div>
          )}
        </div>
      </div>
    </div>
  );
}
