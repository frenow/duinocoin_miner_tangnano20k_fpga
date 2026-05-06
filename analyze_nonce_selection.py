#!/usr/bin/env python3
"""
Se nonce_0 = 440171, quais são os valores de nonce_1 a nonce_6?
"""

nonce_0 = 440171

print("="*80)
print("VALORES DOS 7 NONCES SE nonce_0 = 440171")
print("="*80)
print()

for i in range(7):
    nonce = nonce_0 + i
    nonce_hex = f"0x{nonce:08x}"
    print(f"nonce_{i} = {nonce:10d} = {nonce_hex}")

print()
print("="*80)
print("VERIFICANDO QUAL NONCE TEM BYTE MSB = 0x04")
print("="*80)
print()

target_msb = 0x04

for i in range(7):
    nonce = nonce_0 + i
    msb = (nonce >> 24) & 0xFF
    if msb == target_msb:
        print(f"ENCONTRADO: nonce_{i} = {nonce} = 0x{nonce:08x}")
        print(f"  Byte MSB = 0x{msb:02x}")
        print(f"  Isto corresponde ao nonce 67549035 enviado!")
        break
else:
    print(f"Nenhum dos nonce_0 a nonce_6 tem byte MSB = 0x{target_msb:02x}")
    
print()
print("Teste reverso: se o nonce enviado é 67549035 = 0x0406b76b,")
print("qual deveria ser o nonce_0?")
print()

sent_nonce = 67549035
# Reverter o padrão
for offset in range(7):
    nonce_0_candidate = sent_nonce - offset
    print(f"Se nonce_{offset} = {sent_nonce}, então nonce_0 = {nonce_0_candidate}")
