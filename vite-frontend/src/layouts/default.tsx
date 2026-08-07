import { Navbar } from "@/components/navbar";
import bgImage from "@/images/bg.jpg";

export default function DefaultLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <div
      className="relative flex flex-col min-h-screen bg-white dark:bg-black"
      style={{
        backgroundImage: `url(${bgImage})`,
        backgroundSize: 'cover',
        backgroundPosition: 'center',
        backgroundAttachment: 'fixed',
      }}
    >
      {/* 背景遮罩，保证内容可读性 */}
      <div className="absolute inset-0 bg-white/75 dark:bg-black/70" />
      <Navbar />
      <main className="relative container mx-auto max-w-7xl px-4 sm:px-6 flex-grow pt-4 sm:pt-16">
        {children}
      </main>
    </div>
  );
}
