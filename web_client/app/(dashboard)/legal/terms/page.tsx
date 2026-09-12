import { LegalPage, H, SubH, P, B, EmailLink } from '@/components/legal/LegalDoc';

// Mirrors lib/features/legal/terms_of_service_screen.dart section-for-section.
const APP_NAME = 'eSportlyic';
const SUPPORT_EMAIL = 'NASSARACORETECHVENTURES@GMAIL.COM';
const EFFECTIVE_DATE = '15 February 2026';

export const metadata = { title: 'Terms of Service | eSportlyic' };

export default function TermsOfServicePage() {
  return (
    <LegalPage title="Terms of Service" subtitle={`${APP_NAME} · Effective date: ${EFFECTIVE_DATE}`}>
      <H>1. Acceptance of Terms</H>
      <P>By downloading, accessing, or using {APP_NAME} (&quot;the App&quot;), you agree to be bound by these Terms of Service. If you do not agree, you must not use the App.</P>

      <H>2. Eligibility</H>
      <P>You must be at least 13 years old (or the minimum legal age in your country) to use the App. By using the App, you confirm that you meet this requirement.</P>
      <P>If you are using the App on behalf of an organization, you confirm that you have authority to bind that organization to these Terms.</P>

      <H>3. Account Registration and Security</H>
      <P>Some features require an account created through Firebase Authentication or supported login providers.</P>
      <P>You agree to:</P>
      <B>Provide accurate and complete information.</B>
      <B>Keep your login credentials secure.</B>
      <B>Accept responsibility for all activity under your account.</B>
      <P>We reserve the right to suspend or terminate accounts suspected of abuse, fraud, or violation of these Terms.</P>

      <H>4. Use of the App</H>
      <P>You agree to use the App only for lawful purposes and in a way that does not harm, disrupt, or interfere with other users or the App.</P>
      <P>You must not:</P>
      <B>Use the App for illegal, harmful, or fraudulent activity.</B>
      <B>Attempt unauthorized access to systems or accounts.</B>
      <B>Interfere with App performance or security.</B>
      <B>Upload malicious code or content.</B>
      <B>Harass, abuse, or threaten other users.</B>
      <B>Violate intellectual property or privacy rights.</B>

      <H>5. Camera, Microphone, and Screen Recording Use</H>
      <P>The App may request access to:</P>
      <B>Camera — for profile images, content creation, or streaming features.</B>
      <B>Microphone — for voice communication, live interaction, or recording features.</B>
      <B>Screen recording (Media Projection) — for live streaming, screen sharing, or gameplay capture.</B>
      <P>These features:</P>
      <B>Are only activated when you explicitly start them.</B>
      <B>Do not run in the background without your action.</B>
      <B>Can be disabled at any time through device settings or in-app controls.</B>

      <H>6. Overlay (Floating Window) Features</H>
      <P>The App may use overlay permissions to display floating elements such as:</P>
      <B>Chat heads.</B>
      <B>Voice controls.</B>
      <B>Live session tools.</B>
      <P>These overlays:</P>
      <B>Appear only during active use of supported features.</B>
      <B>Do not collect personal data by themselves.</B>
      <B>Can be disabled by the user at any time.</B>

      <H>7. User Content</H>
      <P>You are responsible for any content you upload, create, or share through the App, including:</P>
      <B>Profile information.</B>
      <B>Images.</B>
      <B>League data or content.</B>
      <P>You confirm that:</P>
      <B>You own or have permission to use the content you upload.</B>
      <B>Your content does not violate any laws or third-party rights.</B>
      <P>We may remove content that violates these Terms or applicable policies.</P>

      <H>8. Leagues and Community Features</H>
      <P>The App allows users to create and manage leagues and participate in community activities.</P>
      <P>You are responsible for how you organize and manage your leagues, including compliance with applicable laws and community standards.</P>
      <P>We are not responsible for disputes between users or league participants.</P>

      <H>9. Marketplace and Affiliate Links</H>
      <P>The App may display marketplace content and external links.</P>
      <P>Some links may be affiliate links, meaning we may earn a commission if you make a purchase.</P>
      <SubH>Important:</SubH>
      <B>Purchases are made on third-party websites.</B>
      <B>We are not responsible for pricing, delivery, refunds, or product quality.</B>
      <B>Third-party services are governed by their own terms.</B>

      <H>10. Third-Party Services</H>
      <P>The App relies on third-party services including:</P>
      <B>Google Firebase — authentication, database, crash reporting.</B>
      <B>Cloudinary — image storage and delivery.</B>
      <B>External websites or partners linked in marketplace content.</B>
      <P>We are not responsible for third-party services or their policies.</P>

      <H>11. Intellectual Property</H>
      <P>All App content, design, features, and software are owned by {APP_NAME} or its licensors.</P>
      <P>You are granted a limited, non-exclusive, non-transferable license to use the App for personal or internal purposes.</P>
      <P>You may not:</P>
      <B>Copy or modify the App.</B>
      <B>Reverse engineer or extract source code.</B>
      <B>Distribute or resell the App.</B>

      <H>12. Termination</H>
      <P>We may suspend or terminate your access to the App if:</P>
      <B>You violate these Terms.</B>
      <B>You misuse the App.</B>
      <B>Your actions create risk for users or the platform.</B>
      <P>You may stop using the App at any time.</P>

      <H>13. Disclaimer of Warranties</H>
      <P>The App is provided &quot;as is&quot; and &quot;as available&quot; without warranties of any kind.</P>
      <P>We do not guarantee:</P>
      <B>That the App will be error-free.</B>
      <B>That the App will be uninterrupted.</B>
      <B>That all features will function at all times.</B>

      <H>14. Limitation of Liability</H>
      <P>To the maximum extent permitted by law, we are not liable for:</P>
      <B>Indirect or incidental damages.</B>
      <B>Loss of data, revenue, or profits.</B>
      <B>App downtime or failure.</B>
      <P>Our total liability will not exceed the amount you paid (if any) to use the App in the last 12 months.</P>

      <H>15. Indemnification</H>
      <P>You agree to indemnify and hold harmless {APP_NAME} from any claims, damages, or expenses arising from:</P>
      <B>Your use of the App.</B>
      <B>Your content.</B>
      <B>Your violation of these Terms.</B>

      <H>16. Data Protection and Privacy</H>
      <P>Your use of the App is also governed by our Privacy Policy, which explains how we collect and process data including:</P>
      <B>Authentication data.</B>
      <B>Device information.</B>
      <B>Camera, microphone, and screen recording usage.</B>
      <B>Uploaded images and content.</B>

      <H>17. Changes to Terms</H>
      <P>We may update these Terms at any time. Updates will be posted within the App with a revised effective date.</P>
      <P>Continued use of the App means you accept the updated Terms.</P>

      <H>18. Governing Law</H>
      <P>These Terms are governed by the applicable laws of the jurisdiction in which the App operates, unless otherwise required by local law.</P>

      <H>19. Contact Information</H>
      <P>For questions about these Terms, contact us:</P>
      <EmailLink email={SUPPORT_EMAIL} />
    </LegalPage>
  );
}
