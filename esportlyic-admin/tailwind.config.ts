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
        // Matches the mobile/web app's brand palette (lib/core/theme/app_theme.dart
        // and web_client/tailwind.config.ts) so the admin panel reads as the same
        // product — navy surfaces, lime accent.
        base: {
          DEFAULT: '#081120', // app: navyBg
          panel: '#182230', // app: darkCard
          raised: '#222E3D', // app: darkCardAlt
          border: '#334155', // app: darkBorder
        },
        ink: {
          primary: '#FFFFFF',
          secondary: '#94A3B8', // app: darkMutedText
          muted: '#64748B',
        },
        brand: {
          DEFAULT: '#B6FF00', // app: limeAccent
          soft: '#84CC16', // app: limeAccentDark
          faint: 'rgba(182, 255, 0, 0.12)',
        },
        signal: {
          success: '#22C55E', // app: completed-status green
          successFaint: 'rgba(34, 197, 94, 0.12)',
          warning: '#FFB020',
          warningFaint: 'rgba(255, 176, 32, 0.12)',
          danger: '#EF4444', // app: ownerRed
          dangerFaint: 'rgba(239, 68, 68, 0.12)',
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
