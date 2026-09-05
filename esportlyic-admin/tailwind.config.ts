import type { Config } from 'tailwindcss';

const config: Config = {
  darkMode: ['class'],
  content: [
    './app/**/*.{ts,tsx}',
    './components/**/*.{ts,tsx}',
    './hooks/**/*.{ts,tsx}',
    './lib/**/*.{ts,tsx}',
  ],
  theme: {
    extend: {
      colors: {
        base: {
          DEFAULT: '#0B0F1A',
          panel: '#131926',
          raised: '#1B2333',
          border: '#232B3D',
        },
        ink: {
          primary: '#EDF1F7',
          secondary: '#8892A6',
          muted: '#5B6479',
        },
        brand: {
          DEFAULT: '#4C6FFF',
          soft: '#3A55CC',
          faint: 'rgba(76, 111, 255, 0.12)',
        },
        signal: {
          success: '#00E5A0',
          successFaint: 'rgba(0, 229, 160, 0.12)',
          warning: '#FFB020',
          warningFaint: 'rgba(255, 176, 32, 0.12)',
          danger: '#FF5470',
          dangerFaint: 'rgba(255, 84, 112, 0.12)',
          info: '#38BDF8',
          infoFaint: 'rgba(56, 189, 248, 0.12)',
        },
      },
      fontFamily: {
        // Deliberately system-font stacks, NOT next/font/google — this
        // project builds from a mobile/CI environment where fetching
        // fonts.googleapis.com at build time is unreliable and has
        // caused build failures (ETIMEDOUT). These stacks render close
        // enough to Space Grotesk/Inter without any network dependency.
        display: [
          '-apple-system', 'BlinkMacSystemFont', '"Segoe UI"', 'Roboto',
          '"Helvetica Neue"', 'Arial', 'sans-serif',
        ],
        sans: [
          '-apple-system', 'BlinkMacSystemFont', '"Segoe UI"', 'Roboto',
          '"Helvetica Neue"', 'Arial', 'sans-serif',
        ],
      },
      borderRadius: {
        sm: '6px',
        md: '10px',
        lg: '14px',
      },
      boxShadow: {
        none: 'none',
      },
    },
  },
  plugins: [],
};

export default config;
