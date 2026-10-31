export interface JournalLine {
  accountCode: string;
  debitCents: number;
  creditCents: number;
}

export interface JournalDraft {
  currency: "CNY";
  lines: JournalLine[];
}

export function validateJournal(draft: JournalDraft): { ok: true; totalCents: number } | { ok: false; reason: string } {
  if (draft.lines.length < 2) return { ok: false, reason: "至少需要两条分录" };
  let debit = 0;
  let credit = 0;
  for (const line of draft.lines) {
    if (!line.accountCode.trim()) return { ok: false, reason: "科目编码不能为空" };
    if (!Number.isSafeInteger(line.debitCents) || !Number.isSafeInteger(line.creditCents)
      || line.debitCents < 0 || line.creditCents < 0
      || (line.debitCents === 0 && line.creditCents === 0)
      || (line.debitCents > 0 && line.creditCents > 0)) {
      return { ok: false, reason: "每条分录必须且只能填写借方或贷方正整数分" };
    }
    debit += line.debitCents;
    credit += line.creditCents;
  }
  if (!Number.isSafeInteger(debit) || !Number.isSafeInteger(credit) || debit !== credit) {
    return { ok: false, reason: "借贷金额必须相等且不能超出安全整数范围" };
  }
  return { ok: true, totalCents: debit };
}

/** Posted journal rows are never edited; corrections are represented as reversal entries. */
export function correctionMode(): "reversal" {
  return "reversal";
}
