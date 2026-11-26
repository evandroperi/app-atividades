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

  // Notificações (Firebase) — só depois do login.
  function iniciarNotificacoes() {
    var FM = Cap && Cap.Plugins && Cap.Plugins.FirebaseMessaging;
    if (!FM || /^\/login/.test(location.pathname)) return;

    FM.addListener('notificationActionPerformed', function (ev) {
      var url = ev && ev.notification && ev.notification.data && ev.notification.data.url;
      if (!url) return;
      if (ESCONDER_VITRINE && ehCompra(url)) return;
      if (hostDe(url) === location.hostname) location.href = url;
    });

    if (localStorage.getItem('aai_push_ok') === '1') return;
    FM.requestPermissions().then(function (r) {
      if (r && r.receive === 'granted') {
        return FM.subscribeToTopic({ topic: 'todos' }).then(function () {
          return FM.subscribeToTopic({ topic: plataforma });
        }).then(function () {
          localStorage.setItem('aai_push_ok', '1');
        });
      }
    }).catch(function () {});
  }
  if (document.readyState === 'complete') iniciarNotificacoes();
  else window.addEventListener('load', iniciarNotificacoes);
})();
