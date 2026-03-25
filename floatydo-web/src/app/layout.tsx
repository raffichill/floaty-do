import type { Metadata } from "next";
import { TodoProvider } from "@/providers/todo-provider";
import "@/styles/globals.scss";

export const metadata: Metadata = {
  title: "FloatyDo — A tiny floating todo list for macOS",
  description:
    "A minimal, beautiful floating todo list that lives in the corner of your screen. Quick capture, keyboard-first, zero friction.",
  openGraph: {
    title: "FloatyDo",
    description: "A tiny floating todo list for macOS",
    url: "https://www.floatydo.com",
    siteName: "FloatyDo",
    type: "website",
  },
  twitter: {
    card: "summary_large_image",
    title: "FloatyDo",
    description: "A tiny floating todo list for macOS",
  },
};

export default function RootLayout({
  children,
}: {
  children: React.ReactNode;
}) {
  return (
    <html lang="en" data-theme="theme1">
      <body>
        <TodoProvider>{children}</TodoProvider>
      </body>
    </html>
  );
}
