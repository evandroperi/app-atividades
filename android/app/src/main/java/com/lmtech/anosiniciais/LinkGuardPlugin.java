package com.lmtech.anosiniciais;

import android.app.DownloadManager;
import android.content.Context;
import android.net.Uri;
import android.os.Environment;
import android.webkit.CookieManager;
import android.widget.Toast;
import com.getcapacitor.PluginCall;
import com.getcapacitor.PluginMethod;
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

    /** Baixa o arquivo para a pasta Downloads, com aviso na barra de notificações. */
    @PluginMethod
    public void openFile(PluginCall call) {
        String url = call.getString("url");
        if (url == null) { call.reject("URL inválida"); return; }
        String nome = call.getString("name", "");
        if (nome == null || nome.trim().isEmpty()) nome = Uri.parse(url).getLastPathSegment();
        nome = nome.trim().replace("/", "-");
        try {
            DownloadManager.Request req = new DownloadManager.Request(Uri.parse(url));
            String cookies = CookieManager.getInstance().getCookie(url);
            if (cookies != null) req.addRequestHeader("Cookie", cookies);
            req.setTitle(nome);
            req.setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED);
            req.setDestinationInExternalPublicDir(Environment.DIRECTORY_DOWNLOADS, nome);
            DownloadManager dm = (DownloadManager) getContext().getSystemService(Context.DOWNLOAD_SERVICE);
            dm.enqueue(req);
            final String aviso = "Baixando " + nome + "… veja em Downloads";
            getActivity().runOnUiThread(() -> Toast.makeText(getContext(), aviso, Toast.LENGTH_LONG).show());
            call.resolve();
        } catch (Exception e) {
            call.reject("Não foi possível baixar", e);
        }
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
