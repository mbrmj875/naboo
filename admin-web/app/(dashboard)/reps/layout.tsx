import type { Metadata } from "next";
import "../../field/field.css";

export const metadata: Metadata = {
  title: "المندوبون | نابو",
};

export default function Layout({ children }: { children: React.ReactNode }) {
  return children;
}
