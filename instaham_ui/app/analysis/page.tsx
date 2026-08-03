'use client'

import { ScreenContainer } from '@/components/layouts/screen-container'
import { HealthStatusLabel } from '@/components/ui/health-status-label'
import { Button } from '@/components/ui/button'
import { Card, CardContent } from '@/components/ui/card'
import { ChevronLeft, Download } from 'lucide-react'
import Link from 'next/link'

export default function AnalysisPage() {
  return (
    <ScreenContainer showNav={false}>
      {/* Header with back button */}
      <div className='border-b border-border p-4'>
        <div className='flex items-center gap-2'>
          <Link href='/measurements'>
            <button className='p-1.5 hover:bg-muted rounded-lg transition-colors'>
              <ChevronLeft className='h-5 w-5' />
            </button>
          </Link>
          <h1 className='text-xl font-bold flex-1'>Analysis Results</h1>
        </div>
      </div>

      {/* Main Content */}
      <div className='mobile-viewport p-4 space-y-4 pb-24'>
        {/* Photo Thumbnail */}
        <Card>
          <CardContent className='p-0 h-40 bg-muted flex items-center justify-center rounded-lg'>
            <div className='text-center text-muted-foreground'>
              <div className='text-4xl mb-2'>📸</div>
              <p className='text-sm'>Scan Photo</p>
            </div>
          </CardContent>
        </Card>

        {/* Results */}
        <div className='space-y-3'>
          <h2 className='text-sm font-semibold px-1'>Measurements</h2>

          {/* Weight Card */}
          <HealthStatusLabel
            label='Weight'
            value={45.2}
            unit='kg'
            status='success'
            subtext='Healthy weight range for age'
          />

          {/* Health Card */}
          <HealthStatusLabel
            label='Health Score'
            value={8.5}
            unit='/10'
            status='success'
            subtext='Good body condition, no concerns detected'
          />
        </div>

        {/* Actions */}
        <div className='flex gap-2 pt-4'>
          <Button
            variant='secondary'
            size='lg'
            className='flex-1'
            asChild
          >
            <Link href='/measurements'>Done</Link>
          </Button>
          <Button
            size='lg'
            className='flex-1'
            asChild
          >
            <Link href='/measurements'>Retake</Link>
          </Button>
        </div>

        {/* Export */}
        <Button
          variant='outline'
          size='lg'
          className='w-full'
        >
          <Download className='h-4 w-4' />
          Export Report
        </Button>
      </div>
    </ScreenContainer>
  )
}
