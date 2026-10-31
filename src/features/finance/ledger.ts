export interface JournalLine { accountId: string; debitMinor: number; creditMinor: number }
export interface JournalEntry { currency: "CNY" | "USD"; lines: readonly JournalLine[] }

/** Validates a proposed entry before persistence; posted entries must be immutable. */
export function validateJournalEntry(entry: JournalEntry): string[] {
  const errors: string[] = [];
  if (entry.lines.length < 2) errors.push("JOURNAL_REQUIRES_TWO_LINES");
  let debit = 0;
  let credit = 0;
  for (const line of entry.lines) {
    if (!line.accountId.trim()) errors.push("ACCOUNT_REQUIRED");
    if (!Number.isSafeInteger(line.debitMinor) || line.debitMinor < 0 ||
        !Number.isSafeInteger(line.creditMinor) || line.creditMinor < 0) {
      errors.push("INVALID_LEDGER_AMOUNT"); continue;
    }
    if (line.debitMinor > 0 && line.creditMinor > 0) errors.push("LINE_CANNOT_DEBIT_AND_CREDIT");
    debit += line.debitMinor;
    credit += line.creditMinor;
  }
  if (!Number.isSafeInteger(debit) || !Number.isSafeInteger(credit)) errors.push("LEDGER_OVERFLOW");
  else if (debit !== credit || debit <= 0) errors.push("JOURNAL_NOT_BALANCED");
  return [...new Set(errors)];
}
