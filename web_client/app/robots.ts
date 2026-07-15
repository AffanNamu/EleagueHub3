import { MetadataRoute } from 'next';

export default function robots(): MetadataRoute.Robots {
  const baseUrl = process.env.NEXT_PUBLIC_BASE_URL || 'https://esportlyic.web.app';

  return {
    rules: {
      userAgent: '*',
      allow: '/',
      disallow: ['/api/', '/premium/', '/*/admin/'], // Hide admin panels from search engines
    },
    sitemap: `${baseUrl}/sitemap.xml`,
  };
}
