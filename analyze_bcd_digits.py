#!/usr/bin/env python3
"""
Analisa os dígitos BCD de ambos os nonces para procurar padrão
"""

def get_bcd_digits(nonce):
    """Retorna os 9 dígitos BCD (com zeros à esquerda)"""
    nonce_str = str(nonce).zfill(9)
    return [int(d) for d in nonce_str]

nonce_correct = 440171
nonce_sent = 67549035

print("="*80)
print("ANÁLISE BCD DOS DOIS NONCES")
print("="*80)
print()

digits_correct = get_bcd_digits(nonce_correct)
digits_sent = get_bcd_digits(nonce_sent)

print(f"Nonce correto: {nonce_correct}")
print(f"Dígitos (9 posições):  {' '.join(str(d) for d in digits_correct)}")
print(f"Posição:               0 1 2 3 4 5 6 7 8")
print()

print(f"Nonce enviado: {nonce_sent}")
print(f"Dígitos (9 posições):  {' '.join(str(d) for d in digits_sent)}")
print(f"Posição:               0 1 2 3 4 5 6 7 8")
print()

print("Comparacao:")
for i in range(9):
    match = "OK" if digits_correct[i] == digits_sent[i] else "DIFF"
    print(f"  Posicao {i}: {digits_correct[i]} vs {digits_sent[i]} {match}")

print()
print("="*80)
print("ANÁLISE: Qual é a origem do 0x04?")
print("="*80)
print()

# O byte 0x04 em ASCII é EOT (End Of Transmission)
# Em decimal é 4
# Em hex é 0x04

print("0x04 em decimal = 4")
print()
print("Procurando 4 nos dígitos de 440171:")
for i, d in enumerate(digits_correct):
    if d == 4:
        print(f"  Encontrado na posição {i}: digit {i} = 4")

print()
print("Isto pode significar que o digit_4 (que vale 4) está sendo")
print("interpretado como parte do nonce inteiro!")
