'use client';

import { useState } from 'react';
import { useParams, useRouter } from 'next/navigation';
import { auth } from '@/lib/firebase';
import { submitVerificationApplicationWeb, VerificationApplicationData } from '@/lib/masterLeagues/masterLeaguesRepository';
import { uploadImageFile } from '@/lib/cloudinary/cloudinaryUpload';
import { Glass } from '@/components/ui/Glass';
import { ArrowLeft, Loader2, ShieldCheck, UploadCloud, ShieldAlert } from 'lucide-react';

// Mirrors organizer_verification_application_screen.dart's kOrganizerTypes.
const ORG_TYPES = [
  'Esports Organization',
  'Football Club / Academy',
  'League / Federation',
  'Community / Fan Group',
  'Company / Brand',
  'Educational Institution',
  'Individual Organizer',
  'Other',
];

// Mirrors kOrganizerVerificationCountries.
const ORG_COUNTRIES: [string, string][] = [
  ['US', 'United States'], ['GB', 'United Kingdom'], ['NG', 'Nigeria'],
  ['GH', 'Ghana'], ['KE', 'Kenya'], ['ZA', 'South Africa'], ['EG', 'Egypt'],
  ['CA', 'Canada'], ['AU', 'Australia'], ['DE', 'Germany'], ['FR', 'France'],
  ['ES', 'Spain'], ['IT', 'Italy'], ['NL', 'Netherlands'], ['BE', 'Belgium'],
  ['PT', 'Portugal'], ['IE', 'Ireland'], ['SE', 'Sweden'], ['NO', 'Norway'],
  ['DK', 'Denmark'], ['FI', 'Finland'], ['PL', 'Poland'], ['CZ', 'Czechia'],
  ['AT', 'Austria'], ['CH', 'Switzerland'], ['GR', 'Greece'], ['TR', 'Turkey'],
  ['RU', 'Russia'], ['UA', 'Ukraine'], ['IN', 'India'], ['PK', 'Pakistan'],
  ['BD', 'Bangladesh'], ['CN', 'China'], ['JP', 'Japan'], ['KR', 'South Korea'],
  ['ID', 'Indonesia'], ['MY', 'Malaysia'], ['SG', 'Singapore'],
  ['PH', 'Philippines'], ['TH', 'Thailand'], ['VN', 'Vietnam'],
  ['AE', 'United Arab Emirates'], ['SA', 'Saudi Arabia'], ['QA', 'Qatar'],
  ['IL', 'Israel'], ['BR', 'Brazil'], ['AR', 'Argentina'], ['MX', 'Mexico'],
  ['CL', 'Chile'], ['CO', 'Colombia'], ['PE', 'Peru'], ['CM', 'Cameroon'],
  ["CI", "Cote d'Ivoire"], ['SN', 'Senegal'], ['TZ', 'Tanzania'],
  ['UG', 'Uganda'], ['RW', 'Rwanda'], ['ET', 'Ethiopia'], ['MA', 'Morocco'],
  ['DZ', 'Algeria'], ['TN', 'Tunisia'], ['ZM', 'Zambia'], ['ZW', 'Zimbabwe'],
  ['NZ', 'New Zealand'], ['HU', 'Hungary'], ['RO', 'Romania'],
  ['BG', 'Bulgaria'], ['HR', 'Croatia'], ['RS', 'Serbia'], ['SK', 'Slovakia'],
  ['SI', 'Slovenia'], ['IS', 'Iceland'], ['LU', 'Luxembourg'], ['CY', 'Cyprus'],
  ['MT', 'Malta'],
];

// Mirrors OrganizerVerificationApplicationData.validate() exactly.
function validate(formData: VerificationApplicationData, hasLogo: boolean): string | null {
  if (!formData.orgName.trim()) return 'Organization name is required.';
  if (!formData.orgType.trim()) return 'Organization type is required.';
  if (formData.orgCountry.trim().length !== 2) return 'Please select a country.';
  if (!formData.contactEmail.trim() || !formData.contactEmail.includes('@')) {
    return 'A valid contact email is required.';
  }
  if (!formData.applicantFullName.trim()) return "Applicant's full name is required.";
  if (!formData.applicantRole.trim()) return "Applicant's role or position is required.";
  if (!formData.orgDescription.trim()) return 'Please describe what your organization does.';
  if (!formData.verificationReason.trim()) return 'Please explain why you want organizer verification.';
  if (!hasLogo) return 'Please upload your organization logo.';
  return null;
}

