'use client'

import { ScreenContainer } from '@/components/layouts/screen-container'
import { HealthStatusLabel } from '@/components/ui/health-status-label'
import { Button } from '@/components/ui/button'
import { Card, CardContent } from '@/components/ui/card'
import { ChevronLeft, AlertCircle, Lock } from 'lucide-react'
import Link from 'next/link'

export default function WeightBlockedPage() {
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

          {/* Weight Card - Blocked */}
          <Card className='p-4 border-orange-200 bg-orange-50'>
            <div className='flex items-start gap-3'>
              <div className='flex-shrink-0 mt-0.5'>
                <Lock className='h-5 w-5 text-orange-900' />
              </div>
              <div className='flex-1 min-w-0'>
                <p className='text-sm text-muted-foreground mb-1'>Weight</p>
                <p className='font-mono text-xl font-bold text-orange-900'>
                  Unavailable
                </p>
                <p className='text-xs text-orange-800 mt-2'>
                  Reference object was not detected. Include it in your next scan for weight measurement.
                </p>
                <Button
                  variant='outline'
                  size='sm'
                  className='mt-3 text-orange-900 border-orange-300 hover:bg-orange-100'
                >
                  Try Again
                </Button>
              </div>
            </div>
          </Card>

          {/* Health Card - Success */}
          <HealthStatusLabel
            label='Health Score'
            value={8.1}
            unit='/10'
            status='success'
            subtext='Good body condition detected'
          />
        </div>

        {/* Info Box */}
        <Card className='bg-blue-50 border-blue-200'>
          <CardContent className='p-4 flex gap-3'>
            <AlertCircle className='h-5 w-5 text-blue-900 flex-shrink-0 mt-0.5' />
            <p className='text-sm text-blue-900'>
              Health assessment is complete. Retake with your reference object to get weight measurements.
            </p>
          </CardContent>
        </Card>

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
            <Link href='/capture'>Retake</Link>
          </Button>
        </div>
      </div>
    </ScreenContainer>
  )
}
