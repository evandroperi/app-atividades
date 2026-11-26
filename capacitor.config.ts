import type { CapacitorConfig } from '@capacitor/cli';

const config: CapacitorConfig = {
  appId: 'com.lmtech.anosiniciais',
  appName: 'Anos Iniciais',
  webDir: 'www',
  appendUserAgent: 'AnosIniciaisApp',
  backgroundColor: '#ffffff',
  server: {
    // O app abre o painel ao vivo; www/ só guarda a tela de erro e o script injetado.
    url: 'https://painel.atividadesanosiniciais.com.br',
    errorPath: 'erro.html',
    allowNavigation: [
      'painel.atividadesanosiniciais.com.br',
      'clientes.atividadesanosiniciais.com.br',
    ],
  },
  ios: {
    contentInset: 'always',
    limitsNavigationsToAppBoundDomains: false,
  },
  plugins: {
    SplashScreen: {
      launchShowDuration: 800,
      backgroundColor: '#ffffff',
      showSpinner: false,
    },
    FirebaseMessaging: {
      presentationOptions: ['alert', 'badge', 'sound'],
    },
  },
};

export default config;
