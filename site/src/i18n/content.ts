export type Locale = 'en' | 'es';

export type SiteCopy = {
  locale: Locale;
  meta: {
    title: string;
    description: string;
    imageAlt: string;
  };
};

export const content: Record<Locale, SiteCopy> = {
  en: {
    locale: 'en',
    meta: {
      title: 'Vitrine — turn code and terminal output into beautiful images',
      description:
        'A native macOS app for share-ready code and terminal images. Captures full-screen terminal apps like htop and lazygit as the final frame, not an escape-code transcript. Rendering is local; optional WebKit snapshots load content you explicitly request.',
      imageAlt:
        'The Vitrine editor with a code pane, live preview, and controls for theme, background, padding, and window chrome.',
    },
  },
  es: {
    locale: 'es',
    meta: {
      title: 'Vitrine — convierte código y salida de terminal en imágenes bonitas',
      description:
        'Una app nativa para macOS para crear imágenes de código y de terminal listas para compartir. Captura aplicaciones de terminal a pantalla completa como htop o lazygit reconstruyendo el fotograma final, no una transcripción de códigos de escape. El renderizado es local; las capturas WebKit cargan el contenido que pides explícitamente.',
      imageAlt:
        'El editor de Vitrine con código, vista previa y controles de tema, fondo, relleno y marco de ventana.',
    },
  },
};
