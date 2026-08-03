'use client'

import { ScreenContainer } from "@/components/layouts/screen-container"
import { Card, CardHeader, CardTitle, CardContent } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Camera } from "lucide-react"

export default function MeasurementsPage() {
  return (
    <ScreenContainer
      header={
        <div className="p-4 mobile-viewport">
          <h1 className="text-2xl font-bold">Measurements</h1>
          <p className="text-sm text-muted-foreground">Capture and track measurements</p>
        </div>
      }
    >
      <div className="mobile-viewport p-4 space-y-4 flex flex-col items-center justify-center min-h-[50vh]">
        <div className="text-center space-y-4">
          <div className="mx-auto w-16 h-16 bg-primary/10 rounded-full flex items-center justify-center">
            <Camera className="h-8 w-8 text-primary" />
          </div>
          <h2 className="text-xl font-semibold">Start a New Scan</h2>
          <p className="text-sm text-muted-foreground max-w-xs">
            Position your pig and tap below to begin capturing measurements
          </p>
          <Button size="lg" className="w-full mt-4">
            Start Capture
          </Button>
        </div>
      </div>
    </ScreenContainer>
  )
}
