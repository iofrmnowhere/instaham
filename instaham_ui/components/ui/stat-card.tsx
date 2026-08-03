import * as React from "react"
import { cn } from "@/lib/utils"
import { Card } from "./card"

interface StatCardProps extends React.HTMLAttributes<HTMLDivElement> {
  label: string
  value: string | number
  unit?: string
  icon?: React.ReactNode
  status?: "success" | "warning" | "error"
}

export const StatCard = React.forwardRef<HTMLDivElement, StatCardProps>(
  ({ label, value, unit, icon, status, className, ...props }, ref) => {
    return (
      <Card
        ref={ref}
        className={cn(
          "p-4 flex items-start gap-3 bg-white",
          status === "warning" && "bg-pink-tint border-pink-200",
          status === "error" && "bg-pink-tint border-pink-200",
          className
        )}
        {...props}
      >
        {icon && (
          <div className={cn(
            "flex-shrink-0",
            status === "warning" || status === "error" ? "text-primary" : "text-foreground"
          )}>
            {icon}
          </div>
        )}
        <div className="flex-1 min-w-0">
          <p className="text-sm text-muted-foreground mb-1">{label}</p>
          <div className="flex items-baseline gap-1">
            <p className="font-numeric text-2xl font-bold text-foreground">
              {value}
            </p>
            {unit && (
              <span className="text-sm text-muted-foreground">{unit}</span>
            )}
          </div>
        </div>
      </Card>
    )
  }
)
StatCard.displayName = "StatCard"
