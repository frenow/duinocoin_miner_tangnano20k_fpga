#!/usr/bin/env python3
"""
Testa a lógica BCD para determinar se o digit_count está correto.
"""

def get_digit_count(nonce):
    """Simula a lógica do BCD para contar dígitos"""
    if nonce == 0:
        return 1
    
    digit_count = 0
    temp = nonce
    while temp > 0:
        digit_count += 1
        temp //= 10
    
    return digit_count

# Testa alguns nonces
test_nonces = [67549035, 440171, 13447511, 30452628, 11083765]

print("="*80)
print("ANÁLISE DO DIGIT_COUNT PARA NONCES COM ERRO")
print("="*80)
print()

for nonce in test_nonces:
    digit_count = get_digit_count(nonce)
    nonce_str = str(nonce)
    
    print(f"Nonce: {nonce}")
    print(f"  Digit count (esperado): {len(nonce_str)}")
    print(f"  Digit count (calculado): {digit_count}")
    print(f"  Match: {'OK' if digit_count == len(nonce_str) else 'ERRO'}")
    print()

# Análise específica do padrão
print("="*80)
print("ANÁLISE DO PADRÃO OBSERVADO")
print("="*80)
print()

# Nonce 67549035 deveria ter 8 dígitos
# Mas o firmware encontrou 440171 (6 dígitos) como correto
sent_nonce = 67549035
correct_nonce = 440171

print(f"Nonce enviado: {sent_nonce} ({len(str(sent_nonce))} dígitos)")
print(f"Nonce correto encontrado: {correct_nonce} ({len(str(correct_nonce))} dígitos)")
print()
print("HIPÓTESE: O firmware CALCULOU corretamente 440171 (6 dígitos),")
print("          mas ao TRANSMITIR, enviou 67549035 (8 dígitos)")
print()
print("ISTO SUGERE QUE:")
print("  1. O nonce_0 começou como 440171")
print("  2. Após encontrar a solução, houve um 'overflow' ou 'corruption' de memória")
print("  3. O valor foi sobrescrito antes da transmissão")
print()

# Análise em hexadecimal
print("Análise hexadecimal:")
print(f"  67549035 = 0x{67549035:08x}")
print(f"  440171   = 0x{440171:08x}")
print()
print("Observação: Os bits [23:0] são IDÊNTICOS (0x06b76b)")
print("            Apenas o byte MSB diferencia (0x04 vs 0x00)")
print()
print("ISTO SUGERE QUE O NONCE CORRETO (440171) está sendo MASCARADO")
print("e um valor espúrio (0x04) está sendo COLOCADO no byte MSB!")
