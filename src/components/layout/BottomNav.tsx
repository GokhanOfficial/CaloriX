import { Link, useLocation } from "react-router-dom";
import { Home, PlusCircle, BarChart3, Settings } from "lucide-react";
import { cn } from "@/lib/utils";

import { useTranslation } from "react-i18next";

const navItems = [
  { to: "/", icon: Home, label: "nav.home" },
  { to: "/add", icon: PlusCircle, label: "nav.add" },
  { to: "/analytics", icon: BarChart3, label: "nav.analytics" },
  { to: "/settings", icon: Settings, label: "nav.settings" },
];

export function BottomNav() {
  const location = useLocation();
  const { t } = useTranslation();

  return (
    <nav className="fixed bottom-0 left-0 right-0 z-50 border-t border-border bg-card/95 backdrop-blur-lg safe-area-bottom">
      <div className="mx-auto flex max-w-lg items-center justify-around">
        {navItems.map(({ to, icon: Icon, label }) => {
          const isActive = location.pathname === to;
          return (
            <Link
              key={to}
              to={to}
              className={cn(
                "flex flex-1 flex-col items-center gap-1 py-3 transition-colors",
                isActive
                  ? "text-primary"
                  : "text-muted-foreground hover:text-foreground"
              )}
            >
              <Icon className={cn("h-6 w-6", isActive && "drop-shadow-glow")} />
              <span className="text-xs font-medium">{t(label)}</span>
            </Link>
          );
        })}
      </div>
    </nav>
  );
}
