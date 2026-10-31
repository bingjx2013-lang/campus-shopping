import { NextResponse } from "next/server";

export function GET() {
  return NextResponse.json({
    status: "ok",
    service: "campus-shopping",
    mode: "scaffold",
    timestamp: new Date().toISOString(),
  }, {
    headers: { "Cache-Control": "no-store, max-age=0" },
  });
}
