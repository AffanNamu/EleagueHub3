'use client';

export function PanelCard({
  title,
  icon,
  action,
  className = '',
  children,
}: {
  title?: string;
  icon?: React.ReactNode;
  action?: React.ReactNode;
  className?: string;
  children: React.ReactNode;
}) {
  return (
    <div className={`bg-[#0B1221] border border-[#1E293B] rounded-2xl overflow-hidden shadow-xl ${className}`}>
      {title && (
        <div className="flex items-center justify-between px-5 py-4 border-b border-[#1E293B]">
          <div className="flex items-center gap-2.5">
            {icon}
            <h3 className="font-bold text-white text-sm tracking-wide">{title}</h3>
          </div>
          {action}
        </div>
      )}
      <div className="p-5">{children}</div>
    </div>
  );
}
