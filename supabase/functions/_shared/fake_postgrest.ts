// A stand-in for the part of PostgREST that the paging code uses, for tests: filters, keyset
// comparison, order, limit, and the server's cap on rows per response (`max_rows`). `onRequest`
// runs before each request is answered, so a test can insert or delete rows between pages.
export type Row = Record<string, unknown>;
export type Answer = Readonly<{ data: Row[] | null; error: unknown }>;

export class FakeQuery implements PromiseLike<Answer> {
  private filters: Array<(row: Row) => boolean> = [];
  private orderBy: string[] = [];
  private cap = Number.POSITIVE_INFINITY;

  constructor(
    private readonly rows: () => Row[],
    private readonly maxRows: number,
    private readonly onRequest: () => void,
    private readonly fail = false,
  ) {}

  eq(column: string, value: unknown) {
    this.filters.push((row) => row[column] === value);
    return this;
  }
  neq(column: string, value: unknown) {
    this.filters.push((row) => row[column] !== value);
    return this;
  }
  not(column: string, operator: string, value: unknown) {
    if (operator !== "is") throw new Error("fake supports not(..., 'is', ...) only");
    this.filters.push((row) => (row[column] ?? null) !== value);
    return this;
  }
  gt(column: string, value: string) {
    this.filters.push((row) => String(row[column]) > value);
    return this;
  }
  order(column: string, _options?: { ascending: boolean }) {
    this.orderBy.push(column);
    return this;
  }
  limit(count: number) {
    this.cap = count;
    return this;
  }

  then<R1 = Answer, R2 = never>(
    onfulfilled?: ((value: Answer) => R1 | PromiseLike<R1>) | null,
    onrejected?: ((reason: unknown) => R2 | PromiseLike<R2>) | null,
  ): PromiseLike<R1 | R2> {
    this.onRequest();
    let answer: Answer;
    if (this.fail) {
      answer = { data: null, error: { message: "detail" } };
    } else {
      const matching = this.rows().filter((row) => this.filters.every((keep) => keep(row)));
      for (const column of [...this.orderBy].reverse()) {
        matching.sort((a, b) => {
          const [left, right] = [String(a[column]), String(b[column])];
          return left < right ? -1 : left > right ? 1 : 0;
        });
      }
      answer = {
        data: matching.slice(0, Math.min(this.cap, this.maxRows)).map((row) => ({ ...row })),
        error: null,
      };
    }
    return Promise.resolve(answer).then(onfulfilled, onrejected);
  }
}
