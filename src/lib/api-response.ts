import { NextResponse } from "next/server";

export interface ApiErrorBody {
  error: {
    code: string;
    message: string;
    requestId: string;
  };
}

export function apiError(
  status: number,
  code: string,
  message: string,
  requestId: string,
) {
  const body: ApiErrorBody = {
    error: { code, message, requestId },
  };

  return NextResponse.json(body, {
    status,
    headers: { "Cache-Control": "no-store" },
  });
}
