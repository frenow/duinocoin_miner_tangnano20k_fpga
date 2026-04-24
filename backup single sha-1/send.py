import serial
import hashlib
import time  # Para temporização e timestamps

# Configurações
COM_PORT = "COM9"
BAUDRATE = 115200
TIMEOUT = 10

def send_to_fpga(data):
    """
    Envia 80 bytes para FPGA via UART e recebe 20 bytes de SHA-1
    
    Args:
        data: 80 bytes a serem enviados
    
    Returns:
        SHA-1 digest (20 bytes) ou None se timeout
    """
    try:
        # Abre porta serial
        with serial.Serial(COM_PORT, BAUDRATE, timeout=TIMEOUT) as ser:
            # Envia 80 bytes
            ser.write(data)
            print(f"[ENVIO] {data.decode('ascii', errors='ignore')} (80 bytes)")
            
            # Recebe 20 bytes do SHA-1
            response = b""
            while len(response) < 4:
                byte = ser.read(1)
                if not byte:  # Timeout
                    return None
                response += byte
            
            
            response = int.from_bytes(response, byteorder='big')
            return response
                
    except Exception as e:
        print(f"[ERRO] {e}")
        return None


if __name__ == "__main__":
    # Teste com 80 bytes fixos - primeiros 40 bytes mensagem ... 40 bytes restante sha-1 esperado
    #test_data = b'abcdefghijklmnopqrstuvwxyz01234567890123052362f2cf99d0f0a7612df9d1d0e09902d7ea22' nonce 1000
    test_data =  b'abcdefghijklmnopqrstuvwxyz01234567890123052362f2cf99d0f0a7612df9d1d0e09902d7ea22'
    
    print(f"\n{'='*60}")
    print("TESTE SIMPLES: ENVIO DE 80 BYTES -> GOLD NONCE")
    print(f"{'='*60}\n")
    
    # Marca o tempo de início do cálculo de hash
    hashingStartTime = time.time()    
    
    result = send_to_fpga(test_data)
    print(f'[Gold Nonce] {result}')
    
    # Hash encontrado! Calcula estatísticas
    # Exemplo: se result = 1234567, então a solução foi encontrada no 1.234.567º hash testado
    hashingStopTime = time.time()
    timeDifference = hashingStopTime - hashingStartTime
    hashrate = result / timeDifference  # Hashes por segundo (1.234.567 / tempo)
    print(f'[HashRate] {int(hashrate/1000)}')
    
