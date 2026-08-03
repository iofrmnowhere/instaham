'use client'

import * as React from "react"
import Link from "next/link"
import { usePathname } from "next/navigation"
import { Home, Ruler, BarChart3, Heart } from "lucide-react"
import { cn } from "@/lib/utils"

const navItems = [
  { href: "/", label: "Home", icon: Home },
  { href: "/measurements", label: "Measurements", icon: Ruler },
  { href: "/analytics", label: "Analytics", icon: BarChart3 },
  { href: "/health", label: "Health", icon: Heart },
]

export function BottomNav() {
  const pathname = usePathname()

  return (
    <nav className="fixed bottom-0 left-0 right-0 bg-sidebar border-t border-border">
      <div className="mobile-viewport flex h-14 items-center justify-between px-1">
        {navItems.map((item) => {
          const Icon = item.icon
          const isActive = pathname === item.href
          return (
            <Link
              key={item.href}
              href={item.href}
              className={cn(
                "flex flex-1 flex-col items-center justify-center gap-0.5 px-2 py-1.5 rounded transition-colors relative",
                isActive
                  ? "text-primary"
                  : "text-muted-foreground hover:text-foreground"
              )}
            >
              <Icon className="h-5 w-5" />
              <span className="text-xs font-medium">{item.label}</span>
              {isActive && (
                <div className="absolute bottom-0 w-1 h-0.5 bg-primary rounded-full" />
              )}
            </Link>
          )
        })}
      </div>
    </nav>
  )
}
