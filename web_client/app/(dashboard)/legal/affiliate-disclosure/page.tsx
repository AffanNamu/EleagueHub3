import { LegalPage, H, P, B } from '@/components/legal/LegalDoc';

// Mirrors lib/features/legal/affiliate_disclosure_screen.dart section-for-section.
const APP_NAME = 'eSportlyic';
const SUPPORT_EMAIL = 'NASSARACORETECHVENTURES@GMAIL.COM';
const EFFECTIVE_DATE = '15 February 2026';

export const metadata = { title: 'Affiliate Disclosure | eSportlyic' };

export default function AffiliateDisclosurePage() {
  return (
    <LegalPage title="Affiliate Disclosure" subtitle={`Effective date: ${EFFECTIVE_DATE}`}>
      <P>
        {APP_NAME} participates in affiliate marketing programs. This means some links shown in the App may be
        &quot;affiliate links.&quot; If you click an affiliate link and make a purchase from a third-party store, we
        may earn a commission or referral fee.
      </P>

      <H>What this means for you</H>
      <B>You pay no extra cost. Affiliate commissions are paid by the third-party store, not by you.</B>
      <B>Prices and availability are determined by external partner stores and may change at any time.</B>
      <B>Transactions happen on external partner sites/apps. The partner store processes payments, shipping, refunds, warranties, and customer service.</B>

      <H>Partner store responsibility</H>
      <P>
        Because purchases are completed on third-party platforms, {APP_NAME} is not responsible for issues related to
        orders, payments, shipping, returns, refunds, or product quality. Any dispute or request regarding a purchase
        must be addressed directly with the partner store or merchant.
      </P>

      <H>Editorial independence</H>
      <P>
        Where marketplace content is shown, we aim to present products and links that may be useful to users. Any
        affiliate relationship does not guarantee that all products are reviewed, endorsed, or recommended by us, and
        you should always conduct your own research before purchasing.
      </P>

      <H>Questions</H>
      <P>If you have questions about this Affiliate Disclosure, contact us at: {SUPPORT_EMAIL}</P>
    </LegalPage>
  );
}
