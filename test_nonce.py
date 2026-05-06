#!/usr/bin/env python3
"""
Script para testar qual nonce produz o hash esperado
"""
import hashlib
import sys

def test_nonce(message_hash_hex, expected_hash_hex, test_nonce):
    """
    Testa um nonce específico
    """
    # Converte o nonce para string ASCII (8 dígitos com padding)
    nonce_str = str(test_nonce).zfill(8)
    
    # Constrói a mensagem: message_hash (40 bytes ASCII) + nonce_str (8 bytes ASCII)
    message = message_hash_hex + nonce_str
    
    # Calcula SHA-1
    sha1 = hashlib.sha1(message.encode('ascii')).hexdigest()
    
    # Verifica se bate com expected_hash
    matches = (sha1 == expected_hash_hex)
    
    return {
        'nonce': test_nonce,
        'nonce_str': nonce_str,
        'message': message,
        'computed_hash': sha1,
        'expected_hash': expected_hash_hex,
        'matches': matches
    }

# Dados do primeiro erro (nonce 10680038, 8 dígitos)
message_hash = "5c43753aa4f40183f9812da1493a05fc5f4af269"
expected_hash = "12bde5d2050550a177640293f5a5fb4e9e08db2a"
nonce_sent = 10680038

print("=" * 80)
print(f"TESTE: nonce enviado = {nonce_sent}")
print("=" * 80)

# Testa o nonce enviado
result = test_nonce(message_hash, expected_hash, nonce_sent)
print(f"\nNonce enviado: {result['nonce_str']}")
print(f"Mensagem: {result['message']}")
print(f"Hash calculado: {result['computed_hash']}")
print(f"Hash esperado:  {result['expected_hash']}")
print(f"Resultado: {'CORRETO' if result['matches'] else 'INCORRETO'}")

# Se não bateu, procura pelo nonce correto
if not result['matches']:
    print("\n" + "=" * 80)
    print("Procurando nonce correto...")
    print("=" * 80)
    
    # Testa nonces próximos
    for offset in range(-10, 11):
        test_n = nonce_sent + offset
        if test_n >= 0:
            result = test_nonce(message_hash, expected_hash, test_n)
            if result['matches']:
                print(f"\n✓ ENCONTRADO nonce correto: {result['nonce']}")
                print(f"Nonce enviado:  {nonce_sent}")
                print(f"Nonce correto:  {result['nonce']}")
                print(f"Diferença: {result['nonce'] - nonce_sent}")
                break
    else:
        print("\n✗ Nonce correto não encontrado nos próximos 10 valores...")
        print("\nTentando busca mais ampla (0 a 100000000)...")
        
        # Busca binária (mais eficiente)
        for test_n in range(0, nonce_sent + 100, 7):  # Testando nonces multiplos de 7 (hepta-core)
            result = test_nonce(message_hash, expected_hash, test_n)
            if result['matches']:
                print(f"\n✓ ENCONTRADO nonce correto: {result['nonce']}")
                print(f"Nonce enviado:  {nonce_sent}")
                print(f"Nonce correto:  {result['nonce']}")
                print(f"Diferença: {result['nonce'] - nonce_sent}")
                break
