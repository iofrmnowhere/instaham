import * as React from "react"
import { cn } from "@/lib/utils"
import { Badge } from "./badge"
import { Card } from "./card"

interface HealthStatusLabelProps {
  label: string
  value: number | string
  unit?: string
  status: "success" | "uncertain" | "blocked"
  subtext?: string
}

export const HealthStatusLabel = React.forwardRef<
  HTMLDivElement,
  HealthStatusLabelProps
>(({ label, value, unit, status, subtext }, ref) => {
  const statusBadgeMap = {
    success: "success",
    uncertain: "uncertain",
    blocked: "blocked",
  } as const

  return (
    <Card ref={ref} className="p-4">
      <div className="space-y-3">
        <div className="flex items-start justify-between">
          <div>
            <p className="text-sm text-muted-foreground mb-1">{label}</p>
            <div className="flex items-baseline gap-1">
              <p className="font-numeric text-3xl font-bold text-foreground">
                {value}
              </p>
              {unit && (
                <span className="text-sm text-muted-foreground">{unit}</span>
              )}
            </div>
          </div>
          <Badge variant={statusBadgeMap[status]}>
            {status === "success" && "Confirmed"}
            {status === "uncertain" && "Uncertain"}
            {status === "blocked" && "Blocked"}
          </Badge>
        </div>
        {subtext && (
          <p className="text-xs text-muted-foreground">{subtext}</p>
        )}
      </div>
    </Card>
  )
})
HealthStatusLabel.displayName = "HealthStatusLabel"
