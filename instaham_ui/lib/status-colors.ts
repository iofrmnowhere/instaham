/**
 * Status color mapping for INSTAHAM
 * Provides consistent color coding across all screens
 */

export type StatusType = "success" | "uncertain" | "blocked" | "loading"

export interface StatusColors {
  bg: string
  text: string
  border: string
  badge: "success" | "uncertain" | "blocked"
}

export const statusColorMap: Record<StatusType, StatusColors> = {
  success: {
    bg: "bg-green-50",
    text: "text-green-900",
    border: "border-green-300",
    badge: "success",
  },
  uncertain: {
    bg: "bg-amber-50",
    text: "text-amber-900",
    border: "border-amber-300",
    badge: "uncertain",
  },
  blocked: {
    bg: "bg-orange-50",
    text: "text-orange-900",
    border: "border-orange-300",
    badge: "blocked",
  },
  loading: {
    bg: "bg-blue-50",
    text: "text-blue-900",
    border: "border-blue-300",
    badge: "success",
  },
}

export const getStatusColor = (status: StatusType): StatusColors => {
  return statusColorMap[status]
}

export const statusLabels: Record<StatusType, string> = {
  success: "Confirmed",
  uncertain: "Uncertain",
  blocked: "Blocked",
  loading: "Analyzing",
}

export const getStatusLabel = (status: StatusType): string => {
  return statusLabels[status]
}
