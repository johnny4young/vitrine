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
        'A native macOS menu-bar app that turns code, URLs, and HTML into gorgeous, share-ready images — instant, fully local, and free.',
      imageAlt:
        'The Vitrine editor with a code pane, live preview, and controls for theme, background, padding, and window chrome.',
    },
  },
  es: {
    locale: 'es',
    meta: {
      title: 'Vitrine — convierte código en imágenes bonitas desde la barra de menús',
      description:
        'Una app nativa para macOS que convierte código, URLs y HTML en imágenes listas para compartir, al instante, de forma local y gratuita.',
      imageAlt:
        'El editor de Vitrine con código, vista previa y controles de tema, fondo, relleno y marco de ventana.',
    },
  },
};
