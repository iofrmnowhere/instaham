'use client'

import { ScreenContainer } from '@/components/layouts/screen-container'
import { HealthStatusLabel } from '@/components/ui/health-status-label'
import { Button } from '@/components/ui/button'
import { Card, CardContent } from '@/components/ui/card'
import { ChevronLeft, AlertCircle } from 'lucide-react'
import Link from 'next/link'

export default function UncertainResultPage() {
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

        {/* Alert */}
        <Card className='bg-amber-50 border-amber-200'>
          <CardContent className='p-4 flex items-start gap-3'>
            <AlertCircle className='h-5 w-5 text-amber-900 flex-shrink-0 mt-0.5' />
            <div>
              <p className='font-semibold text-sm text-amber-900'>
                Image Quality Issues Detected
              </p>
              <p className='text-xs text-amber-800 mt-1'>
                Lighting or pig positioning may affect accuracy. Review results carefully or retake.
              </p>
            </div>
          </CardContent>
        </Card>

        {/* Results */}
        <div className='space-y-3'>
          <h2 className='text-sm font-semibold px-1'>Measurements</h2>

          {/* Weight Card - Uncertain */}
          <HealthStatusLabel
            label='Weight'
            value={44.8}
            unit='kg'
            status='uncertain'
            subtext='Range: 43-46 kg (confidence: 72%)'
          />

          {/* Health Card - Uncertain */}
          <HealthStatusLabel
            label='Health Score'
            value={7.2}
            unit='/10'
            status='uncertain'
            subtext='Possible minor concerns - recommend review'
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
            <Link href='/measurements'>Retake</Link>
          </Button>
          <Button
            size='lg'
            className='flex-1'
            asChild
          >
            <Link href='/measurements'>Submit Anyway</Link>
          </Button>
        </div>

        {/* Help */}
        <Button
          variant='outline'
          size='lg'
          className='w-full'
        >
          Get Tips for Better Results
        </Button>
      </div>
    </ScreenContainer>
  )
}
