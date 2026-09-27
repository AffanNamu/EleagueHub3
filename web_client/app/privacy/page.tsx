import React from 'react';
import Link from 'next/link';

export default function PrivacyPolicyPage() {
  const appName = 'eSportlyic';
  const supportEmail = 'NASSARACORETECHVENTURES@GMAIL.COM';
  const effectiveDate = '15 February 2026';

  return (
    <div className="min-h-screen bg-[#0F172A] text-slate-200 font-sans selection:bg-[#BFFF00] selection:text-black pb-12">
      {/* Navbar Placeholder - you can replace this with your actual Layout Navbar if needed */}
      <header className="sticky top-0 z-50 w-full backdrop-blur-md bg-[#0F172A]/80 border-b border-slate-800 px-4 py-4 mb-8">
        <div className="max-w-4xl mx-auto flex items-center">
          <Link href="/" className="text-[#BFFF00] font-black text-xl flex items-center gap-2">
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" fill="currentColor" className="w-6 h-6">
              <path d="M21.08 8.58v6.84c0 1.98-1.57 3.58-3.51 3.58h-2.18c-.28 0-.55-.13-.73-.34l-2.02-2.48c-.29-.35-.71-.56-1.16-.56H8.52c-2.43 0-4.4-2.01-4.4-4.5V8.58c0-2.48 1.97-4.5 4.4-4.5h9.05c2.43 0 4.4 2.02 4.4 4.5h-.89zM7.5 11.5a1.5 1.5 0 100-3 1.5 1.5 0 000 3zm3 0a1.5 1.5 0 100-3 1.5 1.5 0 000 3zm4.5 0a1.5 1.5 0 100-3 1.5 1.5 0 000 3z" />
            </svg>
            {appName}
          </Link>
        </div>
      </header>

      <main className="max-w-4xl mx-auto px-4 md:px-6">
        {/* Glass Container */}
        <div className="bg-slate-800/40 backdrop-blur-xl border border-slate-700/50 rounded-3xl p-6 md:p-10 shadow-2xl">
          <div className="mb-8">
            <h1 className="text-3xl md:text-4xl font-black text-white mb-2">
              Privacy Policy
            </h1>
            <p className="text-slate-400 font-medium">
              {appName} Privacy Policy - Effective Date: {effectiveDate}
            </p>
          </div>

          <hr className="border-slate-700 mb-10" />

          <div className="space-y-10">
            {/* 1. Introduction */}
            <section>
              <h2 className="text-xl font-black text-[#BFFF00] mb-4">1. Introduction</h2>
              <p className="text-slate-300 leading-relaxed mb-4">
                Welcome to {appName}. This Privacy Policy explains how we collect, use, disclose, and safeguard your information when you visit our application and use our esports and tournament services.
              </p>
              <p className="text-slate-300 leading-relaxed">
                Please read this privacy policy carefully to understand our practices regarding your personal data.
              </p>
            </section>

            {/* 2. Information We Collect */}
            <section>
              <h2 className="text-xl font-black text-[#BFFF00] mb-4">2. Information We Collect</h2>
              <p className="text-slate-300 leading-relaxed mb-6">
                We collect information that you provide to us, information collected automatically, and information from third parties.
              </p>

              <h3 className="text-lg font-bold text-white mb-3">Information you provide directly</h3>
              <ul className="space-y-2 mb-6 text-slate-300">
                <li className="flex items-start"><span className="text-[#BFFF00] mr-3 mt-1">●</span> Account registration details (username, email, passwords)</li>
                <li className="flex items-start"><span className="text-[#BFFF00] mr-3 mt-1">●</span> Profile information (team affiliation, bio, player avatars)</li>
                <li className="flex items-start"><span className="text-[#BFFF00] mr-3 mt-1">●</span> Payment and premium transaction information</li>
                <li className="flex items-start"><span className="text-[#BFFF00] mr-3 mt-1">●</span> Communications with our support or arbitration teams</li>
              </ul>

              <h3 className="text-lg font-bold text-white mb-3">Information collected automatically</h3>
              <p className="text-slate-300 leading-relaxed mb-3">When you use our services, we automatically collect:</p>
              <ul className="space-y-2 mb-6 text-slate-300">
                <li className="flex items-start"><span className="text-[#BFFF00] mr-3 mt-1">●</span> Device and usage information (IP address, device IDs, browser type)</li>
                <li className="flex items-start"><span className="text-[#BFFF00] mr-3 mt-1">●</span> Matchmaking and gameplay analytics</li>
                <li className="flex items-start"><span className="text-[#BFFF00] mr-3 mt-1">●</span> Log data and crash reports</li>
                <li className="flex items-start"><span className="text-[#BFFF00] mr-3 mt-1">●</span> Interaction data with the global chat and community feeds</li>
              </ul>

              <h3 className="text-lg font-bold text-white mb-3">Information from third parties</h3>
              <p className="text-slate-300 leading-relaxed mb-3">We may receive information about you from:</p>
              <ul className="space-y-2 text-slate-300">
                <li className="flex items-start"><span className="text-[#BFFF00] mr-3 mt-1">●</span> Social media and authentication integrations (e.g., Google, Apple Sign-In)</li>
                <li className="flex items-start"><span className="text-[#BFFF00] mr-3 mt-1">●</span> League organizers and tournament administrators</li>
                <li className="flex items-start"><span className="text-[#BFFF00] mr-3 mt-1">●</span> Verification and analytics providers</li>
                <li className="flex items-start"><span className="text-[#BFFF00] mr-3 mt-1">●</span> Payment processors (e.g., Flutterwave, Crossmint)</li>
              </ul>
            </section>

            {/* 3. Camera / Microphone / Screen Recording */}
            <section>
              <h2 className="text-xl font-black text-[#BFFF00] mb-4">3. Camera, Microphone, and Screen Recording</h2>
              <p className="text-slate-300 leading-relaxed mb-4">To facilitate live esports features, our app may request access to:</p>
              <ul className="space-y-2 mb-4 text-slate-300">
                <li className="flex items-start"><span className="text-[#BFFF00] mr-3 mt-1">●</span> <strong>Camera:</strong> For user profile photos or live session streaming.</li>
                <li className="flex items-start"><span className="text-[#BFFF00] mr-3 mt-1">●</span> <strong>Microphone:</strong> For in-platform voice chat and community discussions via LiveKit.</li>
                <li className="flex items-start"><span className="text-[#BFFF00] mr-3 mt-1">●</span> <strong>Screen Recording:</strong> For match verification, capturing highlights, and dispute resolution.</li>
              </ul>
              <p className="text-slate-300 leading-relaxed">We only access these hardware features with your explicit, real-time permission.</p>
            </section>

            {/* 4. Overlay Permission */}
            <section>
              <h2 className="text-xl font-black text-[#BFFF00] mb-4">4. Overlay Permission</h2>
              <p className="text-slate-300 leading-relaxed mb-4">For competitive play, we may require overlay permissions to:</p>
              <ul className="space-y-2 text-slate-300">
                <li className="flex items-start"><span className="text-[#BFFF00] mr-3 mt-1">●</span> Display critical tournament alerts over other apps.</li>
                <li className="flex items-start"><span className="text-[#BFFF00] mr-3 mt-1">●</span> Show live match scores and fixture updates.</li>
                <li className="flex items-start"><span className="text-[#BFFF00] mr-3 mt-1">●</span> Provide quick-access communication modules during gameplay.</li>
              </ul>
            </section>

            {/* 5. How We Use Your Information */}
            <section>
              <h2 className="text-xl font-black text-[#BFFF00] mb-4">5. How We Use Your Information</h2>
              <p className="text-slate-300 leading-relaxed mb-4">We use the information we collect to:</p>
              <ul className="space-y-2 text-slate-300">
                <li className="flex items-start"><span className="text-[#BFFF00] mr-3 mt-1">●</span> Provide, operate, and maintain our application.</li>
                <li className="flex items-start"><span className="text-[#BFFF00] mr-3 mt-1">●</span> Improve, personalize, and expand our matchmaking features.</li>
                <li className="flex items-start"><span className="text-[#BFFF00] mr-3 mt-1">●</span> Process transactions, premiums, and marketplace coupon redemptions.</li>
                <li className="flex items-start"><span className="text-[#BFFF00] mr-3 mt-1">●</span> Facilitate tournaments, knockout draws, and master leagues.</li>
                <li className="flex items-start"><span className="text-[#BFFF00] mr-3 mt-1">●</span> Communicate with you regarding updates, announcements, and support.</li>
                <li className="flex items-start"><span className="text-[#BFFF00] mr-3 mt-1">●</span> Enforce our terms, competition rules, and fair play policies.</li>
                <li className="flex items-start"><span className="text-[#BFFF00] mr-3 mt-1">●</span> Prevent fraud, cheating, and ensure platform security.</li>
              </ul>
            </section>

            {/* 6. Data Storage and Services */}
            <section>
              <h2 className="text-xl font-black text-[#BFFF00] mb-4">6. Data Storage and Services</h2>
              <p className="text-slate-300 leading-relaxed mb-4">We prioritize the security and integrity of your data:</p>
              <ul className="space-y-2 mb-4 text-slate-300">
                <li className="flex items-start"><span className="text-[#BFFF00] mr-3 mt-1">●</span> Your data is stored on secure, industry-leading servers (including Firebase and Supabase).</li>
                <li className="flex items-start"><span className="text-[#BFFF00] mr-3 mt-1">●</span> Media files, such as player photos and match posters, are securely hosted via Cloudinary.</li>
              </ul>
              <p className="text-slate-300 leading-relaxed">We use industry-standard encryption protocols to protect sensitive information during transit and at rest.</p>
            </section>

            {/* 7. Sharing of Information */}
            <section>
              <h2 className="text-xl font-black text-[#BFFF00] mb-4">7. Sharing of Information</h2>
              <p className="text-slate-300 leading-relaxed mb-4">We do not sell your personal information. We may share information with:</p>
              <ul className="space-y-2 text-slate-300">
                <li className="flex items-start"><span className="text-[#BFFF00] mr-3 mt-1">●</span> Service providers acting on our behalf (hosting, analytics, payments).</li>
                <li className="flex items-start"><span className="text-[#BFFF00] mr-3 mt-1">●</span> League organizers and team admins (for roster verification and match administration).</li>
                <li className="flex items-start"><span className="text-[#BFFF00] mr-3 mt-1">●</span> Other users (publicly visible profile data, squads, and match history).</li>
                <li className="flex items-start"><span className="text-[#BFFF00] mr-3 mt-1">●</span> Legal authorities, if required by law or to protect our platform&apos;s integrity.</li>
              </ul>
            </section>

            {/* 8. Data Retention */}
            <section>
              <h2 className="text-xl font-black text-[#BFFF00] mb-4">8. Data Retention</h2>
              <p className="text-slate-300 leading-relaxed mb-4">We retain your information only as long as necessary to provide our services:</p>
              <ul className="space-y-2 mb-4 text-slate-300">
                <li className="flex items-start"><span className="text-[#BFFF00] mr-3 mt-1">●</span> Account data is kept as long as your account is active.</li>
                <li className="flex items-start"><span className="text-[#BFFF00] mr-3 mt-1">●</span> Match histories, tournament results, and league standings are retained indefinitely for historical platform records.</li>
                <li className="flex items-start"><span className="text-[#BFFF00] mr-3 mt-1">●</span> Chat logs are retained according to our moderation policies and then securely deleted.</li>
                <li className="flex items-start"><span className="text-[#BFFF00] mr-3 mt-1">●</span> You can request complete account and data deletion at any time.</li>
              </ul>
            </section>

            {/* 9. Your Rights */}
            <section>
              <h2 className="text-xl font-black text-[#BFFF00] mb-4">9. Your Rights</h2>
              <p className="text-slate-300 leading-relaxed mb-4">Depending on your location, you have the right to:</p>
              <ul className="space-y-2 mb-6 text-slate-300">
                <li className="flex items-start"><span className="text-[#BFFF00] mr-3 mt-1">●</span> Access the personal data we hold about you.</li>
                <li className="flex items-start"><span className="text-[#BFFF00] mr-3 mt-1">●</span> Correct inaccurate or incomplete data.</li>
                <li className="flex items-start"><span className="text-[#BFFF00] mr-3 mt-1">●</span> Request the deletion of your personal data.</li>
                <li className="flex items-start"><span className="text-[#BFFF00] mr-3 mt-1">●</span> Restrict or object to specific data processing activities.</li>
                <li className="flex items-start"><span className="text-[#BFFF00] mr-3 mt-1">●</span> Request data portability to transfer your data elsewhere.</li>
              </ul>
              <p className="text-slate-300 leading-relaxed mb-3">To exercise any of these rights, please contact us at:</p>
              <a href={`mailto:${supportEmail}`} className="inline-flex items-center gap-2 text-[#BFFF00] hover:text-white underline decoration-[#BFFF00] font-semibold transition-colors">
                <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" className="w-4 h-4">
                  <path d="M3 4a2 2 0 00-2 2v8a2 2 0 002 2h14a2 2 0 002-2V6a2 2 0 00-2-2H3zm14 2.22l-7 4.666-7-4.666V6h14v.22zM3 13.78l6.096-4.064L10 10.334l.904-.618L17 13.78v.22H3v-.22z" />
                </svg>
                {supportEmail}
              </a>
            </section>

            {/* 10. Security */}
            <section>
              <h2 className="text-xl font-black text-[#BFFF00] mb-4">10. Security</h2>
              <p className="text-slate-300 leading-relaxed mb-4">
                We implement robust technical and organizational security measures designed to protect your personal information.
              </p>
              <p className="text-slate-300 leading-relaxed">
                However, no electronic transmission over the internet or information storage technology can be guaranteed to be 100% secure. While we strive to protect your data, we cannot guarantee absolute security.
              </p>
            </section>

            {/* 11. Children's Privacy */}
            <section>
              <h2 className="text-xl font-black text-[#BFFF00] mb-4">11. Children&apos;s Privacy</h2>
              <p className="text-slate-300 leading-relaxed mb-4">
                Our platform and esports tournaments are not intended for children under the age of 13. We do not knowingly collect personal information from children under 13.
              </p>
              <p className="text-slate-300 leading-relaxed">
                If we become aware that we have collected personal data from a child under 13 without verifiable parental consent, we will take immediate steps to delete that information from our servers.
              </p>
            </section>

            {/* 12. Third-Party Services */}
            <section>
              <h2 className="text-xl font-black text-[#BFFF00] mb-4">12. Third-Party Services</h2>
              <p className="text-slate-300 leading-relaxed mb-4">Our application relies on integrated third-party services, including:</p>
              <ul className="space-y-2 mb-4 text-slate-300">
                <li className="flex items-start"><span className="text-[#BFFF00] mr-3 mt-1">●</span> Streaming &amp; Audio Infrastructure (LiveKit).</li>
                <li className="flex items-start"><span className="text-[#BFFF00] mr-3 mt-1">●</span> Payment Gateways (Flutterwave, Crossmint).</li>
                <li className="flex items-start"><span className="text-[#BFFF00] mr-3 mt-1">●</span> Identity Providers (Google Sign-In, Apple Sign-In).</li>
              </ul>
              <p className="text-slate-300 leading-relaxed">
                We are not responsible for the privacy practices or the content of these third-party platforms. We encourage you to read their respective privacy policies.
              </p>
            </section>

            {/* 13. Affiliate Links */}
            <section>
              <h2 className="text-xl font-black text-[#BFFF00] mb-4">13. Affiliate Links</h2>
              <p className="text-slate-300 leading-relaxed">
                Our platform or community feeds may contain affiliate links to gaming hardware or related services. Clicking on these links or making a purchase may result in a commission for us, at no extra cost to you.
              </p>
            </section>

            {/* 14. International Data Transfers */}
            <section>
              <h2 className="text-xl font-black text-[#BFFF00] mb-4">14. International Data Transfers</h2>
              <p className="text-slate-300 leading-relaxed">
                Your information, including personal data, may be transferred to—and maintained on—computers located outside of your state, province, country, or other governmental jurisdiction where the data protection laws may differ from those of your jurisdiction.
              </p>
            </section>

            {/* 15. Changes to This Policy */}
            <section>
              <h2 className="text-xl font-black text-[#BFFF00] mb-4">15. Changes to This Policy</h2>
              <p className="text-slate-300 leading-relaxed mb-4">
                We may update our Privacy Policy from time to time to reflect changes in our practices, technology, or legal requirements.
              </p>
              <p className="text-slate-300 leading-relaxed">
                We will notify you of any changes by updating the &quot;Effective Date&quot; at the top of this document and, in some cases, providing an in-app notification.
              </p>
            </section>

            {/* 16. Contact Us */}
            <section>
              <h2 className="text-xl font-black text-[#BFFF00] mb-4">16. Contact Us</h2>
              <p className="text-slate-300 leading-relaxed mb-3">
                If you have any questions or concerns about this Privacy Policy, please contact our support team at:
              </p>
              <a href={`mailto:${supportEmail}`} className="inline-flex items-center gap-2 text-[#BFFF00] hover:text-white underline decoration-[#BFFF00] font-semibold transition-colors">
                <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 20 20" fill="currentColor" className="w-4 h-4">
                  <path d="M3 4a2 2 0 00-2 2v8a2 2 0 002 2h14a2 2 0 002-2V6a2 2 0 00-2-2H3zm14 2.22l-7 4.666-7-4.666V6h14v.22zM3 13.78l6.096-4.064L10 10.334l.904-.618L17 13.78v.22H3v-.22z" />
                </svg>
                {supportEmail}
              </a>
            </section>
          </div>
        </div>
      </main>
    </div>
  );
}
