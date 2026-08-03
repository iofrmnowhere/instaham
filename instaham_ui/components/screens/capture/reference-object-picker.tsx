import { Button } from '@/components/ui/button'
import { Card, CardContent } from '@/components/ui/card'
import { ChevronLeft, Plus } from 'lucide-react'

interface ReferenceObjectPickerProps {
  onSelect: (type: 'meter' | 'porac' | 'custom') => void
  onBack: () => void
}

const presets = [
  {
    id: 'meter',
    name: '1-Meter Stick',
    description: 'Standard measurement reference',
  },
  {
    id: 'porac',
    name: 'Porac Stick',
    description: 'Field standard reference',
  },
]

export function ReferenceObjectPicker({
  onSelect,
  onBack,
}: ReferenceObjectPickerProps) {
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
          <h2 className='text-lg font-semibold flex-1'>Reference Object</h2>
        </div>

        <div className='space-y-2'>
          {presets.map((preset) => (
            <button
              key={preset.id}
              onClick={() => onSelect(preset.id as 'meter' | 'porac')}
              className='w-full'
            >
              <Card className='hover:shadow-md transition-shadow cursor-pointer'>
                <CardContent className='p-4'>
                  <p className='font-semibold text-sm'>{preset.name}</p>
                  <p className='text-xs text-muted-foreground mt-1'>
                    {preset.description}
                  </p>
                </CardContent>
              </Card>
            </button>
          ))}

          <button
            onClick={() => onSelect('custom')}
            className='w-full'
          >
            <Card className='hover:shadow-md transition-shadow cursor-pointer border-2 border-dashed border-primary'>
              <CardContent className='p-4 flex items-center gap-3'>
                <div className='flex-shrink-0 w-10 h-10 rounded-lg bg-primary/10 flex items-center justify-center'>
                  <Plus className='h-5 w-5 text-primary' />
                </div>
                <div className='text-left'>
                  <p className='font-semibold text-sm'>Add Custom</p>
                  <p className='text-xs text-muted-foreground'>
                    Upload your own reference
                  </p>
                </div>
              </CardContent>
            </Card>
          </button>
        </div>

        <Button
          variant='secondary'
          size='lg'
          className='w-full'
          onClick={onBack}
        >
          Cancel
        </Button>
      </div>
    </div>
  )
}
