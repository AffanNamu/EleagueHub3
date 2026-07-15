import type { Config } from 'tailwindcss';

const config: Config = {
  content: [
    './pages/**/*.{js,ts,jsx,tsx,mdx}',
    './components/**/*.{js,ts,jsx,tsx,mdx}',
    './app/**/*.{js,ts,jsx,tsx,mdx}',
  ],
  darkMode: 'class',
  theme: {
    extend: {
      colors: {
        brand: {
          navy: '#081120',
          navySoft: '#0F172A',
          lime: '#B6FF00',
          limeDark: '#84CC16',
          red: '#EF4444',
          surface: 'rgba(255, 255, 255, 0.05)',
          surfaceDark: 'rgba(0, 0, 0, 0.2)',
        }
      },
      backgroundImage: {
        'glass-gradient': 'linear-gradient(135deg, rgba(255,255,255,0.05) 0%, rgba(255,255,255,0.01) 100%)',
        'glass-gradient-dark': 'linear-gradient(135deg, rgba(0,0,0,0.2) 0%, rgba(0,0,0,0.05) 100%)',
      }
    },
  },
  plugins: [],
};

export default config;
