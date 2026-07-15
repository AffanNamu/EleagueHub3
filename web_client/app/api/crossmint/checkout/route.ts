import { NextResponse } from 'next/server';

export async function POST(req: Request) {
  try {
    // 1. Parse the incoming data from your frontend
    const body = await req.json();
    const { email, walletAddress, itemDetails } = body;

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
