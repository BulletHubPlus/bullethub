import { describe, expect, it } from 'vitest'
import { formatCpf, isValidCpf } from '@/utils/cpf'

describe('cpf', () => {
  it('validates check digits like the backend', () => {
    expect(isValidCpf('529.982.247-25')).toBe(true)
    expect(isValidCpf('52998224724')).toBe(false)
    expect(isValidCpf('111.111.111-11')).toBe(false)
  })

  it('formats progressively', () => {
    expect(formatCpf('529982')).toBe('529.982')
    expect(formatCpf('52998224725')).toBe('529.982.247-25')
  })
})
