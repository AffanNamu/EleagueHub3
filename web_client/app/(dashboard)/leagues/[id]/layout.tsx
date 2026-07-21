
/* app/(dashboard)/league/[id]/layout*/
import { Metadata, ResolvingMetadata } from 'next';
import { adminDb } from '@/lib/firebase-admin';

type Props = {
  params: { id: string };
};

// Next.js magically calls this function on the server before rendering the page
export async function generateMetadata(
  { params }: Props,
  parent: ResolvingMetadata
): Promise<Metadata> {
  const id = params.id;
  
  try {
    // Fetch data using the Admin SDK (bypasses client security rules safely on the server)
    const leagueDoc = await adminDb.collection('leagues').doc(id).get();
    
    if (leagueDoc.exists) {
      const league = leagueDoc.data();
      
      return {
        title: `${league?.name} | eSportlyic`,
        description: league?.description || 'View live standings, matches, and stats on eSportlyic.',
        openGraph: {
          title: league?.name,
          description: league?.description || 'Live Tournament Standings',
          images: league?.coverImageUrl ? [league.coverImageUrl] : [],
          type: 'website',
        },
        twitter: {
          card: 'summary_large_image',
          title: league?.name,
          description: league?.description,
          images: league?.coverImageUrl ? [league.coverImageUrl] : [],
        },
      };
    }
  } catch (error) {
    console.error("Error generating metadata:", error);
  }

  // Fallback metadata
  return {
    title: 'League Details | eSportlyic',
    description: 'View league details and standings.',
  };
}

export default function LeagueDetailsLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <div className="w-full">
      {children}
    </div>
  );
}
