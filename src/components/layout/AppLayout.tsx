import { ReactNode } from "react";
import { Header } from "./Header";
import { BottomNav } from "./BottomNav";

interface AppLayoutProps {
  children: ReactNode;
  title?: string;
  hideNav?: boolean;
}

export function AppLayout({ children, title, hideNav = false }: AppLayoutProps) {
  return (
    <div className="flex min-h-screen flex-col bg-background">
      <Header title={title} />
      <main className="flex-1 pb-20">{children}</main>
      {!hideNav && <BottomNav />}
    </div>
  );
}
