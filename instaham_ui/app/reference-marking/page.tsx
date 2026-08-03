'use client'

import { useState } from 'react'
import { ScreenContainer } from '@/components/layouts/screen-container'
import { Button } from '@/components/ui/button'
import { Card, CardContent } from '@/components/ui/card'
import { ChevronLeft, Copy } from 'lucide-react'
import Link from 'next/link'

interface DraggablePin {
  id: string
  x: number
  y: number
}

export default function ReferenceMarkingPage() {
  const [pins, setPins] = useState<DraggablePin[]>([])
  const [scale, setScale] = useState<number | null>(null)
  const [draggingPin, setDraggingPin] = useState<string | null>(null)

  const handleCanvasClick = (e: React.MouseEvent<HTMLDivElement>) => {
    if (draggingPin) return

    const rect = e.currentTarget.getBoundingClientRect()
    const x = e.clientX - rect.left
    const y = e.clientY - rect.top

    const newPin: DraggablePin = {
      id: `pin-${Date.now()}`,
      x,
      y,
    }
    setPins([...pins, newPin])
  }

  const handlePinMouseDown = (e: React.MouseEvent, pinId: string) => {
    e.preventDefault()
    setDraggingPin(pinId)
  }

  const handleMouseMove = (e: React.MouseEvent<HTMLDivElement>) => {
    if (!draggingPin) return

    const rect = e.currentTarget.getBoundingClientRect()
    const x = e.clientX - rect.left
    const y = e.clientY - rect.top

    setPins(
      pins.map((pin) =>
        pin.id === draggingPin ? { ...pin, x, y } : pin
      )
    )
  }

  const handleMouseUp = () => {
    setDraggingPin(null)
  }

  const handleRemovePin = (pinId: string) => {
    setPins(pins.filter((pin) => pin.id !== pinId))
  }

  const calculateScale = () => {
    if (pins.length < 2) return
    const p1 = pins[0]
    const p2 = pins[1]
    const distance = Math.sqrt(Math.pow(p2.x - p1.x, 2) + Math.pow(p2.y - p1.y, 2))
    setScale(distance)
  }

  return (
    <ScreenContainer showNav={false}>
      {/* Header */}
      <div className='border-b border-border p-4'>
        <div className='flex items-center gap-2'>
          <Link href='/measurements'>
            <button className='p-1.5 hover:bg-muted rounded-lg transition-colors'>
              <ChevronLeft className='h-5 w-5' />
            </button>
          </Link>
          <h1 className='text-xl font-bold flex-1'>Mark Reference Endpoints</h1>
        </div>
      </div>

      <div className='mobile-viewport flex flex-col flex-1 pb-20'>
        {/* Canvas Area */}
        <div
          className='flex-1 bg-gray-100 border border-border relative cursor-crosshair'
          onClick={handleCanvasClick}
          onMouseMove={handleMouseMove}
          onMouseUp={handleMouseUp}
          onMouseLeave={handleMouseUp}
        >
          {/* Photo placeholder */}
          <div className='absolute inset-0 flex items-center justify-center bg-gray-200/50'>
            <p className='text-gray-500 text-sm'>Reference Photo</p>
          </div>

          {/* Pins */}
          {pins.map((pin, index) => (
            <div key={pin.id} className='absolute group'>
              <button
                className='w-8 h-8 rounded-full bg-primary border-2 border-white shadow-lg flex items-center justify-center text-white text-xs font-bold cursor-grab active:cursor-grabbing'
                style={{
                  left: `${pin.x - 16}px`,
                  top: `${pin.y - 16}px`,
                }}
                onMouseDown={(e) => handlePinMouseDown(e, pin.id)}
                title={`Point ${index + 1}`}
              >
                {index + 1}
              </button>
              <button
                onClick={() => handleRemovePin(pin.id)}
                className='absolute -top-2 -right-2 bg-destructive text-white rounded-full p-1 opacity-0 group-hover:opacity-100 transition-opacity'
              >
                ×
              </button>
            </div>
          ))}

          {/* Connection line between pins */}
          {pins.length >= 2 && (
            <svg className='absolute inset-0 w-full h-full pointer-events-none'>
              <line
                x1={pins[0].x}
                y1={pins[0].y}
                x2={pins[1].x}
                y2={pins[1].y}
                stroke='#3D5C1C'
                strokeWidth='2'
                strokeDasharray='4'
              />
            </svg>
          )}
        </div>

        {/* Readout and Controls */}
        <div className='border-t border-border p-4 space-y-3'>
          {pins.length >= 2 && (
            <Card>
              <CardContent className='p-3'>
                <p className='text-xs text-muted-foreground mb-2'>Scale Ratio</p>
                <p className='font-mono font-bold text-lg'>
                  {pins.length >= 2 && (
                    <>
                      {Math.round(
                        Math.sqrt(
                          Math.pow(pins[1].x - pins[0].x, 2) +
                          Math.pow(pins[1].y - pins[0].y, 2)
                        )
                      )}
                      px → 1.00cm
                    </>
                  )}
                </p>
              </CardContent>
            </Card>
          )}

          <div className='flex gap-2'>
            <Button
              variant='secondary'
              size='lg'
              className='flex-1'
              onClick={() => setPins([])}
            >
              Reset
            </Button>
            <Button
              size='lg'
              className='flex-1'
              disabled={pins.length < 2}
              onClick={calculateScale}
            >
              Confirm
            </Button>
          </div>

          {pins.length === 0 && (
            <p className='text-xs text-muted-foreground text-center'>
              Click to add 2 points on the reference object endpoints
            </p>
          )}
          {pins.length === 1 && (
            <p className='text-xs text-muted-foreground text-center'>
              Click to add the second point
            </p>
          )}
        </div>
      </div>
    </ScreenContainer>
  )
}
