// app/(admin)/dashboard/page.tsx
//
// Placeholder landing page for the auth-gate verification slice. Reaching
// this page means: the session cookie was valid, AND the signed-in UID is
// either the super admin or listed in app/admins.pricingAdmins[]. The real
// dashboard (stat cards, platform overview chart, admin control center,
// system alerts) is built in the next batch.

export default function DashboardPage() {
  return (
    <div className="panel p-6">
      <h1 className="font-display text-lg font-semibold text-ink-primary">
        Welcome to the Operations Center
      </h1>
      <p className="mt-1 text-sm text-ink-secondary">
        Authentication and authorization are wired end-to-end. Dashboard
        widgets, sidebar navigation, and the rest of the shell chrome are
        next.
      </p>
    </div>
  );
}
