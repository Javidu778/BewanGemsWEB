import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "Bewan Gems",
  description: "Luxury natural gemstones — Ceylon sapphires and rare stones for discerning collectors.",
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en">
      <body>{children}</body>
    </html>
  );
}