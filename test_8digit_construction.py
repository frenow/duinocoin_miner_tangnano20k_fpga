#!/usr/bin/env python3
"""
Script para testar se o nonce_ascii está sendo construído corretamente para 8 dígitos.
Verifica se o problema está no nonce_ascii_len ou na construção da mensagem SHA-1.
"""
import hashlib

def test_message_for_8digit_nonce():
    """
    Testa como o firmware constrói a mensagem SHA-1 para nonces de 8 dígitos.
    """
    # Exemplo do erro: nonce 67549035 (8 dígitos)
    message_hash = "e2ca31cabaedda10f92d03ba2a93f6f4350d696d"
    expected_hash = "739b635dab680780c5f5d1010db1f95807567f1d"
    nonce_sent = 67549035
    
    print("="*80)
    print("TESTANDO CONSTRUÇÃO DE MENSAGEM PARA 8 DÍGITOS")
    print("="*80)
    print(f"Nonce enviado: {nonce_sent} (8 dígitos)")
    print(f"Message hash: {message_hash}")
    print(f"Expected hash: {expected_hash}")
    print()
    
    # Teste 1: Nonce_ascii padrão (8 dígitos ASCII)
    print("TESTE 1: nonce_ascii_len = 8 (construção correta com 8'd0)")
    nonce_str = str(nonce_sent).zfill(8)
    message = message_hash + nonce_str
    sha1 = hashlib.sha1(message.encode('ascii')).hexdigest()
    print(f"  Nonce string: '{nonce_str}' (len={len(nonce_str)})")
    print(f"  Message: {message}")
    print(f"  SHA-1: {sha1}")
    print(f"  Match: {sha1 == expected_hash}")
    print()
    
    # Teste 2: Nonce_ascii com padding incorreto
    print("TESTE 2: nonce_ascii_len = 7 (nonce com apenas 7 dígitos, faltando 1)")
    nonce_str_7 = str(nonce_sent)[:7]  # Apenas os primeiros 7 dígitos
    message_7 = message_hash + nonce_str_7
    sha1_7 = hashlib.sha1(message_7.encode('ascii')).hexdigest()
    print(f"  Nonce string: '{nonce_str_7}' (len={len(nonce_str_7)})")
    print(f"  Message: {message_7}")
    print(f"  SHA-1: {sha1_7}")
    print(f"  Match: {sha1_7 == expected_hash}")
    print()
    
    # Teste 3: Nonce com overflow (9 dígitos)
    print("TESTE 3: nonce_ascii_len = 9 (nonce com 9 dígitos)")
    nonce_str_9 = str(nonce_sent).zfill(9)  # Com padding para 9
    message_9 = message_hash + nonce_str_9
    sha1_9 = hashlib.sha1(message_9.encode('ascii')).hexdigest()
    print(f"  Nonce string: '{nonce_str_9}' (len={len(nonce_str_9)})")
    print(f"  Message: {message_9}")
    print(f"  SHA-1: {sha1_9}")
    print(f"  Match: {sha1_9 == expected_hash}")
    print()
    
    # Teste 4: Análise do nonce correto encontrado (440171)
    print("TESTE 4: Nonce correto encontrado (440171) - 6 dígitos")
    correct_nonce = 440171
    nonce_str_correct = str(correct_nonce).zfill(6)
    message_correct = message_hash + nonce_str_correct
    sha1_correct = hashlib.sha1(message_correct.encode('ascii')).hexdigest()
    print(f"  Nonce string: '{nonce_str_correct}' (len={len(nonce_str_correct)})")
    print(f"  Message: {message_correct}")
    print(f"  SHA-1: {sha1_correct}")
    print(f"  Match: {sha1_correct == expected_hash}")
    print()
    
    # Teste 5: Tenta entender o padrão
    print("TESTE 5: Analisando o padrão - como 67549035 vira 440171?")
    print(f"  67549035 (8 dígitos) → 440171 (6 dígitos)")
    print(f"  Diferença: {67549035 - 440171} = 0x{67549035 - 440171:08x}")
    print(f"  Byte analysis:")
    print(f"    67549035 = 0x{67549035:08x} = bytes: 0x04 0x06 0xb7 0x6b")
    print(f"    440171   = 0x{440171:08x} = bytes: 0x00 0x06 0xb7 0x6b")
    print(f"  Observação: Apenas o byte MSB diferencia! 0x04 vs 0x00")
    print()

if __name__ == '__main__':
    test_message_for_8digit_nonce()
