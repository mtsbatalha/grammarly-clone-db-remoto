import axios from 'axios';

const API_URL = import.meta.env.VITE_API_URL || '/api/v1';

export const api = axios.create({
  baseURL: API_URL,
  headers: {
    'Content-Type': 'application/json',
  },
});

// Response interceptor for error handling
api.interceptors.response.use(
  (response) => response,
  async (error) => {
    const originalRequest = error.config;

    // Handle 401 errors (token expired)
    if (error.response?.status === 401 && !originalRequest._retry) {
      originalRequest._retry = true;

      try {
        // Try to refresh token
        const { useAuthStore } = await import('../stores/authStore');
        await useAuthStore.getState().refreshAuth();

        // Retry original request
        const token = useAuthStore.getState().token;
        if (token) {
          originalRequest.headers['Authorization'] = `Bearer ${token}`;
          return api(originalRequest);
        }
      } catch {
        // Refresh failed, redirect to login
        window.location.href = '/login';
      }
    }

    return Promise.reject(error);
  }
);

// Grammar API
export const grammarApi = {
  check: (text: string, language: string = 'PT_BR', options?: object) =>
    api.post('/grammar/check', { text, language, options }),

  adjustTone: (text: string, targetTone: string, language: string = 'PT_BR') =>
    api.post('/grammar/tone', { text, targetTone, language }),

  rewrite: (text: string, style: string, language: string = 'PT_BR') =>
    api.post('/grammar/rewrite', { text, style, language }),

  translate: (text: string, targetLanguage: string) =>
    api.post('/grammar/translate', { text, targetLanguage }),

  getLanguages: () => api.get('/grammar/languages'),

  getTones: () => api.get('/grammar/tones'),
};

// Documents API
export const documentsApi = {
  list: (params?: { page?: number; limit?: number; search?: string }) =>
    api.get('/documents', { params }),

  get: (id: string) => api.get(`/documents/${id}`),

  create: (data: { title?: string; content: string; language?: string }) =>
    api.post('/documents', data),

  update: (id: string, data: { title?: string; content?: string }) =>
    api.patch(`/documents/${id}`, data),

  delete: (id: string) => api.delete(`/documents/${id}`),

  getRevisions: (id: string, params?: { page?: number; limit?: number }) =>
    api.get(`/documents/${id}/revisions`, { params }),

  restoreRevision: (documentId: string, revisionId: string) =>
    api.post(`/documents/${documentId}/restore/${revisionId}`),
};

// User API
export const userApi = {
  getProfile: () => api.get('/users/profile'),

  updateProfile: (data: { name?: string; preferredLanguage?: string }) =>
    api.patch('/users/profile', data),

  updatePassword: (data: { currentPassword: string; newPassword: string }) =>
    api.patch('/users/password', data),

  getSettings: () => api.get('/users/settings'),

  updateSettings: (settings: object) => api.patch('/users/settings', settings),

  addToDictionary: (word: string) =>
    api.post('/users/dictionary', { word }),

  removeFromDictionary: (word: string) =>
    api.delete(`/users/dictionary/${word}`),

  deleteAccount: (password: string) =>
    api.delete('/users/account', { data: { password } }),

  getAIConfig: () => api.get('/users/ai-config'),
};

// Stats API
export const statsApi = {
  getStats: () => api.get('/stats'),

  getWeekly: () => api.get('/stats/weekly'),

  getByType: () => api.get('/stats/corrections-by-type'),

  getRecentActivity: () => api.get('/stats/recent-activity'),

  getUsage: () => api.get('/stats/usage'),
};
