import { Component, type ErrorInfo, type ReactNode } from 'react'
import { ErrorState } from '../components/ui'

/** Last-resort render-error boundary. Shows a generic message; details go to the console only (no stack traces in the UI). */
export class ErrorBoundary extends Component<{ children: ReactNode }, { failed: boolean }> {
  state = { failed: false }
  static getDerivedStateFromError() { return { failed: true } }
  componentDidCatch(error: Error, info: ErrorInfo) { console.error('UI error', error, info.componentStack) }
  render() {
    if (!this.state.failed) return this.props.children
    return <div className="p-8"><ErrorState title="This page hit an unexpected error" message="Please reload. If it keeps happening, contact the administrator." onRetry={() => this.setState({ failed: false })} /></div>
  }
}
