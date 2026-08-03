import { Button } from '@/components/ui/button'
import { ChevronLeft, AlertCircle } from 'lucide-react'

interface HeightModeAlignmentProps {
  onConfirm: () => void
  onBack: () => void
}

export function HeightModeAlignment({
  onConfirm,
  onBack,
}: HeightModeAlignmentProps) {
  return (
    <div className='fixed inset-0 bg-black flex flex-col'>
      {/* Header */}
      <div className='bg-black/70 p-3 flex items-center gap-2'>
        <button
          onClick={onBack}
          className='p-1.5 hover:bg-white/10 rounded-lg transition-colors text-white'
        >
          <ChevronLeft className='h-5 w-5' />
        </button>
        <h2 className='text-lg font-semibold flex-1 text-white'>Align Camera</h2>
      </div>

      {/* Camera Preview */}
      <div className='flex-1 bg-black flex items-center justify-center relative'>
        {/* Silhouette overlay */}
        <div className='absolute inset-0 flex items-center justify-center pointer-events-none'>
          <svg
            className='w-24 h-32 text-white/30'
            viewBox='0 0 100 120'
            fill='none'
            stroke='currentColor'
            strokeWidth='2'
          >
            {/* Simple pig silhouette */}
            <circle cx='50' cy='40' r='20' />
            <rect x='35' y='60' width='30' height='40' rx='4' />
            <circle cx='25' cy='75' r='6' />
            <circle cx='75' cy='75' r='6' />
            <circle cx='25' cy='95' r='6' />
            <circle cx='75' cy='95' r='6' />
          </svg>
        </div>

        {/* Alignment guides */}
        <div className='absolute inset-0 flex items-center justify-center pointer-events-none'>
          <div className='absolute top-1/4 left-0 right-0 h-px bg-white/20'></div>
          <div className='absolute bottom-1/4 left-0 right-0 h-px bg-white/20'></div>
        </div>
      </div>

      {/* Guidance */}
      <div className='bg-black/80 p-4 space-y-3 border-t border-white/10'>
        <div className='flex gap-2 text-yellow-400 text-sm'>
          <AlertCircle className='h-4 w-4 flex-shrink-0 mt-0.5' />
          <p>Position pig to match the silhouette guide</p>
        </div>
        <div className='flex gap-2'>
          <Button
            variant='secondary'
            size='lg'
            className='flex-1'
            onClick={onBack}
          >
            Adjust Height
          </Button>
          <Button
            size='lg'
            className='flex-1'
            onClick={onConfirm}
          >
            Capture
          </Button>
        </div>
      </div>
    </div>
  )
}
