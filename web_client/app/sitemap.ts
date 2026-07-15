import { MetadataRoute } from 'next';
import { adminDb } from '@/lib/firebase-admin';

export default async function sitemap(): Promise<MetadataRoute.Sitemap> {
  const baseUrl = process.env.NEXT_PUBLIC_BASE_URL || 'https://esportlyic.web.app';

  // Fetch top active public leagues for the sitemap
  let leagues: any[] = [];
  try {
    const snapshot = await adminDb.collection('leagues')
      .where('status', 'in', ['active', 'completed'])
      .limit(100)
      .get();
    
    leagues = snapshot.docs.map(doc => ({ id: doc.id, ...doc.data() }));
  } catch (error) {
    console.error("Sitemap generation error:", error);
  }

  const leagueUrls = leagues.map((league) => ({
    url: `${baseUrl}/leagues/${league.id}`,
    lastModified: new Date(league.createdAt?._seconds * 1000 || Date.now()),
    changeFrequency: 'daily' as const,
    priority: 0.8,
  }));

  return [
    {
      url: baseUrl,
      lastModified: new Date(),
      changeFrequency: 'daily',
      priority: 1,
    },
    {
      url: `${baseUrl}/leagues`,
      lastModified: new Date(),
      changeFrequency: 'hourly',
      priority: 0.9,
    },
    {
      url: `${baseUrl}/master-leagues`,
      lastModified: new Date(),
      changeFrequency: 'daily',
      priority: 0.9,
    },
    ...leagueUrls,
  ];
}
