'use client'

import { ScreenContainer } from "@/components/layouts/screen-container"
import { Card, CardHeader, CardTitle, CardContent } from "@/components/ui/card"
import { Heart } from "lucide-react"

export default function HealthPage() {
  return (
    <ScreenContainer
      header={
        <div className="p-4 mobile-viewport">
          <h1 className="text-2xl font-bold">Health</h1>
          <p className="text-sm text-muted-foreground">Monitor herd health status</p>
        </div>
      }
    >
      <div className="mobile-viewport p-4 space-y-4 flex flex-col items-center justify-center min-h-[50vh]">
        <div className="text-center space-y-4">
          <div className="mx-auto w-16 h-16 bg-primary/10 rounded-full flex items-center justify-center">
            <Heart className="h-8 w-8 text-primary" />
          </div>
          <h2 className="text-xl font-semibold">No Health Alerts</h2>
          <p className="text-sm text-muted-foreground max-w-xs">
            All animals in your herd are in good health status
          </p>
        </div>
      </div>
    </ScreenContainer>
  )
}
