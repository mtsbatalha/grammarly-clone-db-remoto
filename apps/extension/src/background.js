// ===========================================
// GRAMMARLY CLONE - BACKGROUND SERVICE WORKER
// ===========================================

const CONFIG = {
  API_URL: 'http://localhost:3003/api/v1',
};

// ===========================================
// INSTALLATION & UPDATES
// ===========================================

chrome.runtime.onInstalled.addListener((details) => {
  if (details.reason === 'install') {
    // Set default settings
    chrome.storage.sync.set({
      enabled: true,
      language: 'PT_BR',
      enableGrammar: true,
      enableSpelling: true,
      enablePunctuation: true,
      enableStyle: true,
      enableTone: false,
      enableClarity: true,
      showInlineHighlights: true,
      autoCheck: true,
      token: null,
    });

    // Open welcome page
    chrome.tabs.create({
      url: 'welcome/welcome.html',
    });
  }

  // Create context menu
  chrome.contextMenus.create({
    id: 'grammarly-clone-check',
    title: 'Verificar gramática',
    contexts: ['selection'],
  });
});

// ===========================================
// CONTEXT MENU
// ===========================================

chrome.contextMenus.onClicked.addListener(async (info, tab) => {
  if (info.menuItemId === 'grammarly-clone-check' && info.selectionText) {
    try {
      const result = await checkGrammar(info.selectionText);

      // Send result to content script
      chrome.tabs.sendMessage(tab.id, {
        type: 'CONTEXT_MENU_CHECK_RESULT',
        result,
      });
    } catch (error) {
      console.error('Context menu check failed:', error);
    }
  }
});

// ===========================================
// API COMMUNICATION
// ===========================================

async function checkGrammar(text, language = 'PT_BR') {
  const { token } = await chrome.storage.sync.get(['token']);

  const headers = {
    'Content-Type': 'application/json',
  };

  if (token) {
    headers['Authorization'] = `Bearer ${token}`;
  }

  const response = await fetch(`${CONFIG.API_URL}/grammar/check`, {
    method: 'POST',
    headers,
    body: JSON.stringify({ text, language }),
  });

  if (!response.ok) {
    throw new Error(`API error: ${response.status}`);
  }

  return response.json();
}

async function login(email, password) {
  const response = await fetch(`${CONFIG.API_URL}/auth/login`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ email, password }),
  });

  if (!response.ok) {
    const error = await response.json();
    throw new Error(error.error || 'Login failed');
  }

  const data = await response.json();

  // Store tokens
  await chrome.storage.sync.set({
    token: data.accessToken,
    refreshToken: data.refreshToken,
    user: data.user,
  });

  return data;
}

