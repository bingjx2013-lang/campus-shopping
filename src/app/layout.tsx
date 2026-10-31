import type { Metadata } from "next";
import "./globals.css";

export const metadata: Metadata = {
  title: "明德校园购",
  description: "明德中英文学校校园购物平台",
};

export default function RootLayout({ children }: Readonly<{ children: React.ReactNode }>) {
  return (
    <html lang="zh-CN">
      <body>{children}</body>
    </html>
  );
}
