import sitemap from '@astrojs/sitemap';
import { defineConfig } from 'astro/config';

export default defineConfig({
  site: 'https://vitrineframe.app',
  trailingSlash: 'never',
  prerenderConflictBehavior: 'error',
  i18n: {
    locales: ['en', 'es'],
    defaultLocale: 'en',
    routing: {
      prefixDefaultLocale: false,
      redirectToDefaultLocale: false,
    },
  },
  integrations: [
    sitemap({
      filter: (page) => !/\/(download|404)\/?$/.test(page),
    }),
  ],
  build: {
    assets: 'static',
    format: 'file',
    inlineStylesheets: 'auto',
  },
});
