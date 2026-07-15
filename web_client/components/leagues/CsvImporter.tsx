import React, { useRef, useState } from 'react';
import { doc, writeBatch, collection } from 'firebase/firestore';
import { db } from '@/lib/firebase';
import { Team } from '@/types/league';
import { Loader2, Upload, FileSpreadsheet } from 'lucide-react';

interface CsvImporterProps {
  leagueId: string;
  isGroupFormat: boolean;
  onSuccess: () => void;
}

export const CsvImporter: React.FC<CsvImporterProps> = ({ leagueId, isGroupFormat, onSuccess }) => {
  const fileInputRef = useRef<HTMLInputElement>(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState('');

  const handleFileUpload = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0];
    if (!file) return;

    setLoading(true);
    setError('');

    const reader = new FileReader();
    reader.onload = async (event) => {
      try {
        const csv = event.target?.result as string;
        const lines = csv.split('\n').filter(line => line.trim().length > 0);
        
        const batch = writeBatch(db);
        const teamsRef = collection(db, 'leagues', leagueId, 'teams');
        let importCount = 0;

        // Skip header if it contains 'id' or 'team'
        const startIndex = lines[0].toLowerCase().includes('team') ? 1 : 0;

        for (let i = startIndex; i < lines.length; i++) {
          // Naive CSV split handling simple quotes (matching Dart's logic)
          const columns = lines[i].split(',').map(c => c.trim().replace(/^"|"$/g, ''));
          
          if (columns.length < 1) continue;
          
          // Expected format: TeamName, Group (optional)
          const teamName = columns[0];
          let group = columns.length > 1 ? columns[1] : null;

          if (!teamName) continue;

          // Normalize group formatting (e.g. "A" -> "Group A") to match mobile parser
          if (isGroupFormat && group) {
             const upper = group.toUpperCase();
             if (upper.length === 1 && /^[A-L]$/.test(upper)) {
               group = `Group ${upper}`;
             }
          }

          const teamDoc = doc(teamsRef);
          const newTeam: Partial<Team> = {
            name: teamName,
            groupId: isGroupFormat ? (group || undefined) : undefined,
            logoUrl: '',
            played: 0, won: 0, drawn: 0, lost: 0,
            goalsFor: 0, goalsAgainst: 0, goalDifference: 0,
            basePoints: 0, adminAdjustment: 0, finalPoints: 0,
            updatedAtMs: Date.now(),
          };

          batch.set(teamDoc, newTeam);
          importCount++;
        }

        await batch.commit();
        alert(`Successfully imported ${importCount} teams!`);
        onSuccess();
      } catch (err: any) {
        setError("Failed to parse or upload CSV: " + err.message);
      } finally {
        setLoading(false);
        if (fileInputRef.current) fileInputRef.current.value = '';
      }
    };
    reader.onerror = () => {
      setError("Failed to read file.");
      setLoading(false);
    };
    reader.readAsText(file);
  };

  return (
    <div className="bg-brand-surface border border-brand-lime/30 p-4 rounded-xl flex flex-col sm:flex-row items-center justify-between gap-4">
      <div className="flex items-center gap-3">
        <div className="p-2 bg-brand-lime/10 rounded-lg">
          <FileSpreadsheet className="w-6 h-6 text-brand-lime" />
        </div>
        <div>
          <h3 className="text-white font-bold text-sm">Bulk Import via CSV</h3>
          <p className="text-xs text-gray-400">Format: <span className="font-mono bg-black/30 px-1 rounded">TeamName, GroupName</span></p>
        </div>
      </div>
      
      {error && <span className="text-xs text-brand-red flex-1">{error}</span>}
      
      <input type="file" accept=".csv" ref={fileInputRef} onChange={handleFileUpload} className="hidden" />
      <button 
        onClick={() => fileInputRef.current?.click()}
        disabled={loading}
        className="px-4 py-2 bg-white/10 text-white text-sm font-bold rounded-lg hover:bg-white/20 transition-colors flex items-center gap-2"
      >
        {loading ? <Loader2 className="w-4 h-4 animate-spin" /> : <Upload className="w-4 h-4" />}
        Upload CSV
      </button>
    </div>
  );
};
