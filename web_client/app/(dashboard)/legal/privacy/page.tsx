import { LegalPage, H, SubH, P, B, EmailLink } from '@/components/legal/LegalDoc';

// Mirrors lib/features/legal/privacy_policy_screen.dart section-for-section.
const APP_NAME = 'eSportlyic';
const SUPPORT_EMAIL = 'NASSARACORETECHVENTURES@GMAIL.COM';
const EFFECTIVE_DATE = '15 February 2026';

export const metadata = { title: 'Privacy Policy | eSportlyic' };

export default function PrivacyPolicyPage() {
  return (
    <LegalPage title="Privacy Policy" subtitle={`${APP_NAME} · Effective date: ${EFFECTIVE_DATE}`}>
      <H>1. Introduction</H>
      <P>This Privacy Policy explains how {APP_NAME} collects, uses, stores, and protects your information when you use our application.</P>
      <P>By using the App, you agree to the practices described in this Privacy Policy. If you do not agree, please do not use the App.</P>

      <H>2. Information We Collect</H>
      <P>We collect the following types of information:</P>

      <SubH>2.1 Information you provide directly</SubH>
      <B>Account information such as email address (via Google/Firebase Authentication or other login methods).</B>
      <B>Profile details such as team name, username, and profile photo.</B>
      <B>Content you upload within the App (such as images or league-related data).</B>
      <B>Support messages or communications you send to us.</B>

      <SubH>2.2 Information collected automatically</SubH>
      <P>When you use the App, we may automatically collect:</P>
      <B>Device information (model, operating system version).</B>
      <B>App version and usage data.</B>
      <B>Crash logs and diagnostic data (for performance and bug fixing).</B>
      <B>IP address and general network information.</B>

      <SubH>2.3 Information from third-party services</SubH>
      <P>If you sign in using third-party services (such as Google), we may receive:</P>
      <B>Unique user ID.</B>
      <B>Email address.</B>
      <B>Display name.</B>
      <B>Profile photo (if available).</B>
      <P>This data is provided in accordance with the third party&apos;s privacy settings and policies.</P>

      <H>3. Camera, Microphone, and Screen Recording</H>
      <P>The App may request access to sensitive device features only when you explicitly use related features:</P>
      <B>Camera access: used for profile images, streaming, or content creation.</B>
      <B>Microphone access: used for voice chat, live communication, or recording features.</B>
      <B>Screen recording (Media Projection): used only when you explicitly start screen sharing or live streaming sessions.</B>
      <P>We do not access your camera, microphone, or screen in the background without your active permission and interaction. You can disable these permissions at any time in your device settings.</P>

      <H>4. Overlay (Floating Window) Permission</H>
      <P>The App may display floating UI elements (such as chat heads, voice controls, or live session controls) using overlay permissions. These overlays:</P>
      <B>Only appear during active features (e.g., live sessions or voice tools).</B>
      <B>Do not collect personal data by themselves.</B>
      <B>Can be disabled by the user through settings or system permissions.</B>

      <H>5. How We Use Your Information</H>
      <P>We use collected information to:</P>
      <B>Provide and operate the App.</B>
      <B>Enable user accounts and authentication.</B>
      <B>Support league and profile features.</B>
      <B>Enable live interaction features (voice, streaming, etc.).</B>
      <B>Improve performance and fix bugs.</B>
      <B>Provide customer support.</B>
      <B>Ensure security and prevent fraud or abuse.</B>

      <H>6. Data Storage and Services</H>
      <P>We use trusted third-party services to operate the App, including:</P>
      <B>Google Firebase — Authentication, database, crash reporting.</B>
      <B>Cloudinary — image storage and delivery.</B>
      <P>These providers may process your data according to their own privacy policies.</P>

      <H>7. Sharing of Information</H>
      <P>We do not sell your personal data.</P>
      <P>We may share information only in the following cases:</P>
      <B>With service providers (Firebase, Cloudinary) to operate the App.</B>
      <B>When required by law or legal process.</B>
      <B>To protect user safety, security, or prevent abuse.</B>
      <B>In case of business transfer (merger or acquisition).</B>

      <H>8. Data Retention</H>
      <P>We keep your information only as long as necessary to:</P>
      <B>Provide App services.</B>
      <B>Comply with legal obligations.</B>
      <B>Resolve disputes.</B>
      <B>Enforce agreements.</B>
      <P>You may request deletion of your account and data at any time.</P>

      <H>9. Your Rights</H>
      <P>Depending on your location, you may have the right to:</P>
      <B>Access your personal data.</B>
      <B>Correct inaccurate data.</B>
      <B>Request deletion of your data.</B>
      <B>Withdraw consent.</B>
      <B>Object to data processing.</B>
      <P>To exercise these rights, contact us at:</P>
      <EmailLink email={SUPPORT_EMAIL} />

      <H>10. Security</H>
      <P>We implement appropriate technical and organizational measures to protect your data. However, no system is 100% secure, and we cannot guarantee absolute security.</P>
      <P>You are responsible for keeping your account credentials safe.</P>

      <H>11. Children&apos;s Privacy</H>
      <P>The App is not intended for children under 13 years of age (or the minimum legal age in your country). We do not knowingly collect data from children.</P>
      <P>If we discover such data has been collected, we will delete it promptly.</P>

      <H>12. Third-Party Services</H>
      <P>The App may include third-party services such as:</P>
      <B>Google/Firebase services.</B>
      <B>Cloudinary image hosting.</B>
      <B>External links or affiliate marketplaces.</B>
      <P>These services operate under their own privacy policies, which we encourage you to review.</P>

      <H>13. Affiliate Links</H>
      <P>Some links in the App may be affiliate links. This means we may earn a commission if you purchase through those links. This does not affect the price you pay.</P>

      <H>14. International Data Transfers</H>
      <P>Your data may be processed in countries outside your location where our service providers operate. We ensure appropriate safeguards are applied where required by law.</P>

      <H>15. Changes to This Policy</H>
      <P>We may update this Privacy Policy from time to time. Updates will be posted within the App, and the effective date will be revised.</P>
      <P>Continued use of the App means you accept the updated policy.</P>

      <H>16. Contact Us</H>
      <P>If you have any questions about this Privacy Policy, contact us:</P>
      <EmailLink email={SUPPORT_EMAIL} />
    </LegalPage>
  );
}
