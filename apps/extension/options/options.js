// ===========================================
// GRAMMARLY CLONE - OPTIONS SCRIPT
// ===========================================

document.addEventListener('DOMContentLoaded', async () => {
  // Elements
  const elements = {
    language: document.getElementById('language'),
    autoCheck: document.getElementById('autoCheck'),
    showInlineHighlights: document.getElementById('showInlineHighlights'),
    enableGrammar: document.getElementById('enableGrammar'),
    enableSpelling: document.getElementById('enableSpelling'),
    enablePunctuation: document.getElementById('enablePunctuation'),
    enableStyle: document.getElementById('enableStyle'),
    enableClarity: document.getElementById('enableClarity'),
    enableTone: document.getElementById('enableTone'),
    apiUrl: document.getElementById('apiUrl'),
    statusIndicator: document.getElementById('statusIndicator'),
    statusText: document.getElementById('statusText'),
    testConnection: document.getElementById('testConnection'),
    resetBtn: document.getElementById('resetBtn'),
    saveBtn: document.getElementById('saveBtn'),
    toast: document.getElementById('toast'),
    toastMessage: document.getElementById('toastMessage'),
  };

  // Default settings
  const defaults = {
    language: 'PT_BR',
    autoCheck: true,
    showInlineHighlights: true,
    enableGrammar: true,
    enableSpelling: true,
    enablePunctuation: true,
    enableStyle: true,
    enableClarity: true,
    enableTone: false,
    apiUrl: 'http://localhost:3001/api/v1',
  };

  // ===========================================
  // UTILITIES
  // ===========================================

  function showToast(message, type = 'success') {
    elements.toastMessage.textContent = message;
    elements.toast.className = `toast ${type}`;

    setTimeout(() => {
      elements.toast.classList.add('hidden');
    }, 3000);
  }

  async function testApiConnection(url) {
    try {
      const response = await fetch(`${url.replace('/api/v1', '')}/health`, {
        method: 'GET',
        signal: AbortSignal.timeout(5000),
      });

      if (response.ok) {
        const data = await response.json();
        return {
          connected: data.status === 'healthy',
          message: 'Conexão estabelecida',
        };
      }

      return { connected: false, message: 'Servidor não respondeu corretamente' };
    } catch (error) {
      if (error.name === 'TimeoutError') {
        return { connected: false, message: 'Conexão expirou' };
      }
      return { connected: false, message: 'Não foi possível conectar' };
    }
  }

  function updateConnectionStatus(connected, message) {
    elements.statusIndicator.className = `status-indicator ${connected ? 'connected' : 'error'}`;
    elements.statusText.textContent = message;
  }

  // ===========================================
  // LOAD SETTINGS
  // ===========================================

  async function loadSettings() {
    const settings = await chrome.storage.sync.get(Object.keys(defaults));

    // Apply settings to form
    Object.keys(defaults).forEach(key => {
      const element = elements[key];
      const value = settings[key] ?? defaults[key];

      if (!element) return;

      if (element.type === 'checkbox') {
        element.checked = value;
      } else {
        element.value = value;
      }
    });

    // Test connection
    const connectionResult = await testApiConnection(settings.apiUrl || defaults.apiUrl);
    updateConnectionStatus(connectionResult.connected, connectionResult.message);
  }

  // ===========================================
  // SAVE SETTINGS
  // ===========================================

  async function saveSettings() {
    const settings = {
      language: elements.language.value,
      autoCheck: elements.autoCheck.checked,
      showInlineHighlights: elements.showInlineHighlights.checked,
      enableGrammar: elements.enableGrammar.checked,
      enableSpelling: elements.enableSpelling.checked,
      enablePunctuation: elements.enablePunctuation.checked,
      enableStyle: elements.enableStyle.checked,
      enableClarity: elements.enableClarity.checked,
      enableTone: elements.enableTone.checked,
      apiUrl: elements.apiUrl.value,
    };

    await chrome.storage.sync.set(settings);

    // Notify all tabs about settings update
    chrome.runtime.sendMessage({
      type: 'UPDATE_SETTINGS',
      settings,
    });

    showToast('Configurações salvas!', 'success');
  }

  // ===========================================
  // RESET SETTINGS
  // ===========================================

  async function resetSettings() {
    if (!confirm('Tem certeza que deseja restaurar as configurações padrão?')) {
      return;
    }

    await chrome.storage.sync.set(defaults);
    await loadSettings();
    showToast('Configurações restauradas!', 'success');
  }

  // ===========================================
  // EVENT LISTENERS
  // ===========================================

  elements.testConnection.addEventListener('click', async () => {
    elements.testConnection.disabled = true;
    elements.testConnection.textContent = 'Testando...';

    const result = await testApiConnection(elements.apiUrl.value);
    updateConnectionStatus(result.connected, result.message);

    elements.testConnection.disabled = false;
    elements.testConnection.textContent = 'Testar Conexão';

    showToast(
      result.connected ? 'Conexão bem sucedida!' : 'Falha na conexão',
      result.connected ? 'success' : 'error'
    );
  });

  elements.saveBtn.addEventListener('click', saveSettings);
  elements.resetBtn.addEventListener('click', resetSettings);

  // Save on Enter key in inputs
  elements.apiUrl.addEventListener('keypress', (e) => {
    if (e.key === 'Enter') {
      saveSettings();
    }
  });

  // Auto-save toggles
  const toggles = [
    'autoCheck', 'showInlineHighlights', 'enableGrammar', 'enableSpelling',
    'enablePunctuation', 'enableStyle', 'enableClarity', 'enableTone'
  ];

  toggles.forEach(id => {
    elements[id]?.addEventListener('change', saveSettings);
  });

  elements.language.addEventListener('change', saveSettings);

  // ===========================================
  // INITIALIZATION
  // ===========================================

  loadSettings();
});
