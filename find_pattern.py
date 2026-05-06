#!/usr/bin/env python3
"""
Diagnostic script to find the pattern in rejected nonces.
For each error log entry, finds the CORRECT nonce and compares with sent nonce.
"""
import os
import hashlib
import re
from pathlib import Path

def find_correct_nonce(message_hash_hex, expected_hash_hex, max_search=10000000):
    """
    Brute force search for the nonce that produces the expected hash.
    Returns the correct nonce or None if not found.
    """
    # Try with different nonce string lengths (1-9 digits)
    for nonce_len in range(1, 10):
        print(f"  Searching with {nonce_len}-digit nonces...", end="", flush=True)
        
        # Calculate the range for this nonce_len
        if nonce_len == 1:
            start, end = 0, 9
        else:
            start = 10 ** (nonce_len - 1)
            end = min(10 ** nonce_len, max_search)
        
        for nonce_val in range(start, end):
            nonce_str = str(nonce_val).zfill(nonce_len)
            message = message_hash_hex + nonce_str
            sha1 = hashlib.sha1(message.encode('ascii')).hexdigest()
            
            if sha1 == expected_hash_hex:
                print(f" FOUND!\n")
                return nonce_val, nonce_len
        
        print(f" not found")
    
    return None, None

def parse_error_log(filepath):
    """Parse error log file and extract nonce/hash pairs."""
    entries = []
    
    with open(filepath, 'r') as f:
        content = f.read()
    
    # Split by the separator line
    blocks = content.split('================================================================================')
    
    for block in blocks:
        if 'NONCE:' not in block:
            continue
        
        # Extract fields
        nonce_match = re.search(r'NONCE:\s+(\d+)', block)
        msg_hash_match = re.search(r'MESSAGE_HASH:\s+([a-f0-9]+)', block)
        exp_hash_match = re.search(r'EXPECTED_HASH:\s+([a-f0-9]+)', block)
        difficulty_match = re.search(r'DIFICULDADE:\s+(\d+)', block)
        status_match = re.search(r'STATUS:\s+(\w+)', block)
        
        if all([nonce_match, msg_hash_match, exp_hash_match]):
            entries.append({
                'nonce_sent': int(nonce_match.group(1)),
                'message_hash': msg_hash_match.group(1),
                'expected_hash': exp_hash_match.group(1),
                'difficulty': int(difficulty_match.group(1)) if difficulty_match else 0,
                'status': status_match.group(1) if status_match else 'UNKNOWN'
            })
    
    return entries

def main():
    error_logs_dir = Path('C:\\Users\\Emerson\\Documents\\python\\duinocoin_miner_tangnano20k_fpga\\error_logs')
    
    all_entries = []
    
    # Parse all error log files
    for log_file in sorted(error_logs_dir.glob('rejected_shares_*.txt')):
        print(f"\n{'='*80}")
        print(f"Parsing: {log_file.name}")
        print(f"{'='*80}")
        entries = parse_error_log(log_file)
        all_entries.extend(entries)
    
    print(f"\n{'='*80}")
    print(f"ANALYSIS OF {len(all_entries)} REJECTED SHARES")
    print(f"{'='*80}\n")
    
    # Analyze patterns
    nonce_digit_counts = {}
    pattern_found = False
    
    for i, entry in enumerate(all_entries, 1):
        nonce_sent = entry['nonce_sent']
        nonce_digits = len(str(nonce_sent))
        msg_hash = entry['message_hash']
        exp_hash = entry['expected_hash']
        difficulty = entry['difficulty']
        
        nonce_digit_counts[nonce_digits] = nonce_digit_counts.get(nonce_digits, 0) + 1
        
        print(f"\n[{i}/{len(all_entries)}] NONCE: {nonce_sent} ({nonce_digits} digits), DIFFICULTY: {difficulty}")
        print(f"MESSAGE_HASH: {msg_hash}")
        print(f"EXPECTED_HASH: {exp_hash}")
        
        # Find correct nonce
        correct_nonce, correct_len = find_correct_nonce(msg_hash, exp_hash)
        
        if correct_nonce is not None:
            print(f"CORRECT NONCE: {correct_nonce} ({correct_len} digits)")
            
            if correct_nonce == nonce_sent:
                print(f"STATUS: NONCE MATCHES - UNEXPECTED!")
            else:
                pattern_found = True
                diff = correct_nonce - nonce_sent
                print(f"STATUS: MISMATCH - Difference: {diff}")
                print(f"        Sent: {nonce_sent} ({nonce_digits} digits)")
                print(f"        Expected: {correct_nonce} ({correct_len} digits)")
                
                # Analyze the difference
                if nonce_digits != correct_len:
                    print(f"        >>> DIGIT COUNT MISMATCH: {nonce_digits} vs {correct_len}")
                
                # Check if it's a simple offset
                if diff > 0 and diff < 1000000:
                    print(f"        >>> Simple offset: +{diff}")
        else:
            print(f"CORRECT NONCE: NOT FOUND in search range")
    
    # Summary
    print(f"\n{'='*80}")
    print(f"SUMMARY")
    print(f"{'='*80}")
    print(f"Total rejected shares analyzed: {len(all_entries)}")
    print(f"Nonce digit count distribution:")
    for digits in sorted(nonce_digit_counts.keys()):
        count = nonce_digit_counts[digits]
        print(f"  {digits} digits: {count} shares")
    
    if pattern_found:
        print(f"\nPATTERN FOUND: Some nonces do not match the correct values!")
    else:
        print(f"\nNO PATTERN FOUND: All nonces match (unexpected)")

if __name__ == '__main__':
    main()
