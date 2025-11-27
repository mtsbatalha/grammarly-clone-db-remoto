// ===========================================
// GRAMMARLY CLONE - POPUP SCRIPT
// ===========================================

document.addEventListener('DOMContentLoaded', async () => {
  // Elements
  const enabledToggle = document.getElementById('enabled-toggle');
  const statusText = document.getElementById('status-text');
  const langButtons = document.querySelectorAll('.lang-btn');
  const checkNowBtn = document.getElementById('check-now-btn');
  const dashboardBtn = document.getElementById('dashboard-btn');
  const settingsBtn = document.getElementById('settings-btn');
  const loginBtn = document.getElementById('login-btn');
  const logoutBtn = document.getElementById('logout-btn');
  const loggedOutSection = document.getElementById('logged-out-section');
  const loggedInSection = document.getElementById('logged-in-section');
  const loginModal = document.getElementById('login-modal');
  const loginForm = document.getElementById('login-form');
  const loginError = document.getElementById('login-error');
  const userName = document.getElementById('user-name');
  const userPlan = document.getElementById('user-plan');
  const userAvatar = document.getElementById('user-avatar');
  const correctionsToday = document.getElementById('corrections-today');
  const wordsChecked = document.getElementById('words-checked');

  // ===========================================
  // INITIALIZATION
  // ===========================================

  async function init() {
    // Load settings
    const settings = await chrome.storage.sync.get([
      'enabled',
      'language',
      'user',
      'token',
    ]);

    // Update toggle
    enabledToggle.checked = settings.enabled !== false;
    updateToggleStatus(enabledToggle.checked);

    // Update language
    const lang = settings.language || 'PT_BR';
    langButtons.forEach(btn => {
      btn.classList.toggle('active', btn.dataset.lang === lang);
    });

    // Update user section
    if (settings.token && settings.user) {
      showLoggedInState(settings.user);
    } else {
      showLoggedOutState();
    }

    // Load stats
    await loadStats();
  }

  function updateToggleStatus(enabled) {
    statusText.textContent = enabled ? 'Ativado' : 'Desativado';
    statusText.classList.toggle('disabled', !enabled);
  }

  function showLoggedInState(user) {
    loggedOutSection.classList.add('hidden');
    loggedInSection.classList.remove('hidden');

    userName.textContent = user.name || user.email;
    userPlan.textContent = `Plano ${user.plan}`;
    userAvatar.textContent = (user.name || user.email).charAt(0).toUpperCase();
  }

  function showLoggedOutState() {
    loggedOutSection.classList.remove('hidden');
    loggedInSection.classList.add('hidden');
  }

  async function loadStats() {
    try {
      const { token } = await chrome.storage.sync.get(['token']);

      if (!token) {
        correctionsToday.textContent = '0';
        wordsChecked.textContent = '0';
        return;
      }

      const response = await fetch('http://localhost:3003/api/v1/stats/usage', {
        headers: {
          'Authorization': `Bearer ${token}`,
        },
      });

      if (response.ok) {
        const data = await response.json();
        correctionsToday.textContent = data.checksUsed || '0';

        // Get words checked from full stats
        const statsResponse = await fetch('http://localhost:3003/api/v1/stats', {
          headers: {
            'Authorization': `Bearer ${token}`,
          },
        });

        if (statsResponse.ok) {
          const stats = await statsResponse.json();
          wordsChecked.textContent = formatNumber(stats.totalWordsChecked || 0);
        }
      }
    } catch (error) {
      console.error('Failed to load stats:', error);
    }
  }

  function formatNumber(num) {
    if (num >= 1000000) {
      return (num / 1000000).toFixed(1) + 'M';
    }
    if (num >= 1000) {
      return (num / 1000).toFixed(1) + 'K';
    }
    return num.toString();
  }

  // ===========================================
  // EVENT HANDLERS
  // ===========================================

  // Toggle enabled
  enabledToggle.addEventListener('change', async (e) => {
    const enabled = e.target.checked;

    await chrome.storage.sync.set({ enabled });
    updateToggleStatus(enabled);

    // Notify content scripts
    const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
    if (tab) {
      chrome.tabs.sendMessage(tab.id, { type: 'TOGGLE_ENABLED', enabled });
    }
  });

  // Language selection
  langButtons.forEach(btn => {
    btn.addEventListener('click', async () => {
      const lang = btn.dataset.lang;

      langButtons.forEach(b => b.classList.remove('active'));
      btn.classList.add('active');

      await chrome.storage.sync.set({ language: lang });

      // Notify content scripts
      const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
      if (tab) {
        chrome.tabs.sendMessage(tab.id, { type: 'SET_LANGUAGE', language: lang });
      }
    });
  });

  // Check now button
  checkNowBtn.addEventListener('click', async () => {
    const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
    if (tab) {
      chrome.tabs.sendMessage(tab.id, { type: 'CHECK_NOW' });
    }
  });

  // Dashboard button
  dashboardBtn.addEventListener('click', () => {
    chrome.tabs.create({ url: 'http://localhost:5173' });
  });

  // Settings button
  settingsBtn.addEventListener('click', () => {
    chrome.runtime.openOptionsPage();
  });

  // Login button
  loginBtn.addEventListener('click', () => {
    loginModal.classList.remove('hidden');
  });

  // Close modal
  document.querySelector('.close-modal').addEventListener('click', () => {
    loginModal.classList.add('hidden');
    loginError.classList.add('hidden');
    loginForm.reset();
  });

  // Login form
  loginForm.addEventListener('submit', async (e) => {
    e.preventDefault();

    const email = document.getElementById('email').value;
    const password = document.getElementById('password').value;

    try {
      const response = await chrome.runtime.sendMessage({
        type: 'LOGIN',
        email,
        password,
      });

      if (response.success) {
        loginModal.classList.add('hidden');
        loginForm.reset();
        showLoggedInState(response.result.user);
        await loadStats();

        // Notify content scripts
        const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
        if (tab) {
          chrome.tabs.sendMessage(tab.id, {
            type: 'SET_TOKEN',
            token: response.result.accessToken,
          });
        }
      } else {
        loginError.textContent = response.error || 'Erro ao fazer login';
        loginError.classList.remove('hidden');
      }
    } catch (error) {
      loginError.textContent = 'Erro de conexão';
      loginError.classList.remove('hidden');
    }
  });

  // Logout button
  logoutBtn.addEventListener('click', async () => {
    await chrome.runtime.sendMessage({ type: 'LOGOUT' });
    showLoggedOutState();

    // Notify content scripts
    const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
    if (tab) {
      chrome.tabs.sendMessage(tab.id, { type: 'SET_TOKEN', token: null });
    }
  });

  // Initialize
  init();
});
