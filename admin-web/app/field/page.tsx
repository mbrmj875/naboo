import { FieldErrorBoundary } from "@/components/field/field-error-boundary";
import { VisitForm } from "@/components/field/visit-form";

export default function Page() {
  return (
    <FieldErrorBoundary>
      <VisitForm stayAfterSave title="محل جديد" />
    </FieldErrorBoundary>
  );
}
