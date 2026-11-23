import { Component, type ReactNode } from "react";

/** If anything below throws while rendering, show what happened and a way out
 *  instead of a blank window. (React only offers this as a class component.)
 *  React itself logs the error to the console. */
export class ErrorBoundary extends Component<{ children: ReactNode }, { error: Error | null }> {
  state = { error: null as Error | null };

  static getDerivedStateFromError(error: Error) {
    return { error };
  }

  render() {
    if (!this.state.error) return this.props.children;
    return (
      <div className="crash" role="alert">
        <strong>Something went wrong</strong>
        <span>Your tasks are safe: they're files in your vault. Reloading usually fixes this.</span>
        <pre>{this.state.error.message}</pre>
        <button type="button" className="btn-primary" onClick={() => location.reload()}>
          Reload
        </button>
      </div>
    );
  }
}
