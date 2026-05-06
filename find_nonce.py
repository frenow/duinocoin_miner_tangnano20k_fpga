#!/usr/bin/env python3
import hashlib

def test_nonce(message_hash_hex, expected_hash_hex, test_nonce):
    nonce_str = str(test_nonce).zfill(8)
    message = message_hash_hex + nonce_str
    sha1 = hashlib.sha1(message.encode('ascii')).hexdigest()
    return sha1 == expected_hash_hex

message_hash = "5c43753aa4f40183f9812da1493a05fc5f4af269"
expected_hash = "12bde5d2050550a177640293f5a5fb4e9e08db2a"
nonce_sent = 10680038

print(f"Procurando nonce correto para expected_hash: {expected_hash}")
print(f"Nonce enviado: {nonce_sent}")
print()

# Busca linear em volta do nonce enviado
found = False
for offset in range(-1000, 1001):
    test_n = nonce_sent + offset
    if test_n >= 0 and test_nonce(message_hash, expected_hash, test_n):
        print(f"FOUND: Nonce correto = {test_n}")
        print(f"Offset: {offset} (diferenca = {test_n - nonce_sent})")
        found = True
        break

if not found:
    print("Nonce nao encontrado entre os valores proximos")
    print("Testando se o nonce estava correto mas com padding diferente...")
    
    # Testa com padding 0-7
    for padding in range(1, 9):
        nonce_str = str(nonce_sent).zfill(padding)
        message = message_hash + nonce_str
        sha1 = hashlib.sha1(message.encode('ascii')).hexdigest()
        if sha1 == expected_hash:
            print(f"FOUND with padding {padding}: nonce_str = '{nonce_str}'")
            found = True
            break
    
    if not found:
        print("\nTentando busca exaustiva (0 a 1000000)...")
        for test_n in range(1000000, nonce_sent-100, -1):
            if test_nonce(message_hash, expected_hash, test_n):
                print(f"FOUND: {test_n}")
                break
