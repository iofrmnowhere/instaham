'use client'

import { useState } from 'react'
import { ScreenContainer } from '@/components/layouts/screen-container'
import { Button } from '@/components/ui/button'
import { Camera, Settings, RotateCcw } from 'lucide-react'
import { HeightModeSettings } from '@/components/screens/capture/height-mode-settings'
import { HeightModeAlignment } from '@/components/screens/capture/height-mode-alignment'
import { ReferenceObjectPicker } from '@/components/screens/capture/reference-object-picker'
import { ReferenceObjectDetails } from '@/components/screens/capture/reference-object-details'

type CaptureMode = 'camera' | 'heightSettings' | 'heightAlignment' | 'refPicker' | 'refDetails'

export default function CapturePage() {
  const [mode, setMode] = useState<CaptureMode>('camera')
  const [heightValue, setHeightValue] = useState<number>(0)
  const [measurementMode, setMeasurementMode] = useState<'height' | 'reference'>('height')

  const handleHeightModeClick = () => {
    setMeasurementMode('height')
    setMode('heightSettings')
  }

  const handleReferenceModeClick = () => {
    setMeasurementMode('reference')
    setMode('refPicker')
  }

  return (
    <ScreenContainer showNav={false}>
      {mode === 'camera' && (
        <CameraView
          onHeightMode={handleHeightModeClick}
          onReferenceMode={handleReferenceModeClick}
        />
      )}
      {mode === 'heightSettings' && (
        <HeightModeSettings
          value={heightValue}
          onChange={setHeightValue}
          onNext={() => setMode('heightAlignment')}
          onBack={() => setMode('camera')}
        />
      )}
      {mode === 'heightAlignment' && (
        <HeightModeAlignment
          onConfirm={() => setMode('camera')}
          onBack={() => setMode('heightSettings')}
        />
      )}
      {mode === 'refPicker' && (
        <ReferenceObjectPicker
          onSelect={(type) => {
            if (type === 'custom') {
              setMode('refDetails')
            }
          }}
          onBack={() => setMode('camera')}
        />
      )}
      {mode === 'refDetails' && (
        <ReferenceObjectDetails
          onConfirm={() => setMode('camera')}
          onBack={() => setMode('refPicker')}
        />
      )}
    </ScreenContainer>
  )
}

function CameraView({
  onHeightMode,
  onReferenceMode,
}: {
  onHeightMode: () => void
  onReferenceMode: () => void
}) {
  return (
    <div className='flex flex-col h-full bg-black'>
      {/* Camera Preview Area */}
      <div className='flex-1 bg-black flex items-center justify-center relative'>
        <div className='text-center text-white'>
          <Camera className='h-16 w-16 mx-auto mb-4 opacity-50' />
          <p className='text-sm opacity-75'>Camera Preview</p>
        </div>
        {/* Crosshair overlay */}
        <div className='absolute inset-0 flex items-center justify-center pointer-events-none'>
          <div className='w-32 h-32 border-2 border-white/30 rounded-lg'></div>
        </div>
      </div>

      {/* Controls */}
      <div className='bg-foreground/5 border-t border-border p-4 space-y-3'>
        <div className='flex gap-3'>
          <Button
            onClick={onHeightMode}
            variant='default'
            size='lg'
            className='flex-1'
          >
            Height Mode
          </Button>
          <Button
            onClick={onReferenceMode}
            variant='outline'
            size='lg'
            className='flex-1'
          >
            Reference Mode
          </Button>
        </div>
        <Button variant='tertiary' className='w-full' size='sm'>
          <RotateCcw className='h-4 w-4' />
          Reset
        </Button>
      </div>
    </div>
  )
}
