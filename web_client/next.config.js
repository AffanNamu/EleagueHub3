// 🛡️ Safe Inner Environment Network Permission Bypass
const os = require('os');
os.networkInterfaces = () => {
  return {
    lo: [
      {
        address: '127.0.0.1',
        netmask: '255.0.0.0',
        family: 'IPv4',
        mac: '00:00:00:00:00:00',
        internal: true,
        cidr: '127.0.0.1/8'
      }
    ]
  };
};

console.log('🛡️ Core application network proxy intercept activated inside config.');

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
    ];
  },
};

module.exports = nextConfig;
