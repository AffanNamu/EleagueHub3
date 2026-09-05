export default function UserDetailLoading() {
  return (
    <div className="grid grid-cols-1 gap-4 lg:grid-cols-3">
      <div className="space-y-4 lg:col-span-2">
        <div className="panel h-28 animate-pulse p-5" />
        <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
          <div className="panel h-20 animate-pulse p-4" />
          <div className="panel h-20 animate-pulse p-4" />
          <div className="panel h-20 animate-pulse p-4" />
          <div className="panel h-20 animate-pulse p-4" />
        </div>
        <div className="panel h-32 animate-pulse p-5" />
      </div>
      <div className="panel h-64 animate-pulse p-5" />
    </div>
  );
}
