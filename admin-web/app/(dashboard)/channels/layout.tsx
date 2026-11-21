import type { Metadata } from "next";

export const metadata: Metadata = {
  title: "القنوات — NABOO",
};

export default function ChannelsLayout({
  children,
}: Readonly<{ children: React.ReactNode }>) {
  return children;
}
