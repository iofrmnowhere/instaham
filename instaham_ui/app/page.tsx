'use client'

import { ScreenContainer } from "@/components/layouts/screen-container"
import { StatCard } from "@/components/ui/stat-card"
import { Card, CardHeader, CardTitle, CardContent } from "@/components/ui/card"
import { ChevronRight, AlertCircle, Zap } from "lucide-react"

export default function HomePage() {
  const recentScans = [
    { id: 1, pig: "Pig #042", date: "2 hours ago", weight: "45kg", health: "Good" },
    { id: 2, pig: "Pig #038", date: "4 hours ago", weight: "42kg", health: "Monitor" },
    { id: 3, pig: "Pig #035", date: "Yesterday", weight: "48kg", health: "Good" },
  ]

  return (
    <ScreenContainer
      header={
        <div className="p-4 mobile-viewport">
          <h1 className="text-2xl font-bold">INSTAHAM</h1>
          <p className="text-sm text-muted-foreground">Farm Health Monitoring</p>
        </div>
      }
    >
      <div className="mobile-viewport p-4 space-y-4">
        {/* Welcome Card */}
        <Card className="bg-primary text-primary-foreground border-primary">
          <CardContent className="p-4">
            <h2 className="text-lg font-semibold mb-2">Welcome Back</h2>
            <p className="text-sm opacity-90 mb-3">Tap below to start a new scan</p>
            <button className="bg-white text-primary px-6 py-2 rounded-full font-medium text-sm hover:bg-gray-100 transition-colors">
              Start Capture
            </button>
          </CardContent>
        </Card>

        {/* Stat Cards */}
        <div className="grid grid-cols-2 gap-3">
          <StatCard
            label="Scans Today"
            value="12"
            icon={<Zap className="h-5 w-5" />}
          />
          <StatCard
            label="Health Alerts"
            value="2"
            icon={<AlertCircle className="h-5 w-5" />}
            status="warning"
          />
        </div>

        {/* Recent Scans */}
        <div>
          <h3 className="text-sm font-semibold mb-3 px-1">Recent Scans</h3>
          <div className="space-y-2">
            {recentScans.map((scan) => (
              <Card key={scan.id} className="hover:shadow-md cursor-pointer transition-shadow">
                <CardContent className="p-4 flex items-center justify-between">
                  <div className="flex-1 min-w-0">
                    <p className="font-semibold text-sm">{scan.pig}</p>
                    <p className="text-xs text-muted-foreground">{scan.date}</p>
                  </div>
                  <div className="flex items-center gap-3 text-right">
                    <div>
                      <p className="font-mono font-bold text-sm">{scan.weight}</p>
                      <p className="text-xs text-muted-foreground">{scan.health}</p>
                    </div>
                    <ChevronRight className="h-5 w-5 text-muted-foreground flex-shrink-0" />
                  </div>
                </CardContent>
              </Card>
            ))}
          </div>
        </div>
      </div>
    </ScreenContainer>
  )
}
