// Decimal digits of any script read as the ASCII digits they stand for ("४५" is 45, "５０" is 50),
// so a guard that reads figures cannot be passed by writing them in another script. Unicode puts
// each script's digits in runs of ten from zero, so a digit's value is its place in its run.
const decimalDigit = /\p{Nd}/u;

export function asciiDigits(text: string): string {
  return text.replace(/\p{Nd}/gu, (digit) => {
    let code = digit.codePointAt(0)!;
    if (code < 0x80) return digit;
    let place = 0;
    while (decimalDigit.test(String.fromCodePoint(code - 1))) {
      code -= 1;
      place += 1;
    }
    return String(place % 10);
  });
}
