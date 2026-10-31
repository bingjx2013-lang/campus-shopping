export interface JournalLine {
  accountCode: string;
  debitCents: number;
  creditCents: number;
}
export interface JournalDraft {
  currency: "CNY";
  lines: JournalLine[];
}

export function validateJournal(
  draft: JournalDraft,
): { ok: true; totalCents: number } | { ok: false; reason: string } {
  if (draft.currency !== "CNY") return { ok: false, reason: "账务币种必须为 CNY" };
  if (!Array.isArray(draft.lines) || draft.lines.length < 2) {
    return { ok: false, reason: "至少需要两条分录" };
  }
  let debit = 0;
  let credit = 0;
  for (const line of draft.lines) {
    if (typeof line.accountCode !== "string" || !line.accountCode.trim()) {
      return { ok: false, reason: "科目编码不能为空" };
    }
    if (!Number.isSafeInteger(line.debitCents) || !Number.isSafeInteger(line.creditCents)
      || line.debitCents < 0 || line.creditCents < 0
      || (line.debitCents === 0 && line.creditCents === 0)
      || (line.debitCents > 0 && line.creditCents > 0)) {
      return { ok: false, reason: "每条分录必须且只能填写借方或贷方正整数分" };
    }
    debit += line.debitCents;
    credit += line.creditCents;
  }
  if (!Number.isSafeInteger(debit) || !Number.isSafeInteger(credit) || debit !== credit || debit <= 0) {
    return { ok: false, reason: "借贷金额必须相等、为正数且不能超出安全整数范围" };
  }
  return { ok: true, totalCents: debit };
}

export function correctionMode(): "reversal" {
  return "reversal";
}
