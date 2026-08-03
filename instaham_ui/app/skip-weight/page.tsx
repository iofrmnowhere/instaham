'use client'

import { ScreenContainer } from '@/components/layouts/screen-container'
import { Button } from '@/components/ui/button'
import { Card, CardContent } from '@/components/ui/card'
import { AlertCircle } from 'lucide-react'
import Link from 'next/link'

export default function SkipWeightPage() {
  return (
    <ScreenContainer showNav={false}>
      <div className='mobile-viewport flex flex-col items-center justify-center min-h-screen px-4'>
        <div className='fixed inset-0 bg-black/50 flex items-end z-50'>
          <div className='w-full bg-background rounded-t-2xl p-4 space-y-4 animate-in slide-in-from-bottom'>
            {/* Icon */}
            <div className='flex justify-center mb-2'>
              <div className='w-12 h-12 rounded-full bg-amber-100 flex items-center justify-center'>
                <AlertCircle className='h-6 w-6 text-amber-900' />
              </div>
            </div>

            {/* Content */}
            <div className='text-center space-y-2'>
              <h2 className='text-lg font-bold'>Skip Weight Measurement?</h2>
              <p className='text-sm text-muted-foreground'>
                You can still capture health information without a reference object
              </p>
            </div>

            {/* Info Card */}
            <Card>
              <CardContent className='p-4 space-y-3'>
                <div>
                  <h3 className='font-semibold text-sm mb-2'>You will get:</h3>
                  <ul className='space-y-1 text-sm text-muted-foreground'>
                    <li className='flex gap-2'>
                      <span className='text-success'>✓</span>
                      <span>Health score and indicators</span>
                    </li>
                    <li className='flex gap-2'>
                      <span className='text-destructive'>✗</span>
                      <span>Weight estimation</span>
                    </li>
                  </ul>
                </div>
              </CardContent>
            </Card>

            {/* Buttons */}
            <div className='flex gap-2'>
              <Button
                variant='secondary'
                size='lg'
                className='flex-1'
                asChild
              >
                <Link href='/capture'>
                  Keep Reference Mode
                </Link>
              </Button>
              <Button
                size='lg'
                className='flex-1'
                asChild
              >
                <Link href='/measurements'>
                  Skip Weight
                </Link>
              </Button>
            </div>

            <p className='text-xs text-muted-foreground text-center'>
              You can always retake with a reference object later
            </p>
          </div>
        </div>
      </div>
    </ScreenContainer>
  )
}
