import { auth } from '@/lib/firebase';

const SUPABASE_URL = process.env.NEXT_PUBLIC_SUPABASE_URL || '';
const SUPABASE_ANON_KEY = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY || '';

export class SupabaseEdgeNotificationsService {
  private static getEdgeUri(fnName: string) {
    if (!SUPABASE_URL) return null;
    const base = SUPABASE_URL.trim().replace(/\/$/, '');
    return `${base}/functions/v1/${fnName}`;
  }

  static async notifyLeagueChatMessage(params: any) {
    const uri = this.getEdgeUri('league-chat-notify');
    if (!uri || !SUPABASE_ANON_KEY || !auth.currentUser) return;
    try {
      const token = await auth.currentUser.getIdToken();
      await fetch(uri, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'apikey': SUPABASE_ANON_KEY, 'Authorization': `Bearer ${token}` },
        body: JSON.stringify(params),
      });
    } catch (e) { console.error(e); }
  }

  static async notifyFollowedOrganizerUpdate(params: any) {
    const uri = this.getEdgeUri('organizer-follow-notify');
    if (!uri || !SUPABASE_ANON_KEY || !auth.currentUser) return;
    try {
      const token = await auth.currentUser.getIdToken();
      await fetch(uri, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'apikey': SUPABASE_ANON_KEY, 'Authorization': `Bearer ${token}` },
        body: JSON.stringify(params),
      });
    } catch (e) { console.error(e); }
  }
  
  // Mirrors lib/core/services/account_deletion_service.dart's
  // _callDeleteUserDataEdgeFunction() exactly: the Firebase ID token goes
  // in the request BODY as `firebase_id_token`, NOT the Authorization
  // header. Unlike this file's other edge functions (which have
  // verify_jwt=false in supabase/config.toml and read the Firebase token
  // from the Authorization header themselves), delete-user-data is not
  // declared there — meaning it falls back to Supabase's own gateway-level
  // JWT verification, which rejects a Firebase-issued JWT as invalid
  // before the function code ever runs. Putting it in the body sidesteps
  // that entirely, same as mobile.
  static async triggerAccountDeletion(params?: { feedbackReason?: string; feedbackText?: string }) {
    const uri = this.getEdgeUri('delete-user-data');
    if (!uri || !SUPABASE_ANON_KEY || !auth.currentUser) throw new Error("Missing config");
    const idToken = await auth.currentUser.getIdToken(true);
    if (!idToken) throw new Error("Could not obtain an auth token.");

    const body: Record<string, string> = { firebase_id_token: idToken };
    if (params?.feedbackReason?.trim()) body.feedbackReason = params.feedbackReason.trim();
    if (params?.feedbackText?.trim()) body.feedbackText = params.feedbackText.trim();

    const res = await fetch(uri, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'apikey': SUPABASE_ANON_KEY },
      body: JSON.stringify(body),
    });
    if (!res.ok) throw new Error("Failed to delete user data on the server.");
    const data = await res.json().catch(() => null);
    if (data && data.success !== true) throw new Error("Failed to delete user data on the server.");
  }
}
