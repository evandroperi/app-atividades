# App Anos Iniciais (iOS + Android)

App que abre o painel `painel.atividadesanosiniciais.com.br` dentro de um app nativo (Capacitor 8).

- **iPhone:** a Vitrine e todos os links de compra ficam escondidos e bloqueados (regra 3.1.1 da Apple).
- **Android:** a vitrine continua visível (dá para esconder mudando `ESCONDER_VITRINE` em `www/inject.js` e `BLOQUEAR_COMPRAS` em `LinkGuardPlugin.java`).
- **Notificações:** Firebase Cloud Messaging (gratuito), no lugar do OneSignal. Cada aparelho entra nos tópicos `todos` e `ios`/`android`.

## Onde fica cada coisa

| Arquivo | O que faz |
|---|---|
| `capacitor.config.ts` | Endereço do painel, nome e identificador do app |
| `www/inject.js` | Script injetado no painel: esconde a vitrine, bloqueia compra, liga notificações |
| `www/erro.html` | Tela de "sem conexão" |
| `ios/App/App/MainViewController.swift` | Injeta o script e bloqueia links de compra no iPhone |
| `android/.../LinkGuardPlugin.java` | Injeta o script no Android |
| `.github/workflows/ios.yml` | Compila e envia para o TestFlight (Actions → iOS → TestFlight → Run) |
| `.github/workflows/notificacao.yml` | Envia notificação (Actions → Enviar notificação → Run) |

## Secrets necessários (GitHub → Settings → Secrets and variables → Actions)

| Secret | De onde vem |
|---|---|
| `APPLE_TEAM_ID` | developer.apple.com → Conta → Membership (Team ID, 10 caracteres) |
| `ASC_KEY_ID` | App Store Connect → Usuários e acesso → Integrações → Chaves (função **Admin**) |
| `ASC_ISSUER_ID` | Mesma página, "Issuer ID" no topo |
| `ASC_KEY_P8` | Conteúdo do arquivo `AuthKey_XXXX.p8` baixado ao criar a chave |
| `FIREBASE_SERVICE_ACCOUNT` | Firebase → Configurações do projeto → Contas de serviço → Gerar nova chave privada (JSON inteiro) |

O `GoogleService-Info.plist` (iOS) e o `google-services.json` (Android) do Firebase ficam no próprio repositório:
`ios/App/App/GoogleService-Info.plist` e `android/app/google-services.json`.
