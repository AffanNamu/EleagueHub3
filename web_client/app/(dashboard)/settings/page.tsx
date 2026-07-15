'use client';

import { useState } from 'react';
import { useRouter } from 'next/navigation';
import { auth } from '@/lib/firebase';
import { SupabaseEdgeNotificationsService } from '@/lib/services/supabaseEdgeNotifications';
import { Glass } from '@/components/ui/Glass';
import { Loader2, Settings, UserX, ShieldAlert, LogOut, Bell, Moon, MessageSquare, AlertTriangle } from 'lucide-react';

export default function SettingsScreen() {
  const router = useRouter();
  const [deleting, setDeleting] = useState(false);
  const [error, setError] = useState('');
  const [showDeleteModal, setShowDeleteModal] = useState(false);

  // Preference Toggles (Simulated local state, in production sync with user profile/localStorage)
  const [prefs, setPrefs] = useState({
    pushEnabled: true,
    marketing: false,
    matchReminders: true,
    liveViewerChat: true,
  });

  const togglePref = (key: keyof typeof prefs) => setPrefs(p => ({ ...p, [key]: !p[key] }));

  const handleSignOut = async () => {
    await auth.signOut();
    router.push('/login');
  };

  const handleDeleteAccount = async () => {
    setDeleting(true);
    setError('');

    try {
      await SupabaseEdgeNotificationsService.triggerAccountDeletion();
      if (auth.currentUser) await auth.currentUser.delete();
      
      router.push('/login');
    } catch (err: any) {
      console.error(err);
      if (err.code === 'auth/requires-recent-login') {
        setError('Please sign out, sign back in, and try again to verify your identity.');
      } else {
        setError(err.message || 'Failed to delete account.');
      }
      setDeleting(false);
      setShowDeleteModal(false);
    }
  };

  return (
    <div className="space-y-6 max-w-4xl mx-auto pb-10">
      <div>
        <h1 className="text-2xl md:text-3xl font-bold text-white flex items-center gap-2">
          <Settings className="w-6 h-6 text-brand-lime" /> Account Settings
        </h1>
        <p className="text-gray-400 mt-1">Manage your application preferences and security.</p>
      </div>

      {error && (
        <div className="flex items-center gap-2 bg-brand-red/20 border border-brand-red text-brand-red p-4 rounded-xl">
          <ShieldAlert className="w-5 h-5 flex-shrink-0" />
          <span className="text-sm">{error}</span>
        </div>
      )}

      <div className="grid grid-cols-1 md:grid-cols-2 gap-6">
        {/* Left Column: Toggles */}
        <div className="space-y-6">
          <Glass className="p-6">
            <div className="flex items-center gap-2 mb-4">
              <Bell className="w-5 h-5 text-[#38BDF8]" />
              <h3 className="font-bold text-white">Notifications</h3>
            </div>
            <div className="space-y-4">
              <ToggleRow label="Enable Push Notifications" checked={prefs.pushEnabled} onChange={() => togglePref('pushEnabled')} />
              <ToggleRow label="Match Reminders" checked={prefs.matchReminders} onChange={() => togglePref('matchReminders')} />
              <ToggleRow label="Marketing & Promos" checked={prefs.marketing} onChange={() => togglePref('marketing')} />
            </div>
          </Glass>

          <Glass className="p-6">
            <div className="flex items-center gap-2 mb-4">
              <MessageSquare className="w-5 h-5 text-[#38BDF8]" />
              <h3 className="font-bold text-white">Live Viewer Settings</h3>
            </div>
            <div className="space-y-4">
              <ToggleRow label="Show Chat in Live View" checked={prefs.liveViewerChat} onChange={() => togglePref('liveViewerChat')} />
            </div>
          </Glass>
        </div>

        {/* Right Column: Danger Zone */}
        <div className="space-y-6">
          <Glass className="p-6 flex flex-col items-start gap-4">
            <div className="w-full">
              <h3 className="text-white font-bold text-lg mb-1">Session Management</h3>
              <p className="text-sm text-gray-400">Securely log out of this browser session.</p>
            </div>
            <button 
              onClick={handleSignOut}
              className="px-6 py-3 bg-white/10 hover:bg-white/20 text-white font-bold rounded-xl transition-colors flex items-center gap-2 w-full justify-center"
            >
              <LogOut className="w-4 h-4" /> Sign Out
            </button>
          </Glass>

          <Glass className="p-6 border-brand-red/30 bg-brand-red/5">
            <div className="flex items-center gap-2 mb-2">
              <AlertTriangle className="w-5 h-5 text-brand-red" />
              <h3 className="text-brand-red font-bold text-lg">Danger Zone</h3>
            </div>
            <p className="text-sm text-gray-400 mb-6">
              Permanently delete your account. This will erase your profile, team data, and remove you from all leagues. This action cannot be undone.
            </p>
            <button 
              onClick={() => setShowDeleteModal(true)}
              className="px-6 py-3 bg-brand-red/10 text-brand-red border border-brand-red/30 font-bold rounded-xl hover:bg-brand-red/20 transition-colors flex items-center gap-2 w-full justify-center"
            >
              <UserX className="w-4 h-4" /> Delete Account
            </button>
          </Glass>
        </div>
      </div>

      {/* Delete Account Modal (Mirrors delete_account_flow.dart) */}
      {showDeleteModal && (
        <div className="fixed inset-0 bg-black/80 backdrop-blur-sm z-50 flex items-center justify-center p-4">
          <Glass className="max-w-md w-full p-8 text-center border-brand-red/50">
            {deleting ? (
              <div className="flex flex-col items-center">
                <Loader2 className="w-12 h-12 text-brand-red animate-spin mb-4" />
                <h3 className="text-xl font-bold text-white mb-2">Deleting Account</h3>
                <p className="text-sm text-gray-400">Removing your data permanently. Please wait...</p>
              </div>
            ) : (
              <>
                <div className="w-16 h-16 bg-brand-red/20 rounded-full flex items-center justify-center mx-auto mb-4">
                  <AlertTriangle className="w-8 h-8 text-brand-red" />
                </div>
                <h3 className="text-2xl font-black text-white mb-2">Are you sure?</h3>
                <p className="text-sm text-gray-400 mb-6">
                  You are about to permanently delete your eSportlyic account. This will destroy all your Master Leagues, Tournaments, and chat history.
                </p>
                <div className="flex gap-3">
                  <button onClick={() => setShowDeleteModal(false)} className="flex-1 py-3 bg-brand-surface border border-white/10 rounded-xl text-white font-bold hover:bg-white/5 transition-colors">
                    Cancel
                  </button>
                  <button onClick={handleDeleteAccount} className="flex-1 py-3 bg-brand-red text-white font-bold rounded-xl hover:bg-brand-red/90 transition-colors shadow-lg shadow-brand-red/20">
                    Yes, Delete
                  </button>
                </div>
              </>
            )}
          </Glass>
        </div>
      )}
    </div>
  );
}

function ToggleRow({ label, checked, onChange }: { label: string, checked: boolean, onChange: () => void }) {
  return (
    <div className="flex items-center justify-between p-3 bg-brand-surface rounded-xl border border-white/5">
      <span className="text-sm font-bold text-gray-200">{label}</span>
      <div 
        onClick={onChange}
        className={`w-12 h-6 rounded-full p-1 cursor-pointer transition-colors ${checked ? 'bg-brand-lime' : 'bg-gray-600'}`}
      >
        <div className={`w-4 h-4 rounded-full bg-brand-navy transition-transform ${checked ? 'translate-x-6' : 'translate-x-0'}`} />
      </div>
    </div>
  );
}
