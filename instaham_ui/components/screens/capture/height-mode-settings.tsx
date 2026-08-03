import { useState } from 'react'
import { Button } from '@/components/ui/button'
import { Card, CardHeader, CardTitle, CardContent } from '@/components/ui/card'
import { ChevronLeft } from 'lucide-react'

interface HeightModeSettingsProps {
  value: number
  onChange: (value: number) => void
  onNext: () => void
  onBack: () => void
}

export function HeightModeSettings({
  value,
  onChange,
  onNext,
  onBack,
}: HeightModeSettingsProps) {
  const [inputValue, setInputValue] = useState(value.toString())

  const handleConfirm = () => {
    onChange(parseFloat(inputValue) || 0)
    onNext()
  }

  return (
    <div className='fixed inset-0 bg-black/50 flex items-end z-50'>
      <div className='w-full bg-background rounded-t-2xl p-4 space-y-4 animate-in slide-in-from-bottom'>
        <div className='flex items-center gap-2 mb-2'>
          <button
            onClick={onBack}
            className='p-1.5 hover:bg-muted rounded-lg transition-colors'
          >
            <ChevronLeft className='h-5 w-5' />
          </button>
          <h2 className='text-lg font-semibold flex-1'>Camera Height</h2>
        </div>

        <Card className='bg-muted/50'>
          <CardContent className='p-4 space-y-4'>
            <div>
              <label className='text-sm font-medium block mb-2'>
                Height (cm)
              </label>
              <input
                type='number'
                value={inputValue}
                onChange={(e) => setInputValue(e.target.value)}
                className='w-full px-3 py-2 border border-border rounded-lg font-mono text-lg focus:outline-none focus:ring-2 focus:ring-primary'
                placeholder='0'
              />
            </div>
            <p className='text-xs text-muted-foreground'>
              Position camera at this height above the pig for accurate measurement
            </p>
          </CardContent>
        </Card>

        <div className='flex gap-2'>
          <Button
            variant='secondary'
            size='lg'
            className='flex-1'
            onClick={onBack}
          >
            Cancel
          </Button>
          <Button
            size='lg'
            className='flex-1'
            onClick={handleConfirm}
          >
            Continue
          </Button>
        </div>
      </div>
    </div>
  )
}
