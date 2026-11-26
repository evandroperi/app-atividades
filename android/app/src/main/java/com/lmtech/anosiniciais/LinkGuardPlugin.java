package com.lmtech.anosiniciais;

import android.net.Uri;
import android.webkit.WebView;
import com.getcapacitor.Plugin;
import com.getcapacitor.WebViewListener;
import com.getcapacitor.annotation.CapacitorPlugin;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.util.regex.Pattern;

/**
 * Injeta public/inject.js em cada página do painel (vitrine + notificações).
 * No Android a vitrine continua visível por padrão; para esconder,
 * mude ESCONDER_VITRINE em www/inject.js e BLOQUEAR_COMPRAS abaixo.
 */
@CapacitorPlugin(name = "LinkGuard")
public class LinkGuardPlugin extends Plugin {

    private static final boolean BLOQUEAR_COMPRAS = false;

    private static final Pattern HOSTS_DE_COMPRA = Pattern.compile(
        "(^|\\.)(seguro|checkout|pay|pagamento)\\.|kavoo|hotmart|eduzz|kiwify|doppus|mercadopago|pagseguro|^(www\\.)?atividadesanosiniciais\\.com\\.br$",
        Pattern.CASE_INSENSITIVE);

    private String script;

    @Override
    public void load() {
        try (InputStream in = getContext().getAssets().open("public/inject.js")) {
            byte[] buf = new byte[in.available()];
            int lidos = in.read(buf);
            script = new String(buf, 0, lidos, StandardCharsets.UTF_8);
        } catch (Exception e) {
            script = null;
        }
        bridge.addWebViewListener(new WebViewListener() {
            @Override
            public void onPageLoaded(WebView webView) {
                if (script != null) webView.evaluateJavascript(script, null);
            }
        });
    }

    @Override
    public Boolean shouldOverrideLoad(Uri url) {
        if (!BLOQUEAR_COMPRAS || url == null) return null;
        String host = url.getHost() == null ? "" : url.getHost();
        if (HOSTS_DE_COMPRA.matcher(host).find()) return true;
        if (url.getPath() != null && url.getPath().startsWith("/vitrine")) return true;
        return null;
    }
}
