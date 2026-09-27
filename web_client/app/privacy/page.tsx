import { LegalPage, H, SubH, P, B, EmailLink } from '@/components/legal/LegalDoc';

const APP_NAME = 'eSportlyic';
const SUPPORT_EMAIL = 'NASSARACORETECHVENTURES@GMAIL.COM';
const EFFECTIVE_DATE = '15 February 2026';

export const metadata = { title: 'Privacy Policy | eSportlyic' };

export default function PrivacyPolicyPage() {
  return (
    <LegalPage title="Privacy Policy" subtitle={`${APP_NAME} · Effective date: ${EFFECTIVE_DATE}`}>
      <H>1. Introduction</H>
      <P>Welcome to {APP_NAME}. This Privacy Policy explains how we collect, use, disclose, and safeguard your information when you visit our application and use our esports and tournament services.</P>
      <P>Please read this privacy policy carefully to understand our practices regarding your personal data.</P>

      <H>2. Information We Collect</H>
      <P>We collect information that you provide to us, information collected automatically, and information from third parties.</P>

      <SubH>Information you provide directly</SubH>
      <B>Account registration details (username, email, passwords).</B>
      <B>Profile information (team affiliation, bio, player avatars).</B>
      <B>Payment and premium transaction information.</B>
      <B>Communications with our support or arbitration teams.</B>

      <SubH>Information collected automatically</SubH>
      <P>When you use our services, we automatically collect:</P>
      <B>Device and usage information (IP address, device IDs, browser type).</B>
      <B>Matchmaking and gameplay analytics.</B>
      <B>Log data and crash reports.</B>
      <B>Interaction data with the global chat and community feeds.</B>

      <SubH>Information from third parties</SubH>
      <P>We may receive information about you from:</P>
      <B>Social media and authentication integrations (e.g., Google, Apple Sign-In).</B>
      <B>League organizers and tournament administrators.</B>
      <B>Verification and analytics providers.</B>
      <B>Payment processors (e.g., Flutterwave, Crossmint).</B>

      <H>3. Camera, Microphone, and Screen Recording</H>
      <P>To facilitate live esports features, our app may request access to:</P>
      <B><strong>Camera:</strong> For user profile photos or live session streaming.</B>
      <B><strong>Microphone:</strong> For in-platform voice chat and community discussions via LiveKit.</B>
      <B><strong>Screen Recording:</strong> For match verification, capturing highlights, and dispute resolution.</B>
      <P>We only access these hardware features with your explicit, real-time permission.</P>

      <H>4. Overlay Permission</H>
      <P>For competitive play, we may require overlay permissions to:</P>
      <B>Display critical tournament alerts over other apps.</B>
      <B>Show live match scores and fixture updates.</B>
      <B>Provide quick-access communication modules during gameplay.</B>

      <H>5. How We Use Your Information</H>
      <P>We use the information we collect to:</P>
      <B>Provide, operate, and maintain our application.</B>
      <B>Improve, personalize, and expand our matchmaking features.</B>
      <B>Process transactions, premiums, and marketplace coupon redemptions.</B>
      <B>Facilitate tournaments, knockout draws, and master leagues.</B>
      <B>Communicate with you regarding updates, announcements, and support.</B>
      <B>Enforce our terms, competition rules, and fair play policies.</B>
      <B>Prevent fraud, cheating, and ensure platform security.</B>

      <H>6. Data Storage and Services</H>
      <P>We prioritize the security and integrity of your data:</P>
      <B>Your data is stored on secure, industry-leading servers (including Firebase and Supabase).</B>
      <B>Media files, such as player photos and match posters, are securely hosted via Cloudinary.</B>
      <P>We use industry-standard encryption protocols to protect sensitive information during transit and at rest.</P>

      <H>7. Sharing of Information</H>
      <P>We do not sell your personal information. We may share information with:</P>
      <B>Service providers acting on our behalf (hosting, analytics, payments).</B>
      <B>League organizers and team admins (for roster verification and match administration).</B>
      <B>Other users (publicly visible profile data, squads, and match history).</B>
      <B>Legal authorities, if required by law or to protect our platform&apos;s integrity.</B>

      <H>8. Data Retention</H>
      <P>We retain your information only as long as necessary to provide our services:</P>
      <B>Account data is kept as long as your account is active.</B>
      <B>Match histories, tournament results, and league standings are retained indefinitely for historical platform records.</B>
      <B>Chat logs are retained according to our moderation policies and then securely deleted.</B>
      <B>You can request complete account and data deletion at any time.</B>

      <H>9. Your Rights</H>
      <P>Depending on your location, you have the right to:</P>
      <B>Access the personal data we hold about you.</B>
      <B>Correct inaccurate or incomplete data.</B>
      <B>Request the deletion of your personal data.</B>
      <B>Restrict or object to specific data processing activities.</B>
      <B>Request data portability to transfer your data elsewhere.</B>
      <P>To exercise any of these rights, please contact us at:</P>
      <EmailLink email={SUPPORT_EMAIL} />

      <H>10. Security</H>
      <P>We implement robust technical and organizational security measures designed to protect your personal information.</P>
      <P>However, no electronic transmission over the internet or information storage technology can be guaranteed to be 100% secure. While we strive to protect your data, we cannot guarantee absolute security.</P>

      <H>11. Children&apos;s Privacy</H>
      <P>Our platform and esports tournaments are not intended for children under the age of 13. We do not knowingly collect personal information from children under 13.</P>
      <P>If we become aware that we have collected personal data from a child under 13 without verifiable parental consent, we will take immediate steps to delete that information from our servers.</P>

      <H>12. Third-Party Services</H>
      <P>Our application relies on integrated third-party services, including:</P>
      <B>Streaming &amp; Audio Infrastructure (LiveKit).</B>
      <B>Payment Gateways (Flutterwave, Crossmint).</B>
      <B>Identity Providers (Google Sign-In, Apple Sign-In).</B>
      <P>We are not responsible for the privacy practices or the content of these third-party platforms. We encourage you to read their respective privacy policies.</P>

      <H>13. Affiliate Links</H>
      <P>Our platform or community feeds may contain affiliate links to gaming hardware or related services. Clicking on these links or making a purchase may result in a commission for us, at no extra cost to you.</P>

      <H>14. International Data Transfers</H>
      <P>Your information, including personal data, may be transferred to—and maintained on—computers located outside of your state, province, country, or other governmental jurisdiction where the data protection laws may differ from those of your jurisdiction.</P>

      <H>15. Changes to This Policy</H>
      <P>We may update our Privacy Policy from time to time to reflect changes in our practices, technology, or legal requirements.</P>
      <P>We will notify you of any changes by updating the &quot;Effective Date&quot; at the top of this document and, in some cases, providing an in-app notification.</P>

      <H>16. Contact Us</H>
      <P>If you have any questions or concerns about this Privacy Policy, please contact our support team at:</P>
      <EmailLink email={SUPPORT_EMAIL} />
    </LegalPage>
  );
}
