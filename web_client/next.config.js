/** @type {import('next').NextConfig} */
const nextConfig = {
  reactStrictMode: true,
  /* Add additional project settings here if needed */

  // Android App Links (assetlinks.json) and iOS Universal Links
  // (apple-app-site-association) verification both require these files
  // be served with Content-Type: application/json — the extensionless
  // apple-app-site-association in particular would otherwise be served
  // as application/octet-stream by default static-file serving, which
  // Apple's verifier (swcd) is not guaranteed to accept.
  async headers() {
    return [
      {
        source: '/.well-known/apple-app-site-association',
        headers: [{ key: 'Content-Type', value: 'application/json' }],
      },
      {
        source: '/.well-known/assetlinks.json',
        headers: [{ key: 'Content-Type', value: 'application/json' }],
      },
      {
        // Deliberately NOT a Content-Security-Policy here -- getting one
        // wrong (Firebase Auth popups, Google OAuth, Cloudinary images,
        // etc. all need their own allowances) risks silently breaking
        // login, which this sandbox has no way to verify live. These four
        // are safe, low-risk defaults with no such dependency on what the
        // app happens to load.
        source: '/:path*',
        headers: [
          { key: 'X-Frame-Options', value: 'SAMEORIGIN' },
          { key: 'X-Content-Type-Options', value: 'nosniff' },
          { key: 'Referrer-Policy', value: 'strict-origin-when-cross-origin' },
          { key: 'Strict-Transport-Security', value: 'max-age=63072000; includeSubDomains' },
        ],
      },
    ];
  },
};

module.exports = nextConfig;
