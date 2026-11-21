"use client";

import { Component, type ReactNode } from "react";

type Props = { children: ReactNode; fallback?: ReactNode };
type State = { error: Error | null };

export class FieldErrorBoundary extends Component<Props, State> {
  state: State = { error: null };

  static getDerivedStateFromError(error: Error): State {
    return { error };
  }

  render() {
    if (this.state.error) {
      return (
        this.props.fallback ?? (
          <div className="field-alert err" style={{ margin: 16 }}>
            حدث خطأ في العرض. أعد تحميل الصفحة.
          </div>
        )
      );
    }
    return this.props.children;
  }
}
