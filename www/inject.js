/*
 * Script injetado pelo app (iOS e Android) em todas as páginas do painel.
 * - iPhone: esconde a Vitrine e bloqueia qualquer link de compra (exigência da Apple, regra 3.1.1).
 * - Android: por padrão mantém a vitrine (mude ESCONDER_VITRINE abaixo se quiser esconder também).
 * - Pede permissão de notificação e inscreve o aparelho no tópico "todos" (Firebase).
 */
(function () {
  if (window.__anosIniciaisApp) return;
  window.__anosIniciaisApp = true;

  var Cap = window.Capacitor;
  var plataforma = (Cap && Cap.getPlatform && Cap.getPlatform()) || 'web';

  var ESCONDER_VITRINE = { ios: true, android: false }[plataforma] === true;

  // Endereços de compra/venda que não podem abrir dentro do app no iPhone.
  var HOSTS_DE_COMPRA = /(^|\.)(seguro|checkout|pay|pagamento)\.|kavoo|hotmart|eduzz|kiwify|doppus|mercadopago|pagseguro|^(www\.)?atividadesanosiniciais\.com\.br$/i;
  var TEXTOS_DE_COMPRA = /comprar|compre|adquir|desconto|oferta|vitrine/i;

  function hostDe(url) {
    try { return new URL(url, location.href).hostname; } catch (e) { return ''; }
  }
  function ehCompra(url) {
    if (!url) return false;
    var h = hostDe(url);
    if (HOSTS_DE_COMPRA.test(h)) return true;
    try { return /\/vitrine(\/|$|\?)/.test(new URL(url, location.href).pathname); } catch (e) { return false; }
  }

  // "Esqueci minha senha" → link novo de recuperação.
  var LINK_NOVA_SENHA = 'https://redirect.atividadesanosiniciais.com.br/r/6ed3c482-3255-4580-b780-9a3cf5f15243';
  function trocarLinkSenha() {
    var as = document.querySelectorAll('a');
    for (var i = 0; i < as.length; i++) {
      var a = as[i];
      if (/esqueci/i.test(a.textContent || '') || /refazersenha/i.test(a.getAttribute('href') || '')) {
        if (a.getAttribute('href') !== LINK_NOVA_SENHA) a.setAttribute('href', LINK_NOVA_SENHA);
        a.removeAttribute('target');
      }
    }
  }
  trocarLinkSenha();
  new MutationObserver(trocarLinkSenha).observe(document.documentElement, { childList: true, subtree: true });

  // Downloads: em vez de abrir o PDF por cima do app (sem como voltar),
  // o app baixa e mostra numa tela própria com "OK" e o botão de compartilhar/salvar.
  var ARQUIVO = /\.(pdf|pptx?|docx?|xlsx?|zip|png|jpe?g|mp3|mp4)(\?|#|$)/i;
  document.addEventListener('click', function (ev) {
    var LG = Cap && Cap.Plugins && Cap.Plugins.LinkGuard;
    if (!LG || !LG.openFile) return;
    var a = ev.target && ev.target.closest && ev.target.closest('a[href]');
    if (!a) return;
    var href = a.getAttribute('href') || '';
    if (!(a.hasAttribute('download') || ARQUIVO.test(href))) return;
    var abs;
    try { abs = new URL(href, location.href).href; } catch (e) { return; }
    if (!/^https?:/.test(abs)) return;
    ev.preventDefault();
    ev.stopImmediatePropagation();
    var nome = (a.getAttribute('download') || a.textContent || '').trim();
    LG.openFile({ url: abs, name: nome });
    if (window.__aaiDownload) window.__aaiDownload(nome);
  }, true);

  if (ESCONDER_VITRINE) {
    // 1) Se cair na página da vitrine, volta para Meus Materiais.
    if (/^\/vitrine/.test(location.pathname)) {
      location.replace('/meus-materiais');
      return;
    }

    // 2) Esconde menus, botões e links de compra.
    var css = document.createElement('style');
    css.textContent = 'a[href*="vitrine"], .aai-oculto { display: none !important; }';
    (document.head || document.documentElement).appendChild(css);

    function limpar(raiz) {
      var links = (raiz || document).querySelectorAll('a[href], button');
      for (var i = 0; i < links.length; i++) {
        var el = links[i];
        var href = el.getAttribute('href');
        var compra = (href && ehCompra(href)) ||
          (el.tagName === 'BUTTON' && TEXTOS_DE_COMPRA.test(el.textContent || ''));
        if (compra) {
          var alvo = el.closest('li') || el;
          alvo.classList.add('aai-oculto');
        }
      }
    }
    limpar(document);
    new MutationObserver(function () { limpar(document); })
      .observe(document.documentElement, { childList: true, subtree: true });

    // 3) Bloqueia cliques e window.open para endereços de compra.
    document.addEventListener('click', function (ev) {
      var a = ev.target && ev.target.closest && ev.target.closest('a[href]');
      if (a && ehCompra(a.getAttribute('href'))) {
        ev.preventDefault();
        ev.stopImmediatePropagation();
      }
    }, true);
    var abrirOriginal = window.open;
    window.open = function (url) {
      if (ehCompra(url)) return null;
      return abrirOriginal.apply(window, arguments);
    };
  }

  // ===== Central de notificações (Lovable "Automação") =====
  var API = 'https://comercial.atividadesanosiniciais.com.br/api/public/';
  var VERSAO_APP = '1.3.0';
  var naLogin = /^\/login/.test(location.pathname);

  function ls(k, v) {
    try { if (v === undefined) return localStorage.getItem(k); if (v === null) localStorage.removeItem(k); else localStorage.setItem(k, v); } catch (e) { return null; }
  }
  function ss(k, v) {
    try { if (v === undefined) return sessionStorage.getItem(k); sessionStorage.setItem(k, v); } catch (e) { return null; }
  }
  function postar(caminho, corpo) {
    try {
      return fetch(API + caminho, {
        method: 'POST', headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(corpo), keepalive: true
      }).catch(function () {});
    } catch (e) { return Promise.resolve(); }
  }

  // Saiu da conta: esquece quem era.
  if (/^\/logout/.test(location.pathname)) { ls('aai_email', null); ls('aai_nome', null); ls('aai_reg', null); }
  if (naLogin) ss('aai_estava_login', '1');

  // E-mail da cliente logada (lido do Perfil, guardado no aparelho).
  function obterEmail() {
    var guardado = ls('aai_email');
    if (guardado && (ls('aai_nome') || ss('aai_perfil_lido') === '1')) return Promise.resolve(guardado);
    ss('aai_perfil_lido', '1');
    return fetch('/perfil', { credentials: 'include' }).then(function (r) { return r.text(); }).then(function (html) {
      var d = new DOMParser().parseFromString(html, 'text/html');
      var campo = d.querySelector('input[name=email]');
      var campoNome = d.querySelector('input[name=name]');
      var email = campo && (campo.value || '').trim().toLowerCase();
      var nome = campoNome && (campoNome.value || '').trim();
      if (nome) ls('aai_nome', nome.slice(0, 120));
      if (email && email.indexOf('@') > 0) { ls('aai_email', email); return email; }
      return null;
    }).catch(function () { return null; });
  }

  var tokenFcm = null;
  function evento(tipo, dados) {
    if (naLogin) return;
    obterEmail().then(function (email) {
      if (!email) return;
      var corpo = { email: email, event_type: tipo, event_data: dados || {} };
      if (tokenFcm) corpo.fcm_token = tokenFcm;
      postar('app-track-event', corpo);
    });
  }

  // Lembra o nome do material ao tocar no card (a página do material não mostra o nome).
  document.addEventListener('click', function (ev) {
    var a = ev.target && ev.target.closest && ev.target.closest('a[href*="visualizar-material"]');
    if (!a) return;
    var card = a.closest('.card') || a.parentElement;
    var img = card && card.querySelector('img');
    var id = (a.getAttribute('href') || '').split('/').pop();
    if (img && img.alt && id) ss('aai_mat_' + id, img.alt);
  }, true);

  function materialAtual() {
    var m = location.pathname.match(/visualizar-material\/(\d+)/);
    if (!m) return null;
    return { material_id: m[1], material_name: ss('aai_mat_' + m[1]) || '' };
  }

  // Downloads também viram evento (chamado pelo handler de arquivos acima).
  window.__aaiDownload = function (nomeArquivo) {
    var dados = materialAtual() || {};
    dados.file_name = nomeArquivo || '';
    evento('file_download', dados);
  };

  function iniciarNotificacoes() {
    var FM = Cap && Cap.Plugins && Cap.Plugins.FirebaseMessaging;
    if (naLogin) return;

    // Eventos de navegação
    if (ss('aai_aberto') !== '1') { ss('aai_aberto', '1'); evento('app_open', {}); }
    if (ss('aai_estava_login') === '1') { ss('aai_estava_login', '0'); evento('login', {}); }
    var mat = materialAtual();
    if (mat) evento('material_view', mat);

    if (!FM) return;

    FM.addListener('notificationActionPerformed', function (ev) {
      var url = ev && ev.notification && ev.notification.data && ev.notification.data.url;
      if (!url) return;
      if (ESCONDER_VITRINE && ehCompra(url)) return;   // iPhone: link de compra não abre (regra da Apple)
      // Páginas do painel abrem dentro do app; outros links (WhatsApp, Instagram...) abrem fora.
      // (o Capacitor abre no navegador/app externo tudo que não for do painel)
      location.href = url;
    });

    FM.requestPermissions().then(function (r) {
      if (!r || r.receive !== 'granted') return;
      if (ls('aai_push_ok') !== '1') {
        FM.subscribeToTopic({ topic: 'todos' }).then(function () {
          return FM.subscribeToTopic({ topic: plataforma });
        }).then(function () { ls('aai_push_ok', '1'); }).catch(function () {});
      }
      return FM.getToken().then(function (res) {
        tokenFcm = res && res.token;
        if (!tokenFcm) return;
        return obterEmail().then(function (email) {
          if (!email) return;
          // Registra no máximo 1x por dia, ou quando mudar o aparelho/cliente.
          var chave = email + '|' + (ls('aai_nome') || '') + '|' + tokenFcm + '|' + new Date().toISOString().slice(0, 10);
          if (ls('aai_reg') === chave) return;
          var corpo = { email: email, fcm_token: tokenFcm, platform: plataforma, app_version: VERSAO_APP };
          if (ls('aai_nome')) corpo.name = ls('aai_nome');
          return postar('app-register-device', corpo).then(function () { ls('aai_reg', chave); });
        });
      });
    }).catch(function () {});
  }
  if (document.readyState === 'complete') iniciarNotificacoes();
  else window.addEventListener('load', iniciarNotificacoes);
})();
