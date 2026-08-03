import { useState } from 'react'
import { Button } from '@/components/ui/button'
import { Card, CardContent } from '@/components/ui/card'
import { ChevronLeft, Upload, X } from 'lucide-react'

interface ReferenceObjectDetailsProps {
  onConfirm: () => void
  onBack: () => void
}

export function ReferenceObjectDetails({
  onConfirm,
  onBack,
}: ReferenceObjectDetailsProps) {
  const [imageUploaded, setImageUploaded] = useState(false)
  const [length, setLength] = useState('')
  const [width, setWidth] = useState('')

  return (
    <div className='fixed inset-0 bg-black/50 flex items-end z-50'>
      <div className='w-full bg-background rounded-t-2xl p-4 space-y-4 animate-in slide-in-from-bottom max-h-[90vh] overflow-y-auto'>
        <div className='flex items-center gap-2 mb-2'>
          <button
            onClick={onBack}
            className='p-1.5 hover:bg-muted rounded-lg transition-colors'
          >
            <ChevronLeft className='h-5 w-5' />
          </button>
          <h2 className='text-lg font-semibold flex-1'>Reference Characteristics</h2>
        </div>

        <div className='space-y-4'>
          {/* Image Upload */}
          <div>
            <label className='text-sm font-medium block mb-2'>
              Reference Photo
            </label>
            {!imageUploaded ? (
              <Card className='border-2 border-dashed border-border hover:border-primary cursor-pointer transition-colors'>
                <CardContent className='p-6 flex flex-col items-center justify-center gap-2'>
                  <Upload className='h-8 w-8 text-muted-foreground' />
                  <p className='text-sm font-medium'>Upload Image</p>
                  <p className='text-xs text-muted-foreground'>
                    Tap to select or drag image here
                  </p>
                </CardContent>
              </Card>
            ) : (
              <Card>
                <CardContent className='p-4 flex items-center justify-between'>
                  <p className='text-sm'>reference-object.jpg</p>
                  <button
                    onClick={() => setImageUploaded(false)}
                    className='p-1 hover:bg-muted rounded transition-colors'
                  >
                    <X className='h-4 w-4' />
                  </button>
                </CardContent>
              </Card>
            )}
          </div>

          {/* Dimensions */}
          <div className='grid grid-cols-2 gap-3'>
            <div>
              <label className='text-sm font-medium block mb-2'>
                Length (cm)
              </label>
              <input
                type='number'
                value={length}
                onChange={(e) => setLength(e.target.value)}
                className='w-full px-3 py-2 border border-border rounded-lg font-mono focus:outline-none focus:ring-2 focus:ring-primary'
                placeholder='0'
              />
            </div>
            <div>
              <label className='text-sm font-medium block mb-2'>
                Width (cm)
              </label>
              <input
                type='number'
                value={width}
                onChange={(e) => setWidth(e.target.value)}
                className='w-full px-3 py-2 border border-border rounded-lg font-mono focus:outline-none focus:ring-2 focus:ring-primary'
                placeholder='0'
              />
            </div>
          </div>

          <p className='text-xs text-muted-foreground bg-muted/50 p-2 rounded'>
            Provide accurate measurements for reliable pig analysis
          </p>
        </div>

        <div className='flex gap-2 pt-2'>
          <Button
            variant='secondary'
            size='lg'
            className='flex-1'
            onClick={onBack}
          >
            Back
          </Button>
          <Button
            size='lg'
            className='flex-1'
            onClick={onConfirm}
            disabled={!imageUploaded || !length || !width}
          >
            Confirm
          </Button>
        </div>
      </div>
    </div>
  )
}
