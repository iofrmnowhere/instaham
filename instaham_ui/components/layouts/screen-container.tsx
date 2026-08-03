'use client'

import * as React from "react"
import { BottomNav } from "@/components/ui/bottom-nav"
import { cn } from "@/lib/utils"

interface ScreenContainerProps {
  children: React.ReactNode
  header?: React.ReactNode
  footer?: React.ReactNode
  className?: string
  showNav?: boolean
}

export function ScreenContainer({
  children,
  header,
  footer,
  className,
  showNav = true,
}: ScreenContainerProps) {
  return (
    <div className="flex flex-col h-screen bg-background">
      {/* Header */}
      {header && (
        <div className="border-b border-border">
          {header}
        </div>
      )}

      {/* Main Content */}
      <main className={cn("flex-1 overflow-y-auto pb-20", className)}>
        {children}
      </main>

      {/* Footer */}
      {footer && (
        <div className="border-t border-border">
          {footer}
        </div>
      )}

      {/* Bottom Navigation */}
      {showNav && <BottomNav />}
    </div>
  )
}
