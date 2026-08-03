'use client'

import { ScreenContainer } from '@/components/layouts/screen-container'
import { Button } from '@/components/ui/button'
import { Card, CardContent } from '@/components/ui/card'
import { AlertTriangle, ArrowRight } from 'lucide-react'
import Link from 'next/link'

export default function RejectResultPage() {
  return (
    <ScreenContainer showNav={false} showNav>
      <div className='mobile-viewport flex flex-col items-center justify-center min-h-screen px-4 space-y-6'>
        {/* Error Icon */}
        <div className='w-16 h-16 rounded-full bg-destructive/10 flex items-center justify-center'>
          <AlertTriangle className='h-8 w-8 text-destructive' />
        </div>

        {/* Main Message */}
        <div className='text-center space-y-2'>
          <h1 className='text-2xl font-bold'>Scan Failed</h1>
          <p className='text-muted-foreground'>
            We couldn&apos;t process this image. See details below.
          </p>
        </div>

        {/* Error Details Card */}
        <Card className='w-full bg-destructive/5 border-destructive/20'>
          <CardContent className='p-4 space-y-3'>
            <h3 className='font-semibold text-destructive'>What went wrong:</h3>
            <ul className='space-y-2 text-sm text-destructive/80'>
              <li className='flex gap-2'>
                <span>•</span>
                <span>Poor lighting or shadows detected</span>
              </li>
              <li className='flex gap-2'>
                <span>•</span>
                <span>Pig positioning not aligned with guide</span>
              </li>
              <li className='flex gap-2'>
                <span>•</span>
                <span>Reference object not clearly visible</span>
              </li>
            </ul>
          </CardContent>
        </Card>

        {/* Tips */}
        <Card>
          <CardContent className='p-4 space-y-3'>
            <h3 className='font-semibold'>How to fix it:</h3>
            <ul className='space-y-2 text-sm text-muted-foreground'>
              <li className='flex gap-2'>
                <Checkmark />
                <span>Move to a brighter location</span>
              </li>
              <li className='flex gap-2'>
                <Checkmark />
                <span>Position pig side-on to camera</span>
              </li>
              <li className='flex gap-2'>
                <Checkmark />
                <span>Ensure reference object is in frame</span>
              </li>
              <li className='flex gap-2'>
                <Checkmark />
                <span>Check camera height setting</span>
              </li>
            </ul>
          </CardContent>
        </Card>

        {/* Action Buttons */}
        <div className='w-full space-y-2 pt-4'>
          <Button
            size='lg'
            className='w-full'
            asChild
          >
            <Link href='/capture-guidance'>
              View Tips
              <ArrowRight className='h-4 w-4 ml-2' />
            </Link>
          </Button>
          <Button
            variant='secondary'
            size='lg'
            className='w-full'
            asChild
          >
            <Link href='/capture'>Retake Photo</Link>
          </Button>
        </div>
      </div>
    </ScreenContainer>
  )
}

function Checkmark() {
  return (
    <svg
      className='h-5 w-5 text-success flex-shrink-0'
      fill='none'
      viewBox='0 0 24 24'
      stroke='currentColor'
    >
      <path
        strokeLinecap='round'
        strokeLinejoin='round'
        strokeWidth={2}
        d='M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z'
      />
    </svg>
  )
}
