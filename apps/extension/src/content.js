// ===========================================
// GRAMMARLY CLONE - CONTENT SCRIPT
// ===========================================

(function () {
  'use strict';

  // Configuration
  const CONFIG = {
    DEBOUNCE_MS: 1000,
    MIN_TEXT_LENGTH: 10,
    MAX_TEXT_LENGTH: 5000,
  };

  // State
  let state = {
    enabled: true,
    language: 'PT_BR',
    token: null,
    corrections: [],
    activeElement: null,
    widget: null,
    aiMenu: null,
    selectedText: '',
    selectionRange: null,
    selectionStart: null,
    selectionEnd: null,
  };

  // ===========================================
  // UTILITIES
  // ===========================================

  function debounce(func, wait) {
    let timeout;
    return function executedFunction(...args) {
      const later = () => {
        clearTimeout(timeout);
        func(...args);
      };
      clearTimeout(timeout);
      timeout = setTimeout(later, wait);
    };
  }

  function getTextFromElement(element) {
    if (element.isContentEditable) {
      return element.innerText || element.textContent || '';
    }
    return element.value || '';
  }

  function setTextInElement(element, text) {
    if (element.isContentEditable) {
      element.innerText = text;
    } else {
      element.value = text;
    }
  }

  // ===========================================
  // API COMMUNICATION (via Background Script to avoid CORS)
  // ===========================================

  async function checkGrammar(text) {
    try {
      const response = await chrome.runtime.sendMessage({
        type: 'CHECK_GRAMMAR',
        text,
        language: state.language,
      });
      if (response.success) {
        return response.result;
      }
      console.error('[GrammarlyClone] API error:', response.error);
      return null;
    } catch (error) {
      console.error('[GrammarlyClone] API error:', error);
      return null;
    }
  }

  async function rewriteText(text, style) {
    try {
      const response = await chrome.runtime.sendMessage({
        type: 'REWRITE_TEXT',
        text,
        style,
        language: state.language,
      });
      if (response.success) {
        return response.result;
      }
      console.error('[GrammarlyClone] API error:', response.error);
      return null;
    } catch (error) {
      console.error('[GrammarlyClone] API error:', error);
      return null;
    }
  }

  async function adjustTone(text, targetTone) {
    try {
      const response = await chrome.runtime.sendMessage({
        type: 'ADJUST_TONE',
        text,
        targetTone,
        language: state.language,
      });
      if (response.success) {
        return response.result;
      }
      console.error('[GrammarlyClone] API error:', response.error);
      return null;
    } catch (error) {
      console.error('[GrammarlyClone] API error:', error);
      return null;
    }
  }

  async function translateText(text, targetLanguage) {
    try {
      const response = await chrome.runtime.sendMessage({
        type: 'TRANSLATE_TEXT',
        text,
        targetLanguage,
      });
      if (response.success) {
        return response.result;
      }
      console.error('[GrammarlyClone] API error:', response.error);
      return null;
    } catch (error) {
      console.error('[GrammarlyClone] API error:', error);
      return null;
    }
  }

  // ===========================================
  // WIDGET UI
  // ===========================================

  function createWidget() {
    const widget = document.createElement('div');
    widget.id = 'grammarly-clone-widget';
    widget.innerHTML = `
      <div class="gc-widget-container">
        <div class="gc-widget-header">
          <span class="gc-logo">G</span>
          <span class="gc-status">Verificando...</span>
          <button class="gc-close">&times;</button>
        </div>
        <div class="gc-widget-body">
          <div class="gc-corrections-list"></div>
        </div>
        <div class="gc-widget-footer">
          <span class="gc-count">0 correções</span>
          <button class="gc-settings">⚙️</button>
        </div>
      </div>
    `;

    // Create Shadow DOM for style isolation
    const shadow = widget.attachShadow({ mode: 'open' });

    const style = document.createElement('style');
    style.textContent = getWidgetStyles();

    const container = document.createElement('div');
    container.innerHTML = widget.innerHTML;

    shadow.appendChild(style);
    shadow.appendChild(container);

    // Event listeners
    shadow.querySelector('.gc-close').addEventListener('click', () => {
      widget.style.display = 'none';
    });

    document.body.appendChild(widget);
    return widget;
  }

  function getWidgetStyles() {
    return `
      .gc-widget-container {
        position: fixed;
        bottom: 20px;
        right: 20px;
        width: 320px;
        max-height: 400px;
        background: white;
        border-radius: 12px;
        box-shadow: 0 4px 20px rgba(0, 0, 0, 0.15);
        font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
        z-index: 2147483647;
        overflow: hidden;
      }

      .gc-widget-header {
        display: flex;
        align-items: center;
        padding: 12px 16px;
        background: linear-gradient(135deg, #15803d 0%, #166534 100%);
        color: white;
      }

      .gc-logo {
        width: 28px;
        height: 28px;
        background: white;
        color: #15803d;
        border-radius: 6px;
        display: flex;
        align-items: center;
        justify-content: center;
        font-weight: bold;
        font-size: 16px;
        margin-right: 10px;
      }

      .gc-status {
        flex: 1;
        font-size: 14px;
        font-weight: 500;
      }

      .gc-close {
        background: none;
        border: none;
        color: white;
        font-size: 20px;
        cursor: pointer;
        opacity: 0.8;
        transition: opacity 0.2s;
      }

      .gc-close:hover {
        opacity: 1;
      }

      .gc-widget-body {
        max-height: 280px;
        overflow-y: auto;
        padding: 8px;
      }

      .gc-corrections-list {
        display: flex;
        flex-direction: column;
        gap: 8px;
      }

      .gc-correction-item {
        padding: 12px;
        background: #f9fafb;
        border-radius: 8px;
        border-left: 3px solid #ef4444;
        cursor: pointer;
        transition: background 0.2s;
      }

      .gc-correction-item:hover {
        background: #f3f4f6;
      }

      .gc-correction-item.warning {
        border-left-color: #f59e0b;
      }

      .gc-correction-item.suggestion {
        border-left-color: #3b82f6;
      }

      .gc-correction-item.info {
        border-left-color: #6b7280;
      }

      .gc-correction-type {
        font-size: 10px;
        text-transform: uppercase;
        color: #6b7280;
        font-weight: 600;
        margin-bottom: 4px;
      }

      .gc-correction-original {
        font-size: 13px;
        color: #ef4444;
        text-decoration: line-through;
        margin-bottom: 4px;
      }

      .gc-correction-suggestion {
        font-size: 13px;
        color: #15803d;
        font-weight: 500;
        margin-bottom: 4px;
      }

      .gc-correction-explanation {
        font-size: 12px;
        color: #6b7280;
      }

      .gc-correction-actions {
        display: flex;
        gap: 8px;
        margin-top: 8px;
      }

      .gc-btn {
        padding: 6px 12px;
        border-radius: 6px;
        font-size: 12px;
        font-weight: 500;
        cursor: pointer;
        border: none;
        transition: all 0.2s;
      }

      .gc-btn-accept {
        background: #15803d;
        color: white;
      }

      .gc-btn-accept:hover {
        background: #166534;
      }

      .gc-btn-ignore {
        background: #e5e7eb;
        color: #374151;
      }

      .gc-btn-ignore:hover {
        background: #d1d5db;
      }

      .gc-widget-footer {
        display: flex;
        align-items: center;
        justify-content: space-between;
        padding: 10px 16px;
        border-top: 1px solid #e5e7eb;
        background: #f9fafb;
      }

      .gc-count {
        font-size: 12px;
        color: #6b7280;
      }

      .gc-settings {
        background: none;
        border: none;
        cursor: pointer;
        font-size: 16px;
      }

      .gc-empty {
        padding: 24px;
        text-align: center;
        color: #6b7280;
      }

      .gc-empty-icon {
        font-size: 32px;
        margin-bottom: 8px;
      }

      .gc-loading {
        display: flex;
        align-items: center;
        justify-content: center;
        padding: 24px;
      }

      .gc-spinner {
        width: 24px;
        height: 24px;
        border: 2px solid #e5e7eb;
        border-top-color: #15803d;
        border-radius: 50%;
        animation: gc-spin 0.8s linear infinite;
      }

      @keyframes gc-spin {
        to { transform: rotate(360deg); }
      }
    `;
  }

  // ===========================================
  // AI TOOLS MENU
  // ===========================================

  const AI_OPTIONS = [
    { id: 'better', label: 'Melhorar', icon: '✨', desc: 'Melhora a clareza e elegância' },
    { id: 'simplified', label: 'Simplificar', icon: '🪄', desc: 'Torna mais fácil de entender' },
    { id: 'shorter', label: 'Encurtar', icon: '📉', desc: 'Reduz sem perder o sentido' },
    { id: 'longer', label: 'Expandir', icon: '📈', desc: 'Adiciona mais detalhes' },
    { id: 'tone', label: 'Ajustar Tom', icon: '💬', desc: 'Muda o tom da mensagem', hasSubmenu: true },
    { id: 'translate', label: 'Traduzir', icon: '🌐', desc: 'Traduz para outro idioma', hasSubmenu: true },
  ];

  const TONE_OPTIONS = [
    { code: 'FORMAL', label: 'Formal', emoji: '👔', desc: 'Profissional e respeitoso' },
    { code: 'INFORMAL', label: 'Informal', emoji: '😊', desc: 'Casual e descontraído' },
    { code: 'CONFIDENT', label: 'Confiante', emoji: '💪', desc: 'Assertivo e seguro' },
    { code: 'FRIENDLY', label: 'Amigável', emoji: '🤝', desc: 'Caloroso e acolhedor' },
    { code: 'PROFESSIONAL', label: 'Profissional', emoji: '💼', desc: 'Corporativo e sério' },
    { code: 'DIRECT', label: 'Direto', emoji: '🎯', desc: 'Objetivo e sem rodeios' },
    { code: 'DIPLOMATIC', label: 'Diplomático', emoji: '🕊️', desc: 'Cuidadoso e ponderado' },
  ];

  const LANGUAGE_OPTIONS = [
    { code: 'PT_BR', label: 'Português (BR)', flag: '🇧🇷' },
    { code: 'EN_US', label: 'English (US)', flag: '🇺🇸' },
    { code: 'EN_GB', label: 'English (UK)', flag: '🇬🇧' },
    { code: 'ES_ES', label: 'Español (ES)', flag: '🇪🇸' },
    { code: 'ES_MX', label: 'Español (MX)', flag: '🇲🇽' },
  ];

  function createAIMenu() {
    const menu = document.createElement('div');
    menu.id = 'grammarly-clone-ai-menu';

    const shadow = menu.attachShadow({ mode: 'open' });

    const style = document.createElement('style');
    style.textContent = getAIMenuStyles();

    const container = document.createElement('div');
    container.className = 'gc-ai-menu';
    container.innerHTML = `
      <div class="gc-ai-header">
        <div class="gc-ai-logo">✨</div>
        <span class="gc-ai-title">Assistente IA</span>
        <button class="gc-ai-close">&times;</button>
      </div>
      <div class="gc-ai-result"></div>
      <div class="gc-ai-options"></div>
      <div class="gc-ai-submenu"></div>
    `;

    shadow.appendChild(style);
    shadow.appendChild(container);

    // Event listeners
    shadow.querySelector('.gc-ai-close').addEventListener('click', hideAIMenu);

    document.body.appendChild(menu);
    return menu;
  }

  function getAIMenuStyles() {
    return `
      .gc-ai-menu {
        position: fixed;
        width: 280px;
        background: white;
        border-radius: 12px;
        box-shadow: 0 4px 24px rgba(0, 0, 0, 0.18);
        font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
        z-index: 2147483647;
        overflow: hidden;
      }

      .gc-ai-header {
        display: flex;
        align-items: center;
        padding: 10px 12px;
        border-bottom: 1px solid #e5e7eb;
        background: linear-gradient(135deg, #8b5cf6 0%, #6366f1 100%);
        color: white;
      }

      .gc-ai-logo {
        width: 24px;
        height: 24px;
        background: white;
        border-radius: 6px;
        display: flex;
        align-items: center;
        justify-content: center;
        font-size: 14px;
        margin-right: 8px;
      }

      .gc-ai-title {
        flex: 1;
        font-size: 13px;
        font-weight: 600;
      }

      .gc-ai-close {
        background: none;
        border: none;
        color: white;
        font-size: 18px;
        cursor: pointer;
        opacity: 0.8;
        padding: 0 4px;
      }

      .gc-ai-close:hover {
        opacity: 1;
      }

      .gc-ai-result {
        display: none;
        padding: 12px;
        border-bottom: 1px solid #e5e7eb;
      }

      .gc-ai-result.visible {
        display: block;
      }

      .gc-ai-result-text {
        font-size: 13px;
        color: #374151;
        line-height: 1.5;
        margin-bottom: 10px;
      }

      .gc-ai-result-actions {
        display: flex;
        gap: 8px;
      }

      .gc-ai-btn {
        flex: 1;
        padding: 8px;
        border-radius: 6px;
        font-size: 12px;
        font-weight: 500;
        cursor: pointer;
        border: none;
        display: flex;
        align-items: center;
        justify-content: center;
        gap: 4px;
      }

      .gc-ai-btn-accept {
        background: #8b5cf6;
        color: white;
      }

      .gc-ai-btn-accept:hover {
        background: #7c3aed;
      }

      .gc-ai-btn-discard {
        background: #e5e7eb;
        color: #374151;
      }

      .gc-ai-btn-discard:hover {
        background: #d1d5db;
      }

      .gc-ai-loading {
        display: flex;
        align-items: center;
        gap: 8px;
        font-size: 13px;
        color: #6b7280;
      }

      .gc-ai-spinner {
        width: 16px;
        height: 16px;
        border: 2px solid #e5e7eb;
        border-top-color: #8b5cf6;
        border-radius: 50%;
        animation: gc-spin 0.8s linear infinite;
      }

      .gc-ai-options {
        padding: 6px;
      }

      .gc-ai-option {
        display: flex;
        align-items: center;
        gap: 10px;
        padding: 10px;
        border-radius: 8px;
        cursor: pointer;
        transition: background 0.15s;
      }

      .gc-ai-option:hover {
        background: #f3f4f6;
      }

      .gc-ai-option.active {
        background: #f3e8ff;
      }

      .gc-ai-option-icon {
        font-size: 16px;
      }

      .gc-ai-option-content {
        flex: 1;
      }

      .gc-ai-option-label {
        font-size: 13px;
        font-weight: 500;
        color: #111827;
      }

      .gc-ai-option-desc {
        font-size: 11px;
        color: #6b7280;
      }

      .gc-ai-option-arrow {
        font-size: 12px;
        color: #9ca3af;
      }

      .gc-ai-submenu {
        display: none;
        position: absolute;
        left: 100%;
        top: 0;
        margin-left: 4px;
        width: 200px;
        background: white;
        border-radius: 8px;
        box-shadow: 0 4px 16px rgba(0, 0, 0, 0.15);
        padding: 4px;
      }

      .gc-ai-submenu.visible {
        display: block;
      }

      .gc-ai-submenu-item {
        display: flex;
        align-items: center;
        gap: 8px;
        padding: 8px 10px;
        border-radius: 6px;
        cursor: pointer;
        transition: background 0.15s;
      }

      .gc-ai-submenu-item:hover {
        background: #f3f4f6;
      }

      .gc-ai-submenu-emoji {
        font-size: 14px;
      }

      .gc-ai-submenu-content {
        flex: 1;
      }

      .gc-ai-submenu-label {
        font-size: 12px;
        font-weight: 500;
        color: #111827;
      }

      .gc-ai-submenu-desc {
        font-size: 10px;
        color: #6b7280;
      }

      @keyframes gc-spin {
        to { transform: rotate(360deg); }
      }
    `;
  }

  function showAIMenu(x, y) {
    if (!state.aiMenu) {
      state.aiMenu = createAIMenu();
    }

    const shadow = state.aiMenu.shadowRoot;
    const menu = shadow.querySelector('.gc-ai-menu');
    const options = shadow.querySelector('.gc-ai-options');
    const result = shadow.querySelector('.gc-ai-result');
    const submenu = shadow.querySelector('.gc-ai-submenu');

    // Reset state
    result.classList.remove('visible');
    result.innerHTML = '';
    submenu.classList.remove('visible');

    // Render options
    options.innerHTML = AI_OPTIONS.map(opt => `
      <div class="gc-ai-option" data-id="${opt.id}" ${opt.hasSubmenu ? 'data-submenu="true"' : ''}>
        <span class="gc-ai-option-icon">${opt.icon}</span>
        <div class="gc-ai-option-content">
          <div class="gc-ai-option-label">${opt.label}</div>
          <div class="gc-ai-option-desc">${opt.desc}</div>
        </div>
        ${opt.hasSubmenu ? '<span class="gc-ai-option-arrow">›</span>' : ''}
      </div>
    `).join('');

    // Event handlers
    options.querySelectorAll('.gc-ai-option').forEach(opt => {
      opt.addEventListener('click', () => handleAIOptionClick(opt.dataset.id));
      opt.addEventListener('mouseenter', () => {
        if (opt.dataset.submenu) {
          showSubmenu(opt.dataset.id, opt);
        } else {
          submenu.classList.remove('visible');
        }
      });
    });

    // Position menu
    const menuWidth = 280;
    const menuHeight = 320;
    const posX = Math.min(x, window.innerWidth - menuWidth - 10);
    const posY = Math.min(y + 10, window.innerHeight - menuHeight - 10);

    menu.style.left = `${posX}px`;
    menu.style.top = `${posY}px`;

    state.aiMenu.style.display = 'block';
  }

  function hideAIMenu() {
    if (state.aiMenu) {
      state.aiMenu.style.display = 'none';
    }
  }

  function showSubmenu(type, parentElement) {
    const shadow = state.aiMenu.shadowRoot;
    const submenu = shadow.querySelector('.gc-ai-submenu');

    let items = [];
    if (type === 'tone') {
      items = TONE_OPTIONS.map(t => `
        <div class="gc-ai-submenu-item" data-type="tone" data-value="${t.code}">
          <span class="gc-ai-submenu-emoji">${t.emoji}</span>
          <div class="gc-ai-submenu-content">
            <div class="gc-ai-submenu-label">${t.label}</div>
            <div class="gc-ai-submenu-desc">${t.desc}</div>
          </div>
        </div>
      `).join('');
    } else if (type === 'translate') {
      items = LANGUAGE_OPTIONS.map(l => `
          <div class="gc-ai-submenu-item" data-type="translate" data-value="${l.code}">
            <span class="gc-ai-submenu-emoji">${l.flag}</span>
            <div class="gc-ai-submenu-content">
              <div class="gc-ai-submenu-label">${l.label}</div>
            </div>
          </div>
        `).join('');
    }

    submenu.innerHTML = items;
    submenu.classList.add('visible');

    // Position submenu relative to parent
    const parentRect = parentElement.getBoundingClientRect();
    const menuRect = shadow.querySelector('.gc-ai-menu').getBoundingClientRect();
    submenu.style.top = `${parentRect.top - menuRect.top}px`;

    // Event handlers
    submenu.querySelectorAll('.gc-ai-submenu-item').forEach(item => {
      item.addEventListener('click', () => {
        const type = item.dataset.type;
        const value = item.dataset.value;
        if (type === 'tone') {
          handleToneAdjust(value);
        } else if (type === 'translate') {
          handleTranslate(value);
        }
      });
    });
  }

  async function handleAIOptionClick(optionId) {
    if (optionId === 'tone' || optionId === 'translate') {
      return; // Handled by submenu
    }

    const shadow = state.aiMenu.shadowRoot;
    const result = shadow.querySelector('.gc-ai-result');
    const submenu = shadow.querySelector('.gc-ai-submenu');

    submenu.classList.remove('visible');
    result.classList.add('visible');
    result.innerHTML = `
      <div class="gc-ai-loading">
        <div class="gc-ai-spinner"></div>
        <span>Processando...</span>
      </div>
    `;

    const response = await rewriteText(state.selectedText, optionId);

    if (response && response.rewritten) {
      showAIResult(response.rewritten);
    } else {
      result.innerHTML = `<div class="gc-ai-result-text" style="color: #ef4444;">Erro ao processar. Tente novamente.</div>`;
    }
  }

  async function handleToneAdjust(tone) {
    const shadow = state.aiMenu.shadowRoot;
    const result = shadow.querySelector('.gc-ai-result');
    const submenu = shadow.querySelector('.gc-ai-submenu');

    submenu.classList.remove('visible');
    result.classList.add('visible');
    result.innerHTML = `
      <div class="gc-ai-loading">
        <div class="gc-ai-spinner"></div>
        <span>Ajustando tom...</span>
      </div>
    `;

    console.log('[GrammarlyClone] Adjusting tone:', { text: state.selectedText, tone, language: state.language });
    const response = await adjustTone(state.selectedText, tone);
    console.log('[GrammarlyClone] Tone response:', response);

    if (response && response.adjusted) {
      showAIResult(response.adjusted);
    } else {
      const errorMsg = state.token ? 'Erro ao processar. Tente novamente.' : 'Faça login para usar o ajuste de tom.';
      result.innerHTML = `<div class="gc-ai-result-text" style="color: #ef4444;">${errorMsg}</div>`;
    }
  }

  async function handleTranslate(targetLanguage) {
    const shadow = state.aiMenu.shadowRoot;
    const result = shadow.querySelector('.gc-ai-result');
    const submenu = shadow.querySelector('.gc-ai-submenu');

    submenu.classList.remove('visible');
    result.classList.add('visible');
    result.innerHTML = `
      <div class="gc-ai-loading">
        <div class="gc-ai-spinner"></div>
        <span>Traduzindo...</span>
      </div>
    `;

    console.log('[GrammarlyClone] Translating:', { text: state.selectedText, targetLanguage });
    const response = await translateText(state.selectedText, targetLanguage);
    console.log('[GrammarlyClone] Translate response:', response);

    if (response && response.translated) {
      showAIResult(response.translated);
    } else {
      result.innerHTML = `<div class="gc-ai-result-text" style="color: #ef4444;">Erro ao processar. Tente novamente.</div>`;
    }
  }

  function showAIResult(text) {
    const shadow = state.aiMenu.shadowRoot;
    const result = shadow.querySelector('.gc-ai-result');

    result.innerHTML = `
      <div class="gc-ai-result-text">${escapeHtml(text)}</div>
      <div class="gc-ai-result-actions">
        <button class="gc-ai-btn gc-ai-btn-discard">✕ Descartar</button>
        <button class="gc-ai-btn gc-ai-btn-accept">✓ Substituir</button>
      </div>
    `;

    result.querySelector('.gc-ai-btn-discard').addEventListener('click', () => {
      result.classList.remove('visible');
      result.innerHTML = '';
    });

    result.querySelector('.gc-ai-btn-accept').addEventListener('click', () => {
      replaceSelectedText(text);
      hideAIMenu();
    });
  }

  function replaceSelectedText(newText) {
    console.log('[GrammarlyClone] replaceSelectedText called:', {
      newText: newText.substring(0, 50),
      activeElement: state.activeElement?.tagName,
      isContentEditable: state.activeElement?.isContentEditable,
      selectionStart: state.selectionStart,
      selectionEnd: state.selectionEnd,
      hasSelectionRange: !!state.selectionRange,
    });

    try {
      const element = state.activeElement;

      // For textarea/input elements, use stored selection positions
      if (element && (element.tagName === 'TEXTAREA' || element.tagName === 'INPUT')) {
        const start = state.selectionStart;
        const end = state.selectionEnd;
        console.log('[GrammarlyClone] Textarea/Input detected:', { start, end, valueLength: element.value?.length });
        if (start !== null && end !== null) {
          const text = element.value;
          element.value = text.substring(0, start) + newText + text.substring(end);
          element.selectionStart = element.selectionEnd = start + newText.length;
          element.focus();
          element.dispatchEvent(new Event('input', { bubbles: true }));
          console.log('[GrammarlyClone] Textarea/Input replacement successful');
          return true;
        }
      }

      // For contenteditable elements, restore selection and use execCommand
      if (element && element.isContentEditable && state.selectionRange) {
        console.log('[GrammarlyClone] ContentEditable detected');
        element.focus();

        // Restore the selection
        const selection = window.getSelection();
        selection.removeAllRanges();
        selection.addRange(state.selectionRange);

        // Use execCommand to replace
        document.execCommand('insertText', false, newText);
        element.dispatchEvent(new Event('input', { bubbles: true }));
        console.log('[GrammarlyClone] ContentEditable replacement successful');
        return true;
      }

      // For regular page content, use stored range directly
      if (state.selectionRange) {
        console.log('[GrammarlyClone] Regular content detected, trying range replacement');
        try {
          const range = state.selectionRange;

          // Check if range is still valid
          if (range.startContainer && range.startContainer.parentNode) {
            range.deleteContents();
            range.insertNode(document.createTextNode(newText));

            // Clean up selection
            const selection = window.getSelection();
            selection.removeAllRanges();
            console.log('[GrammarlyClone] Range replacement successful');
            return true;
          }
        } catch (rangeError) {
          console.warn('[GrammarlyClone] Range replacement failed:', rangeError);
        }
      }

      // Fallback: copy to clipboard and notify user
      console.log('[GrammarlyClone] Fallback: copying to clipboard');
      navigator.clipboard.writeText(newText).then(() => {
        console.log('[GrammarlyClone] Text copied to clipboard (use Ctrl+V to paste)');
      });
      return false;
    } catch (error) {
      console.error('[GrammarlyClone] Replace failed:', error);
      // Fallback: copy to clipboard
      navigator.clipboard.writeText(newText).catch(() => { });
      return false;
    }
  }

  function handleTextSelection(e) {
    if (!state.enabled) return;

    // Don't update selection if AI menu is visible (preserves selection for replacement)
    if (state.aiMenu && state.aiMenu.style.display !== 'none') {
      // Check if click is inside the AI menu (including shadow DOM)
      const path = e.composedPath ? e.composedPath() : [];
      const isInsideMenu = path.some(el => el === state.aiMenu || (el.id && el.id === 'grammarly-clone-ai-menu'));
      if (isInsideMenu) return;
      // Even if not inside menu, don't update selection while menu is open
      return;
    }

    const selection = window.getSelection();
    const text = selection.toString().trim();

    if (text.length >= 3) {
      state.selectedText = text;

      // Store the selection range for later replacement
      const range = selection.getRangeAt(0);
      state.selectionRange = range.cloneRange();

      // Store active element and selection positions for input/textarea
      const activeEl = document.activeElement;
      if (activeEl && (activeEl.tagName === 'TEXTAREA' || activeEl.tagName === 'INPUT')) {
        state.activeElement = activeEl;
        state.selectionStart = activeEl.selectionStart;
        state.selectionEnd = activeEl.selectionEnd;
      } else if (activeEl && activeEl.isContentEditable) {
        state.activeElement = activeEl;
      } else {
        // For selections in regular page content
        state.activeElement = range.commonAncestorContainer.parentElement;
      }

      // Get position for menu (use mouse coordinates if available, fallback to range rect)
      const rect = range.getBoundingClientRect();
      const posX = e && e.clientX !== undefined ? e.clientX : rect.left;
      const posY = e && e.clientY !== undefined ? e.clientY : rect.bottom;

      showAIMenu(posX, posY);
    } else {
      hideAIMenu();
    }
  }

  function updateWidget(corrections) {
    if (!state.widget) {
      state.widget = createWidget();
    }

    const shadow = state.widget.shadowRoot;
    const list = shadow.querySelector('.gc-corrections-list');
    const status = shadow.querySelector('.gc-status');
    const count = shadow.querySelector('.gc-count');

    state.corrections = corrections;

    if (corrections.length === 0) {
      list.innerHTML = `
        <div class="gc-empty">
          <div class="gc-empty-icon">✨</div>
          <div>Nenhum problema encontrado!</div>
        </div>
      `;
      status.textContent = 'Tudo certo!';
      count.textContent = '0 correções';
    } else {
      list.innerHTML = corrections.map((c, index) => `
        <div class="gc-correction-item ${c.severity.toLowerCase()}" data-index="${index}">
          <div class="gc-correction-type">${getTypeLabel(c.type)}</div>
          <div class="gc-correction-original">${escapeHtml(c.originalText)}</div>
          <div class="gc-correction-suggestion">${escapeHtml(c.suggestion)}</div>
          ${c.explanation ? `<div class="gc-correction-explanation">${escapeHtml(c.explanation)}</div>` : ''}
          <div class="gc-correction-actions">
            <button class="gc-btn gc-btn-accept" data-action="accept" data-index="${index}">Aceitar</button>
            <button class="gc-btn gc-btn-ignore" data-action="ignore" data-index="${index}">Ignorar</button>
          </div>
        </div>
      `).join('');

      status.textContent = `${corrections.length} ${corrections.length === 1 ? 'problema' : 'problemas'}`;
      count.textContent = `${corrections.length} ${corrections.length === 1 ? 'correção' : 'correções'}`;

      // Add click handlers
      list.querySelectorAll('.gc-btn').forEach(btn => {
        btn.addEventListener('click', (e) => {
          const action = e.target.dataset.action;
          const index = parseInt(e.target.dataset.index);
          handleCorrectionAction(action, index);
        });
      });
    }

    state.widget.style.display = 'block';
  }

  function getTypeLabel(type) {
    const labels = {
      GRAMMAR: 'Gramática',
      SPELLING: 'Ortografia',
      PUNCTUATION: 'Pontuação',
      STYLE: 'Estilo',
      TONE: 'Tom',
      CLARITY: 'Clareza',
      CONCISENESS: 'Concisão',
    };
    return labels[type] || type;
  }

  function escapeHtml(text) {
    const div = document.createElement('div');
    div.textContent = text;
    return div.innerHTML;
  }

  function handleCorrectionAction(action, index) {
    const correction = state.corrections[index];
    if (!correction || !state.activeElement) return;

    if (action === 'accept') {
      const text = getTextFromElement(state.activeElement);
      const newText = text.substring(0, correction.startOffset) +
        correction.suggestion +
        text.substring(correction.endOffset);
      setTextInElement(state.activeElement, newText);

      // Trigger input event for frameworks
      state.activeElement.dispatchEvent(new Event('input', { bubbles: true }));
    }

    // Remove correction from list
    state.corrections.splice(index, 1);
    updateWidget(state.corrections);
  }

  // ===========================================
  // INLINE HIGHLIGHTS
  // ===========================================

  function createHighlightOverlay(element, corrections) {
    // Remove existing overlay
    const existingOverlay = element.parentElement?.querySelector('.gc-highlight-overlay');
    if (existingOverlay) {
      existingOverlay.remove();
    }

    if (corrections.length === 0) return;

    // For contenteditable elements, we can use DOM manipulation
    if (element.isContentEditable) {
      highlightContentEditable(element, corrections);
    }
    // For input/textarea, we create an overlay
    else if (element.tagName === 'TEXTAREA' || element.tagName === 'INPUT') {
      // Create overlay for textarea (simplified version)
      const rect = element.getBoundingClientRect();
      const overlay = document.createElement('div');
      overlay.className = 'gc-highlight-overlay';
      overlay.style.cssText = `
        position: absolute;
        top: ${rect.top + window.scrollY}px;
        left: ${rect.left + window.scrollX}px;
        width: ${rect.width}px;
        height: ${rect.height}px;
        pointer-events: none;
        z-index: 2147483646;
      `;
      document.body.appendChild(overlay);
    }
  }

  function highlightContentEditable(element, corrections) {
    // Store original HTML
    const originalHtml = element.innerHTML;

    // Sort corrections by offset (reverse order for safe replacement)
    const sorted = [...corrections].sort((a, b) => b.startOffset - a.startOffset);

    let html = element.innerHTML;

    sorted.forEach(correction => {
      const severityColor = {
        ERROR: '#fee2e2',
        WARNING: '#fef3c7',
        SUGGESTION: '#dbeafe',
        INFO: '#f3f4f6',
      }[correction.severity] || '#fee2e2';

      const underlineColor = {
        ERROR: '#ef4444',
        WARNING: '#f59e0b',
        SUGGESTION: '#3b82f6',
        INFO: '#6b7280',
      }[correction.severity] || '#ef4444';

      // This is a simplified approach - in production, you'd use Range API
      const text = correction.originalText;
      const replacement = `<span class="gc-highlight" style="background: ${severityColor}; border-bottom: 2px wavy ${underlineColor}; cursor: pointer;" data-correction="${encodeURIComponent(JSON.stringify(correction))}">${text}</span>`;

      html = html.replace(text, replacement);
    });

    element.innerHTML = html;
  }

  // ===========================================
  // TEXT FIELD DETECTION
  // ===========================================

  function isEditableElement(element) {
    if (!element) return false;

    const tagName = element.tagName?.toLowerCase();

    // Check for input/textarea
    if (tagName === 'textarea') return true;
    if (tagName === 'input') {
      const type = element.type?.toLowerCase();
      return ['text', 'search', 'email', 'url'].includes(type);
    }

    // Check for contenteditable
    if (element.isContentEditable) return true;
    if (element.getAttribute('contenteditable') === 'true') return true;

    // Check for rich text editors
    if (element.classList.contains('ql-editor')) return true; // Quill
    if (element.classList.contains('ProseMirror')) return true; // ProseMirror
    if (element.classList.contains('tox-edit-area')) return true; // TinyMCE
    if (element.classList.contains('cke_editable')) return true; // CKEditor

    return false;
  }

  function attachToElement(element) {
    if (element.dataset.grammarlyCloneAttached) return;
    element.dataset.grammarlyCloneAttached = 'true';

    const debouncedCheck = debounce(async () => {
      if (!state.enabled) return;

      const text = getTextFromElement(element);

      if (text.length < CONFIG.MIN_TEXT_LENGTH) {
        if (state.widget) {
          state.widget.style.display = 'none';
        }
        return;
      }

      if (text.length > CONFIG.MAX_TEXT_LENGTH) {
        console.warn('[GrammarlyClone] Text too long, truncating');
      }

      state.activeElement = element;

      // Show loading state
      if (state.widget) {
        const shadow = state.widget.shadowRoot;
        shadow.querySelector('.gc-status').textContent = 'Verificando...';
        shadow.querySelector('.gc-corrections-list').innerHTML = `
          <div class="gc-loading"><div class="gc-spinner"></div></div>
        `;
        state.widget.style.display = 'block';
      }

      const result = await checkGrammar(text.substring(0, CONFIG.MAX_TEXT_LENGTH));

      if (result && result.corrections) {
        updateWidget(result.corrections);
        createHighlightOverlay(element, result.corrections);
      }
    }, CONFIG.DEBOUNCE_MS);

    element.addEventListener('input', debouncedCheck);
    element.addEventListener('focus', () => {
      state.activeElement = element;
    });
  }

  // ===========================================
  // INITIALIZATION
  // ===========================================

  function init() {
    console.log('[GrammarlyClone] Initializing...');

    // Load settings from storage
    if (typeof chrome !== 'undefined' && chrome.storage) {
      chrome.storage.sync.get(['enabled', 'language', 'token'], (result) => {
        state.enabled = result.enabled !== false;
        state.language = result.language || 'PT_BR';
        state.token = result.token || null;
      });
    }

    // Find and attach to existing text fields
    document.querySelectorAll('textarea, input[type="text"], input[type="search"], [contenteditable="true"]').forEach(attachToElement);

    // Watch for new elements
    const observer = new MutationObserver((mutations) => {
      mutations.forEach((mutation) => {
        mutation.addedNodes.forEach((node) => {
          if (node.nodeType === Node.ELEMENT_NODE) {
            if (isEditableElement(node)) {
              attachToElement(node);
            }
            node.querySelectorAll?.('textarea, input[type="text"], input[type="search"], [contenteditable="true"]').forEach(attachToElement);
          }
        });
      });
    });

    observer.observe(document.body, {
      childList: true,
      subtree: true,
    });

    // Listen for right-click to show AI menu
    document.addEventListener('contextmenu', (e) => {
      if (!state.enabled) return;

      const selection = window.getSelection();
      const text = selection.toString().trim();

      if (text.length >= 3) {
        e.preventDefault(); // Prevent default context menu
        handleTextSelection(e);
      }
    });

    // Hide AI menu on click
    document.addEventListener('mousedown', (e) => {
      if (state.aiMenu && state.aiMenu.style.display !== 'none') {
        const path = e.composedPath ? e.composedPath() : [];
        const isInsideMenu = path.some(el => el === state.aiMenu || (el.id && el.id === 'grammarly-clone-ai-menu'));

        if (!isInsideMenu) {
          hideAIMenu();
        }
      }
    });

    // Listen for messages from popup/background
    if (typeof chrome !== 'undefined' && chrome.runtime) {
      chrome.runtime.onMessage.addListener((message, sender, sendResponse) => {
        if (message.type === 'TOGGLE_ENABLED') {
          state.enabled = message.enabled;
          if (!state.enabled && state.widget) {
            state.widget.style.display = 'none';
          }
        }
        if (message.type === 'SET_LANGUAGE') {
          state.language = message.language;
        }
        if (message.type === 'SET_TOKEN') {
          state.token = message.token;
        }
        if (message.type === 'CHECK_NOW') {
          if (state.activeElement) {
            const text = getTextFromElement(state.activeElement);
            checkGrammar(text).then(result => {
              if (result) {
                updateWidget(result.corrections);
              }
              sendResponse({ success: true });
            });
            return true; // Keep channel open for async response
          }
        }
      });
    }

    console.log('[GrammarlyClone] Initialized successfully');
  }

  // Start when DOM is ready
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
