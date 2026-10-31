import { NextRequest, NextResponse } from "next/server";
import type { ProductListResponse } from "@/features/products/types";

export function GET(request: NextRequest) {
  const pageRaw = Number(request.nextUrl.searchParams.get("page") ?? "1");
  const pageSizeRaw = Number(request.nextUrl.searchParams.get("pageSize") ?? "20");

  if (!Number.isInteger(pageRaw) || pageRaw < 1 ||
      !Number.isInteger(pageSizeRaw) || pageSizeRaw < 1 || pageSizeRaw > 50) {
    return NextResponse.json(
      {
        error: {
          code: "INVALID_PAGINATION",
          message: "page 必须大于 0，pageSize 必须在 1 到 50 之间。",
        },
      },
      { status: 400, headers: { "Cache-Control": "no-store" } },
    );
  }

  // Database access is intentionally not connected yet.
  // Returning an empty result avoids presenting fabricated products as real inventory.
  const response: ProductListResponse = {
    items: [],
    page: pageRaw,
    pageSize: pageSizeRaw,
    total: 0,
  };

  return NextResponse.json(response, {
    headers: { "Cache-Control": "no-store" },
  });
}
