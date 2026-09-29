/** Client-side CPF helpers. The backend re-validates; this is only UX. */

export function onlyDigits(value: string): string {
  return value.replace(/\D/g, '')
}

export function formatCpf(value: string): string {
  const d = onlyDigits(value).slice(0, 11)
  return d
    .replace(/^(\d{3})(\d)/, '$1.$2')
    .replace(/^(\d{3})\.(\d{3})(\d)/, '$1.$2.$3')
    .replace(/\.(\d{3})(\d)/, '.$1-$2')
}

function checkDigit(nums: number[]): number {
  const weight = nums.length + 1
  const sum = nums.reduce((acc, n, i) => acc + n * (weight - i), 0)
  const d = (sum * 10) % 11
  return d === 10 ? 0 : d
}

export function isValidCpf(value: string): boolean {
  const d = onlyDigits(value)
  if (d.length !== 11 || /^(\d)\1{10}$/.test(d)) return false
  const nums = d.split('').map(Number)
  return checkDigit(nums.slice(0, 9)) === nums[9] && checkDigit(nums.slice(0, 10)) === nums[10]
}
