import { useState, useEffect } from 'react';
import { doc, collection, query, orderBy, onSnapshot, limit, getDocs } from 'firebase/firestore';
import { db } from '@/lib/firebase';
import { TeamProfileData, UserStats, Trophy, RecentMatch, SquadData } from '@/lib/profile/teamProfileRepository';

export function useTeamProfile(userId: string | null) {
  const [profile, setProfile] = useState<TeamProfileData | null>(null);
  const [stats, setStats] = useState<UserStats | null>(null);
  const [trophies, setTrophies] = useState<Trophy[]>([]);
  const [recentMatches, setRecentMatches] = useState<RecentMatch[]>([]);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (!userId) {
      setLoading(false);
      return;
    }
    
    let loadedCount = 0;
    const checkDone = () => { loadedCount++; if (loadedCount === 4) setLoading(false); };

    const unsubProfile = onSnapshot(doc(db, 'users', userId, 'team_profile', 'profile'), (doc) => {
      if (doc.exists()) setProfile({ userId, ...doc.data() } as TeamProfileData);
      else setProfile(null);
      checkDone();
    });

    const unsubStats = onSnapshot(doc(db, 'users', userId, 'stats', 'summary'), (doc) => {
      if (doc.exists()) {
        const d = doc.data();
        const matchesPlayed = (d.wins || 0) + (d.draws || 0) + (d.losses || 0);
        const winPercentage = matchesPlayed > 0 ? ((d.wins || 0) / matchesPlayed) * 100 : 0;
        setStats({ ...d, matchesPlayed, winPercentage } as UserStats);
      } else {
        setStats({ followersCount: 0, followingCount: 0, competitionsJoined: 0, trophies: 0, matchesPlayed: 0, wins: 0, draws: 0, losses: 0, goalsScored: 0, goalsConceded: 0, winPercentage: 0 });
      }
      checkDone();
    });

    const qTrophies = query(collection(db, 'users', userId, 'trophies'), orderBy('createdAtMs', 'desc'));
    const unsubTrophies = onSnapshot(qTrophies, (snap) => {
      setTrophies(snap.docs.map(d => ({ id: d.id, ...d.data() } as Trophy)));
      checkDone();
    });

    const qMatches = query(collection(db, 'users', userId, 'recent_matches'), orderBy('playedAtMs', 'desc'), limit(15));
    const unsubMatches = onSnapshot(qMatches, (snap) => {
      setRecentMatches(snap.docs.map(d => ({ id: d.id, ...d.data() } as RecentMatch)));
      checkDone();
    });

    return () => { unsubProfile(); unsubStats(); unsubTrophies(); unsubMatches(); };
  }, [userId]);

  return { profile, stats, trophies, recentMatches, loading };
}

export function useSquad(userId: string | null, gameId: string) {
  const [squad, setSquad] = useState<SquadData | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (!userId || !gameId) {
      setLoading(false);
      return;
    }
    const unsub = onSnapshot(doc(db, 'users', userId, 'squads', gameId), (docSnap) => {
      if (docSnap.exists()) setSquad(docSnap.data() as SquadData);
      else setSquad({ gameId, formation: '4-3-3', players: [], managerName: '', captainPlayerId: '', viceCaptainPlayerId: '', teamStrength: 0, updatedAtMs: 0 });
      setLoading(false);
    });
    return () => unsub();
  }, [userId, gameId]);

  return { squad, loading };
}

export function useSquadGames(userId: string | null) {
  const [games, setGames] = useState<string[]>(['local_football']);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    if (!userId) return;
    getDocs(collection(db, 'users', userId, 'squads')).then(snap => {
      if (!snap.empty) setGames(snap.docs.map(d => d.id));
      setLoading(false);
    }).catch(() => setLoading(false));
  }, [userId]);

  return { games, loading };
}
