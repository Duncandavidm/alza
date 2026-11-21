"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { useEffect, useState } from "react";
import { AnimatePresence, motion } from "framer-motion";
import Icon from "./icons";

export type NavItem = { href: string; label: string; icon: string; badge?: number };
export type NavGroup = { title: string; items: NavItem[] };

/// Menu lateral del panel: secciones agrupadas, indicador animado en la
/// seccion activa y, en el celular, un cajon que se abre con el boton ☰.
export default function Sidebar({
  groups,
  logoutAction,
}: {
  groups: NavGroup[];
  logoutAction: () => Promise<void>;
}) {
  const pathname = usePathname();
  const [open, setOpen] = useState(false);
  const isActive = (href: string) => (href === "/" ? pathname === "/" : pathname === href || pathname.startsWith(`${href}/`));

  // Al navegar, el cajon del celular se cierra solo.
  useEffect(() => setOpen(false), [pathname]);

  const nav = (
    <>
      <Link href="/" className="sb-brand">
        {/* eslint-disable-next-line @next/next/no-img-element */}
        <img src="/monavi-mark.svg" alt="" aria-hidden="true" />
        <span>
          MonAvi <em>Admin</em>
        </span>
      </Link>
      <nav className="sb-nav" aria-label="Secciones del panel">
        {groups.map((group) => (
          <div key={group.title} className="sb-group">
            <div className="sb-group-title">{group.title}</div>
            {group.items.map((item) => {
              const active = isActive(item.href);
              return (
                <Link key={item.href} href={item.href} className={active ? "sb-item active" : "sb-item"} aria-current={active ? "page" : undefined}>
                  {active && (
                    <motion.span
                      layoutId="sb-active"
                      className="sb-active-bg"
                      transition={{ type: "spring", stiffness: 520, damping: 40 }}
                    />
                  )}
                  <Icon name={item.icon} size={18} className="sb-icon" />
                  <span className="sb-label">{item.label}</span>
                  {item.badge ? <span className="sb-badge">{item.badge}</span> : null}
                </Link>
              );
            })}
          </div>
        ))}
      </nav>
      <form action={logoutAction} className="sb-footer">
        <button type="submit" className="sb-logout">
          <Icon name="logout" size={18} />
          Salir
        </button>
      </form>
    </>
  );

  return (
    <>
      <aside className="sidebar">{nav}</aside>

      <header className="mobile-bar">
        <button type="button" className="icon-button" aria-label="Abrir menú" onClick={() => setOpen(true)}>
          <Icon name="menu" />
        </button>
        <Link href="/" className="sb-brand compact">
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src="/monavi-mark.svg" alt="" aria-hidden="true" />
          <span>MonAvi</span>
        </Link>
      </header>

      <AnimatePresence>
        {open && (
          <>
            <motion.div
              className="drawer-backdrop"
              initial={{ opacity: 0 }}
              animate={{ opacity: 1 }}
              exit={{ opacity: 0 }}
              onClick={() => setOpen(false)}
            />
            <motion.aside
              className="sidebar drawer"
              initial={{ x: -300 }}
              animate={{ x: 0 }}
              exit={{ x: -300 }}
              transition={{ type: "spring", stiffness: 380, damping: 38 }}
            >
              <button type="button" className="icon-button drawer-close" aria-label="Cerrar menú" onClick={() => setOpen(false)}>
                <Icon name="close" />
              </button>
              {nav}
            </motion.aside>
          </>
        )}
      </AnimatePresence>
    </>
  );
}
