import { cn } from '@/lib/utils';
import React from 'react';

interface GlassProps extends React.HTMLAttributes<HTMLDivElement> {
  children: React.ReactNode;
  intensity?: 'low' | 'medium' | 'high';
}

export const Glass: React.FC<GlassProps> = ({ children, className, intensity = 'medium', ...props }) => {
  const blurClasses = {
    low: 'backdrop-blur-sm',
    medium: 'backdrop-blur-md',
    high: 'backdrop-blur-xl',
  };

  return (
    <div
      className={cn(
        'bg-glass-gradient border border-white/10 shadow-xl rounded-3xl',
        blurClasses[intensity],
        className
      )}
      {...props}
    >
      {children}
    </div>
  );
};
