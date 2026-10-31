export type ProductStatus = "draft" | "published" | "archived";

export interface ProductSummary {
  id: string;
  storeId: string;
  title: string;
  description: string | null;
  coverImageUrl: string | null;
  minPriceMinor: number;
  currency: "USD" | "CNY";
  status: ProductStatus;
}

export interface ProductListResponse {
  items: ProductSummary[];
  page: number;
  pageSize: number;
  total: number;
}