async function logout() {
  const { token } = await chrome.storage.sync.get(['token']);

  if (token) {
    try {
      await fetch(`${CONFIG.API_URL}/auth/logout`, {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${token}`,
        },
      });
    } catch (error) {
      console.error('Logout API call failed:', error);
    }
  }

  await chrome.storage.sync.remove(['token', 'refreshToken', 'user']);
}

async function refreshToken() {
  const { refreshToken } = await chrome.storage.sync.get(['refreshToken']);

  if (!refreshToken) {
    throw new Error('No refresh token');
  }

  const response = await fetch(`${CONFIG.API_URL}/auth/refresh`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ refreshToken }),
  });

  if (!response.ok) {
    await logout();
    throw new Error('Token refresh failed');
  }

  const data = await response.json();

  await chrome.storage.sync.set({
    token: data.accessToken,
    refreshToken: data.refreshToken,
  });

  return data;
}

// ===========================================
// AI TOOLS API (Proxy for content scripts)
// ===========================================

async function rewriteText(text, style, language) {
  const { token } = await chrome.storage.sync.get(['token']);

  const headers = {
    'Content-Type': 'application/json',
  };

  if (token) {
    headers['Authorization'] = `Bearer ${token}`;
  }

  const response = await fetch(`${CONFIG.API_URL}/grammar/rewrite`, {
    method: 'POST',
    headers,
    body: JSON.stringify({ text, style, language }),
  });

  if (!response.ok) {
    const error = await response.json().catch(() => ({}));
    throw new Error(error.error || `API error: ${response.status}`);
  }

  return response.json();
}

async function adjustTone(text, targetTone, language) {
  const { token } = await chrome.storage.sync.get(['token']);

  console.log('[GrammarlyClone BG] adjustTone called:', { text: text.substring(0, 50), targetTone, language, hasToken: !!token });

  if (!token) {
    throw new Error('Faça login para usar o ajuste de tom');
  }

  const headers = {
    'Content-Type': 'application/json',
    'Authorization': `Bearer ${token}`,
  };

  const response = await fetch(`${CONFIG.API_URL}/grammar/tone`, {
    method: 'POST',
    headers,
    body: JSON.stringify({ text, targetTone, language }),
  });

  console.log('[GrammarlyClone BG] adjustTone response status:', response.status);

  if (!response.ok) {
    const error = await response.json().catch(() => ({}));
    console.error('[GrammarlyClone BG] adjustTone error:', error);
    throw new Error(error.error || error.message || `API error: ${response.status}`);
  }

  return response.json();
}

async function translateText(text, targetLanguage) {
  const { token } = await chrome.storage.sync.get(['token']);

  console.log('[GrammarlyClone BG] translateText called:', { text: text.substring(0, 50), targetLanguage, hasToken: !!token });

  const headers = {
    'Content-Type': 'application/json',
  };

  if (token) {
    headers['Authorization'] = `Bearer ${token}`;
  }

  const response = await fetch(`${CONFIG.API_URL}/grammar/translate`, {
    method: 'POST',
    headers,
    body: JSON.stringify({ text, targetLanguage }),
  });

  console.log('[GrammarlyClone BG] translateText response status:', response.status);

  if (!response.ok) {
    const error = await response.json().catch(() => ({}));
    console.error('[GrammarlyClone BG] translateText error:', error);
    throw new Error(error.error || error.message || `API error: ${response.status}`);
  }

  return response.json();
}

// ===========================================
// MESSAGE HANDLING
// ===========================================

chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
  switch (message.type) {
    case 'CHECK_GRAMMAR':
      checkGrammar(message.text, message.language)
        .then(result => sendResponse({ success: true, result }))
        .catch(error => sendResponse({ success: false, error: error.message }));
      return true;

    case 'REWRITE_TEXT':
      rewriteText(message.text, message.style, message.language)
        .then(result => sendResponse({ success: true, result }))
        .catch(error => sendResponse({ success: false, error: error.message }));
      return true;

    case 'ADJUST_TONE':
      adjustTone(message.text, message.targetTone, message.language)
        .then(result => sendResponse({ success: true, result }))
        .catch(error => sendResponse({ success: false, error: error.message }));
      return true;

    case 'TRANSLATE_TEXT':
      translateText(message.text, message.targetLanguage)
        .then(result => sendResponse({ success: true, result }))
        .catch(error => sendResponse({ success: false, error: error.message }));
      return true;

    case 'LOGIN':
      login(message.email, message.password)
        .then(result => sendResponse({ success: true, result }))
        .catch(error => sendResponse({ success: false, error: error.message }));
      return true;

    case 'LOGOUT':
      logout()
        .then(() => sendResponse({ success: true }))
        .catch(error => sendResponse({ success: false, error: error.message }));
      return true;

    case 'REFRESH_TOKEN':
      refreshToken()
        .then(result => sendResponse({ success: true, result }))
        .catch(error => sendResponse({ success: false, error: error.message }));
      return true;

    case 'GET_USER':
      chrome.storage.sync.get(['user', 'token'], (result) => {
        sendResponse({ user: result.user, isLoggedIn: !!result.token });
      });
      return true;

    case 'UPDATE_SETTINGS':
      chrome.storage.sync.set(message.settings, () => {
        // Notify all tabs
        chrome.tabs.query({}, (tabs) => {
          tabs.forEach(tab => {
            chrome.tabs.sendMessage(tab.id, {
              type: 'SETTINGS_UPDATED',
              settings: message.settings,
            }).catch(() => {});
          });
        });
        sendResponse({ success: true });
      });
      return true;
  }
});

// ===========================================
// BADGE UPDATES
// ===========================================

function updateBadge(count, tabId) {
  const text = count > 0 ? count.toString() : '';
  const color = count > 0 ? '#ef4444' : '#15803d';

  chrome.action.setBadgeText({ text, tabId });
  chrome.action.setBadgeBackgroundColor({ color, tabId });
}

// Listen for correction counts from content scripts
chrome.runtime.onMessage.addListener((message, sender) => {
  if (message.type === 'UPDATE_BADGE' && sender.tab) {
    updateBadge(message.count, sender.tab.id);
  }
});

// ===========================================
// PERIODIC TOKEN REFRESH
// ===========================================

// Refresh token every 6 hours
setInterval(async () => {
  const { token } = await chrome.storage.sync.get(['token']);
  if (token) {
    try {
      await refreshToken();
      console.log('[GrammarlyClone] Token refreshed');
    } catch (error) {
      console.error('[GrammarlyClone] Token refresh failed:', error);
    }
  }
}, 6 * 60 * 60 * 1000);