export default function OrganizerVerificationScreen() {
  const params = useParams();
  const router = useRouter();
  const mlId = params.id as string;

  const [formData, setFormData] = useState<VerificationApplicationData>({
    orgName: '', orgType: ORG_TYPES[0], orgCountry: '', orgRegion: '', orgCity: '',
    contactEmail: '', contactPhone: '', website: '', socialLink: '',
    applicantFullName: '', applicantRole: '', orgDescription: '',
    competitionTypes: '', verificationReason: '', supportingLinks: '', logoUrl: ''
  });

  const [logoFile, setLogoFile] = useState<File | null>(null);
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState('');

  function set<K extends keyof VerificationApplicationData>(key: K, value: VerificationApplicationData[K]) {
    setFormData((prev) => ({ ...prev, [key]: value }));
  }

  const handleSubmit = async () => {
    const validationError = validate(formData, !!logoFile);
    if (validationError) {
      setError(validationError);
      return;
    }
    const uid = auth.currentUser?.uid;
    if (!uid) return router.push('/login');

    setSubmitting(true);
    setError('');

    try {
      // 1. Upload Logo
      const { secureUrl } = await uploadImageFile({ file: logoFile!, folder: 'eleaguehub/organizer_verification' });

      // 2. We skip actual payments on Web for now (requires your payment gateway integration like Stripe/Flutterwave),
      // so we will pass dummy payment data for testing. In production, wrap this in your payment flow.
      await submitVerificationApplicationWeb({
        mlId,
        authUid: uid,
        attemptId: `web_attempt_${Date.now()}`,
        paymentId: `web_payment_${Date.now()}`,
        receiptId: `web_receipt_${Date.now()}`,
        application: { ...formData, logoUrl: secureUrl }
      });

      alert('Verification application submitted successfully!');
      router.push(`/master-leagues/${mlId}`);
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Submission failed. Check permissions.');
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <div className="max-w-3xl mx-auto space-y-6 pb-20 px-4 sm:px-6">
      <div className="flex items-center gap-4 mt-4">
        <button onClick={() => router.back()} className="p-2.5 bg-[#0B1221] border border-[#1E293B] rounded-xl">
          <ArrowLeft className="w-5 h-5 text-white" />
        </button>
        <h1 className="text-xl md:text-2xl font-black text-white flex items-center gap-2">
          <ShieldCheck className="w-6 h-6 text-[#1D9BF0]" /> Get Verified
        </h1>
      </div>

      <Glass className="p-6 md:p-8 bg-[#0B1221] border-[#1E293B] rounded-3xl shadow-xl">
        <p className="text-sm text-gray-400 mb-6 font-medium leading-relaxed">
          Submit your organization details to receive the official Verified Organizer badge. Payment is required before final review.
        </p>

        {error && <div className="p-4 mb-6 bg-red-500/10 border border-red-500/30 text-red-500 rounded-xl text-sm font-bold flex gap-2"><ShieldAlert className="w-5 h-5"/>{error}</div>}

        <div className="space-y-4">
          <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
            <input placeholder="Organization Name *" value={formData.orgName} onChange={e => set('orgName', e.target.value)} className="w-full bg-[#070B14] border border-[#1E293B] rounded-xl p-3.5 text-white outline-none focus:border-[#1D9BF0]" />

            <select value={formData.orgType} onChange={e => set('orgType', e.target.value)} className="w-full bg-[#070B14] border border-[#1E293B] rounded-xl p-3.5 text-white outline-none focus:border-[#1D9BF0]">
              {ORG_TYPES.map((t) => <option key={t} value={t}>{t}</option>)}
            </select>

            <select value={formData.orgCountry} onChange={e => set('orgCountry', e.target.value)} className="w-full bg-[#070B14] border border-[#1E293B] rounded-xl p-3.5 text-white outline-none focus:border-[#1D9BF0]">
              <option value="">Country *</option>
              {ORG_COUNTRIES.map(([code, name]) => <option key={code} value={code}>{name}</option>)}
            </select>

            <input placeholder="Region / State" value={formData.orgRegion} onChange={e => set('orgRegion', e.target.value)} className="w-full bg-[#070B14] border border-[#1E293B] rounded-xl p-3.5 text-white outline-none focus:border-[#1D9BF0]" />
            <input placeholder="City" value={formData.orgCity} onChange={e => set('orgCity', e.target.value)} className="w-full bg-[#070B14] border border-[#1E293B] rounded-xl p-3.5 text-white outline-none focus:border-[#1D9BF0]" />

            <input placeholder="Applicant Full Name *" value={formData.applicantFullName} onChange={e => set('applicantFullName', e.target.value)} className="w-full bg-[#070B14] border border-[#1E293B] rounded-xl p-3.5 text-white outline-none focus:border-[#1D9BF0]" />
            <input placeholder="Applicant Role *" value={formData.applicantRole} onChange={e => set('applicantRole', e.target.value)} className="w-full bg-[#070B14] border border-[#1E293B] rounded-xl p-3.5 text-white outline-none focus:border-[#1D9BF0]" />
            <input placeholder="Contact Email *" value={formData.contactEmail} onChange={e => set('contactEmail', e.target.value)} className="w-full bg-[#070B14] border border-[#1E293B] rounded-xl p-3.5 text-white outline-none focus:border-[#1D9BF0]" />
            <input placeholder="Contact Phone" value={formData.contactPhone} onChange={e => set('contactPhone', e.target.value)} className="w-full bg-[#070B14] border border-[#1E293B] rounded-xl p-3.5 text-white outline-none focus:border-[#1D9BF0]" />
            <input placeholder="Website" value={formData.website} onChange={e => set('website', e.target.value)} className="w-full bg-[#070B14] border border-[#1E293B] rounded-xl p-3.5 text-white outline-none focus:border-[#1D9BF0]" />
            <input placeholder="Social Link" value={formData.socialLink} onChange={e => set('socialLink', e.target.value)} className="w-full bg-[#070B14] border border-[#1E293B] rounded-xl p-3.5 text-white outline-none focus:border-[#1D9BF0]" />
          </div>

          <textarea placeholder="Organization Description *" rows={3} value={formData.orgDescription} onChange={e => set('orgDescription', e.target.value)} className="w-full bg-[#070B14] border border-[#1E293B] rounded-xl p-3.5 text-white outline-none focus:border-[#1D9BF0] resize-none" />
          <textarea placeholder="Competition Types you run" rows={2} value={formData.competitionTypes} onChange={e => set('competitionTypes', e.target.value)} className="w-full bg-[#070B14] border border-[#1E293B] rounded-xl p-3.5 text-white outline-none focus:border-[#1D9BF0] resize-none" />
          <textarea placeholder="Why do you want verification? *" rows={3} value={formData.verificationReason} onChange={e => set('verificationReason', e.target.value)} className="w-full bg-[#070B14] border border-[#1E293B] rounded-xl p-3.5 text-white outline-none focus:border-[#1D9BF0] resize-none" />
          <textarea placeholder="Supporting links (press, socials, etc.)" rows={2} value={formData.supportingLinks} onChange={e => set('supportingLinks', e.target.value)} className="w-full bg-[#070B14] border border-[#1E293B] rounded-xl p-3.5 text-white outline-none focus:border-[#1D9BF0] resize-none" />

          <div className="pt-4">
            <label className="text-xs font-bold text-gray-500 uppercase tracking-widest mb-2 block">Official Logo *</label>
            <div className="flex items-center gap-4">
              <label className="flex items-center justify-center w-20 h-20 bg-[#070B14] border-2 border-dashed border-[#1E293B] hover:border-[#1D9BF0] rounded-2xl cursor-pointer transition-colors overflow-hidden">
                {logoFile ? <img src={URL.createObjectURL(logoFile)} alt="Logo preview" className="w-full h-full object-cover"/> : <UploadCloud className="w-6 h-6 text-gray-500"/>}
                <input type="file" accept="image/*" onChange={e => setLogoFile(e.target.files?.[0] || null)} className="hidden" />
              </label>
              <span className="text-sm text-gray-400 font-medium">Upload a square, high-quality image (Max 5MB).</span>
            </div>
          </div>

          <button onClick={handleSubmit} disabled={submitting} className="w-full py-4 mt-6 bg-[#1D9BF0] text-white font-black rounded-xl hover:bg-sky-400 disabled:opacity-50 flex items-center justify-center gap-2 shadow-lg shadow-sky-500/20">
            {submitting ? <Loader2 className="w-5 h-5 animate-spin" /> : 'Submit for Review'}
          </button>
        </div>
      </Glass>
    </div>
  );
}
