'use client'

import { useState } from 'react'
import { ScreenContainer } from '@/components/layouts/screen-container'
import { Button } from '@/components/ui/button'
import { Card, CardContent } from '@/components/ui/card'
import { ChevronLeft, Shield, Lock } from 'lucide-react'
import Link from 'next/link'

export default function PrivacyPage() {
  const [consentAnonymized, setConsentAnonymized] = useState(true)
  const [consentTracking, setConsentTracking] = useState(false)
  const [isFirstScan, setIsFirstScan] = useState(false)

  return (
    <ScreenContainer showNav={!isFirstScan}>
      {/* Header */}
      {!isFirstScan && (
        <div className='border-b border-border p-4'>
          <div className='flex items-center gap-2'>
            <Link href='/health'>
              <button className='p-1.5 hover:bg-muted rounded-lg transition-colors'>
                <ChevronLeft className='h-5 w-5' />
              </button>
            </Link>
            <h1 className='text-xl font-bold flex-1'>Privacy & Consent</h1>
          </div>
        </div>
      )}

      <div className='mobile-viewport p-4 space-y-4 pb-24'>
        {isFirstScan && (
          <div className='text-center space-y-2 pt-8'>
            <div className='w-12 h-12 rounded-full bg-primary/10 mx-auto flex items-center justify-center'>
              <Shield className='h-6 w-6 text-primary' />
            </div>
            <h1 className='text-2xl font-bold'>Privacy & Consent</h1>
            <p className='text-sm text-muted-foreground'>
              Before we start, we need your consent
            </p>
          </div>
        )}

        {/* Consent Options */}
        <div className='space-y-3'>
          {/* Anonymized Data */}
          <Card>
            <CardContent className='p-4'>
              <div className='flex items-start gap-3'>
                <input
                  type='checkbox'
                  checked={consentAnonymized}
                  onChange={(e) => setConsentAnonymized(e.target.checked)}
                  className='mt-1 h-4 w-4 rounded border-border cursor-pointer'
                />
                <div className='flex-1'>
                  <p className='font-semibold text-sm mb-1'>
                    Allow Anonymized Image Use
                  </p>
                  <p className='text-xs text-muted-foreground'>
                    Help us improve accuracy by sharing anonymized scan images for model training
                  </p>
                </div>
              </div>
            </CardContent>
          </Card>

          {/* Usage Tracking */}
          <Card>
            <CardContent className='p-4'>
              <div className='flex items-start gap-3'>
                <input
                  type='checkbox'
                  checked={consentTracking}
                  onChange={(e) => setConsentTracking(e.target.checked)}
                  className='mt-1 h-4 w-4 rounded border-border cursor-pointer'
                />
                <div className='flex-1'>
                  <p className='font-semibold text-sm mb-1'>
                    Usage Analytics
                  </p>
                  <p className='text-xs text-muted-foreground'>
                    Allow us to collect usage data to improve the app experience
                  </p>
                </div>
              </div>
            </CardContent>
          </Card>
        </div>

        {/* Info */}
        <Card className='bg-primary/5 border-primary/20'>
          <CardContent className='p-4 flex gap-3'>
            <Lock className='h-5 w-5 text-primary flex-shrink-0 mt-0.5' />
            <p className='text-xs text-muted-foreground'>
              Your data is encrypted and stored securely. You can change these settings anytime in Settings.
            </p>
          </CardContent>
        </Card>

        {/* Privacy Policy Link */}
        <button className='w-full text-center text-sm text-primary hover:underline'>
          Read Our Privacy Policy
        </button>

        {/* Actions */}
        {isFirstScan ? (
          <div className='space-y-2 pt-4'>
            <Button
              size='lg'
              className='w-full'
              asChild
            >
              <Link href='/measurements'>
                I Agree & Start Scanning
              </Link>
            </Button>
            <Button
              variant='secondary'
              size='lg'
              className='w-full'
              asChild
            >
              <Link href='/'>Decline</Link>
            </Button>
          </div>
        ) : (
          <div className='flex gap-2 pt-4'>
            <Button
              variant='secondary'
              size='lg'
              className='flex-1'
              asChild
            >
              <Link href='/health'>Back</Link>
            </Button>
            <Button
              size='lg'
              className='flex-1'
              asChild
            >
              <Link href='/health'>Save</Link>
            </Button>
          </div>
        )}

        {/* Delete Records (Settings variant only) */}
        {!isFirstScan && (
          <Button
            variant='destructive'
            size='lg'
            className='w-full mt-4'
          >
            Delete All Records
          </Button>
        )}
      </div>
    </ScreenContainer>
  )
}
