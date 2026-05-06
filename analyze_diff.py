diff = -67108864
print(f"Difference: {diff}")
print(f"Absolute: {abs(diff)} = 0x{abs(diff):08x}")
print(f"In binary: {bin(diff & 0xFFFFFFFF)}")
print()
print(f"2^24 = {2**24} = 0x{2**24:08x}")
print(f"2^26 = {2**26} = 0x{2**26:08x}")
print()
sent = 67549035
correct = 440171
print(f"Sent:    0x{sent:08x}")
print(f"Correct: 0x{correct:08x}")
print()
# Convert to bytes
sent_bytes = sent.to_bytes(4, byteorder="big")
correct_bytes = correct.to_bytes(4, byteorder="big")
print(f"Sent bytes:    {' '.join(f'0x{b:02x}' for b in sent_bytes)}")
print(f"Correct bytes: {' '.join(f'0x{b:02x}' for b in correct_bytes)}")
