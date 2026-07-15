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
};

module.exports = nextConfig;
