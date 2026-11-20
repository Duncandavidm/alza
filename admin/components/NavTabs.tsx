"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { motion } from "framer-motion";

type Tab = { href: string; label: string; badge?: number };

/// Menu del panel con indicador de pestaña activa que se desliza entre
/// pestañas (framer-motion layoutId) y microinteracciones al tocar.
export default function NavTabs({ tabs }: { tabs: Tab[] }) {
  const pathname = usePathname();
  const isActive = (href: string) => (href === "/" ? pathname === "/" : pathname === href || pathname.startsWith(`${href}/`));

  return (
    <div className="nav-tabs" role="tablist" aria-label="Secciones del panel">
      {tabs.map((tab) => {
        const active = isActive(tab.href);
        return (
          <motion.div key={tab.href} className="nav-tab-wrap" whileTap={{ scale: 0.96 }}>
            <Link href={tab.href} className={active ? "nav-tab active" : "nav-tab"} role="tab" aria-selected={active}>
              {active && (
                <motion.span
                  layoutId="nav-active-pill"
                  className="nav-tab-indicator"
                  transition={{ type: "spring", stiffness: 500, damping: 38 }}
                />
              )}
              <span className="nav-tab-label">
                {tab.label}
                {tab.badge ? <span className="nav-badge">{tab.badge}</span> : null}
              </span>
            </Link>
          </motion.div>
        );
      })}
    </div>
  );
}
