'use client'

import { useState } from 'react'
import { ScreenContainer } from '@/components/layouts/screen-container'
import { Button } from '@/components/ui/button'
import { Card, CardContent } from '@/components/ui/card'
import { X, CheckCircle } from 'lucide-react'
import Link from 'next/link'

type GuidanceMode = 'weight-health' | 'health-only'

export default function CaptureGuidancePage() {
  const [showGuidance, setShowGuidance] = useState(true)
  const [mode, setMode] = useState<GuidanceMode>('weight-health')

  const guidanceTips = {
    'weight-health': [
      'Position pig broadside to camera',
      'Ensure good lighting and clear view',
      'Keep camera at marked height',
      'Avoid shadows and reflections',
      'Include reference object in frame',
    ],
    'health-only': [
      'Focus on pig profile view',
      'Check for visible health indicators',
      'Ensure clear facial features visible',
      'Good lighting is essential',
      'Take multiple angles if needed',
    ],
  }

  return (
    <ScreenContainer showNav={false}>
      {/* Header with back button */}
      <div className='border-b border-border p-4'>
        <div className='flex items-center gap-2'>
          <Link href='/measurements'>
            <button className='p-1.5 hover:bg-muted rounded-lg transition-colors'>
              <X className='h-5 w-5' />
            </button>
          </Link>
          <h1 className='text-xl font-bold flex-1'>Capture Tips</h1>
        </div>
      </div>

      {/* Main Content */}
      <div className='mobile-viewport p-4 space-y-4 pb-24'>
        {/* Mode selector */}
        <div className='flex gap-2'>
          <button
            onClick={() => setMode('weight-health')}
            className={`flex-1 px-3 py-2 rounded-lg border transition-colors ${
              mode === 'weight-health'
                ? 'bg-primary text-primary-foreground border-primary'
                : 'border-border hover:bg-muted'
            }`}
          >
            <span className='text-sm font-medium'>Weight + Health</span>
          </button>
          <button
            onClick={() => setMode('health-only')}
            className={`flex-1 px-3 py-2 rounded-lg border transition-colors ${
              mode === 'health-only'
                ? 'bg-primary text-primary-foreground border-primary'
                : 'border-border hover:bg-muted'
            }`}
          >
            <span className='text-sm font-medium'>Health Only</span>
          </button>
        </div>

        {/* Guidance Card */}
        <Card>
          <CardContent className='p-4'>
            <h2 className='font-semibold mb-3'>Best Practices</h2>
            <ul className='space-y-2'>
              {guidanceTips[mode].map((tip, index) => (
                <li
                  key={index}
                  className='flex items-start gap-3 text-sm'
                >
                  <CheckCircle className='h-5 w-5 text-success flex-shrink-0 mt-0.5' />
                  <span>{tip}</span>
                </li>
              ))}
            </ul>
          </CardContent>
        </Card>

        {/* Example Section */}
        <div>
          <h3 className='text-sm font-semibold mb-2'>Example</h3>
          <Card>
            <CardContent className='p-4'>
              <div className='h-32 bg-muted rounded flex items-center justify-center text-sm text-muted-foreground'>
                {mode === 'weight-health'
                  ? 'Side view with reference object'
                  : 'Profile view for health assessment'}
              </div>
            </CardContent>
          </Card>
        </div>

        {/* Actions */}
        <div className='flex gap-2 pt-4'>
          <Button
            variant='secondary'
            size='lg'
            className='flex-1'
            onClick={() => setShowGuidance(false)}
            asChild
          >
            <Link href='/measurements'>Close</Link>
          </Button>
          <Button
            size='lg'
            className='flex-1'
            asChild
          >
            <Link href='/capture'>Start Capture</Link>
          </Button>
        </div>
      </div>
    </ScreenContainer>
  )
}
