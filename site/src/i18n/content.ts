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
      title: 'Vitrine — turn code into beautiful images, from your menu bar',
      description:
        'A native macOS menu-bar app for share-ready code images. Code rendering is local; optional WebKit snapshots load content you explicitly request.',
      imageAlt:
        'The Vitrine editor with a code pane, live preview, and controls for theme, background, padding, and window chrome.',
    },
  },
  es: {
    locale: 'es',
    meta: {
      title: 'Vitrine — convierte código en imágenes bonitas desde la barra de menús',
      description:
        'Una app nativa para macOS para crear imágenes de código listas para compartir. El renderizado de código es local; las capturas WebKit cargan el contenido que pides explícitamente.',
      imageAlt:
        'El editor de Vitrine con código, vista previa y controles de tema, fondo, relleno y marco de ventana.',
    },
  },
};
