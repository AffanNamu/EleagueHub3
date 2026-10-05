import { NextResponse } from 'next/server';
import { adminAuth } from '@/lib/firebase-admin';

export async function POST(req: Request) {
  try {
    // 0. This endpoint mints a real NFT (billed through Crossmint) with
    // no payment verification of its own -- it was completely open with
    // no credentials required at all, letting anyone who found the URL
    // mint NFTs to any email/wallet at the project's expense. Require the
    // same Firebase ID token every other authenticated flow in this app
    // uses; this does not make the endpoint safe to call at scale (it
    // still has no actual payment check), but it closes the
    // zero-credential abuse path.
    const authHeader = req.headers.get('authorization') || '';
    const match = authHeader.match(/^Bearer\s+(.+)$/i);
    if (!match) {
      return NextResponse.json({ error: 'Missing Authorization: Bearer <Firebase ID token>' }, { status: 401 });
    }
    let verifiedEmail: string | undefined;
    try {
      const decoded = await adminAuth.verifyIdToken(match[1].trim());
      verifiedEmail = decoded.email;
    } catch {
      return NextResponse.json({ error: 'Invalid or expired session.' }, { status: 401 });
    }

    // 1. Parse the incoming data from your frontend
    const body = await req.json();
    const { walletAddress, itemDetails } = body;
    // Never trust a client-supplied email for the mint recipient -- use
    // the identity the Firebase token just proved instead.
    const email = verifiedEmail;
    if (!walletAddress && !email) {
      return NextResponse.json({ error: 'Signed-in account has no email and no walletAddress was provided.' }, { status: 400 });
    }

    // 2. Load your secure API key
    const crossmintApiKey = process.env.CROSSMINT_API_KEY;

    if (!crossmintApiKey) {
      console.error("Missing Crossmint API Key");
      return NextResponse.json({ error: 'Server configuration error' }, { status: 500 });
    }

    // 3. Call the Crossmint API
    // (Note: This is a standard Minting API example. You can adjust the URL if you are using their Pay API)
    const crossmintUrl = 'https://www.crossmint.com/api/2022-06-09/collections/default/nfts';
    
    const response = await fetch(crossmintUrl, {
      method: 'POST',
      headers: {
        'X-API-KEY': crossmintApiKey,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        // Deliver to an email, or directly to a wallet address if you have one
        recipient: walletAddress ? `polygon:${walletAddress}` : `email:${email}:polygon`,
        metadata: {
          name: itemDetails?.name || "Premium Upgrade",
          image: "https://your-website.com/premium-badge.png", // Replace with your Cloudinary image later
          description: "Official Esportly Premium Access"
        }
      }),
    });

    const data = await response.json();

    // 4. Handle Crossmint's response
    if (!response.ok) {
      console.error('Crossmint API Error:', data);
      throw new Error(data.message || 'Transaction failed');
    }

    // 5. Send success back to the frontend
    return NextResponse.json({ success: true, data });

  } catch (error: any) {
    console.error('Backend Route Error:', error);
    return NextResponse.json({ error: error.message || 'Internal Server Error' }, { status: 500 });
  }
}
