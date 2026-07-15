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
  
  static async triggerAccountDeletion() {
    const uri = this.getEdgeUri('delete-user-data');
    if (!uri || !SUPABASE_ANON_KEY || !auth.currentUser) throw new Error("Missing config");
    const token = await auth.currentUser.getIdToken();
    const res = await fetch(uri, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', 'apikey': SUPABASE_ANON_KEY, 'Authorization': `Bearer ${token}` },
    });
    if (!res.ok) throw new Error("Failed to delete user data on the server.");
  }
}
