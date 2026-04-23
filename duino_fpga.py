# Importações necessárias para o minerador
import hashlib  # Para calcular SHA-1
import os  # Para executar operações do sistema
from socket import socket, SOL_SOCKET, SO_REUSEADDR  # Socket com opções
import sys  # Para argumentos do sistema
import time  # Para temporização e timestamps
import serial
# Configurações
COM_PORT = "COM9"
BAUDRATE = 115200 # Alterado 115200
TIMEOUT = 60
NODE_ADDRESS = '92.246.129.145'  # IP do servidor DuinoCoin
NODE_PORT = 5089  # Porta do servidor (como int, não string)
def send_to_fpga(data):
    """
    Envia 80 bytes para FPGA via UART e recebe 4 bytes de nonce
    
    Args:
        data: 80 bytes a serem enviados (message + expected_hash)
    
    Returns:
        Nonce (4 bytes convertido para int) ou None se timeout
    """
    try:
        # Abre porta serial
        with serial.Serial(COM_PORT, BAUDRATE, timeout=TIMEOUT) as ser:
            # Envia 80 bytes
            ser.write(data)
            print(f"[ENVIO] {data.decode('ascii', errors='ignore')} (80 bytes)")
            
            # Recebe 4 bytes do nonce (32 bits)
            response = b""
            while len(response) < 4:
                byte = ser.read(1)
                if not byte:  # Timeout
                    return None
                response += byte
            
            # Converte 4 bytes em inteiro (big-endian)
            nonce = int.from_bytes(response, byteorder='big')
            return nonce
                
    except Exception as e:
        print(f"[ERRO FPGA] {e}")
        return None
def current_time():
    """Retorna a hora atual formatada como HH:MM:SS"""
    return time.strftime("%H:%M:%S", time.localtime())
def create_socket():
    """
    Cria um novo socket com configurações adequadas
    
    Returns:
        socket configurado e pronto para conectar
    """
    try:
        soc = socket()
        # Permite reusar endereço (crucial para reconexões rápidas)
        soc.setsockopt(SOL_SOCKET, SO_REUSEADDR, 1)
        return soc
    except Exception as e:
        print(f"[ERRO] Falha ao criar socket: {e}")
        return None
def connect_to_server(soc):
    """
    Conecta ao servidor DuinoCoin com tratamento de erros
    
    Args:
        soc: socket objeto
    
    Returns:
        True se conexão bem-sucedida, False caso contrário
    """
    try:
        print('MINERADOR duinoCoin FPGA TANGNANO 20K by @frenow')
        print(f'{current_time()} : Conectando ao servidor {NODE_ADDRESS}:{NODE_PORT}...')
        soc.connect((NODE_ADDRESS, NODE_PORT))
        print(f'{current_time()} : Conexão estabelecida com sucesso')
        return True
    except Exception as e:
        print(f'{current_time()} : Falha na conexão: {e}')
        return False
# Configurações do minerador
username = 'frenow'         #altere aqui a sua wallet
mining_key = 'None'
# Loop infinito para reconectação automática em caso de falha
attempt = 0
while True:
    attempt += 1
    soc = None
    
    try:
        # Cria novo socket para esta tentativa
        soc = create_socket()
        if soc is None:
            raise Exception("Falha ao criar socket")
        
        # Busca conexão com o servidor DuinoCoin
        if not connect_to_server(soc):
            raise Exception("Não conseguiu conectar ao servidor")
        
        # Recebe versão do servidor
        server_version = soc.recv(100).decode().strip()
        print(f'{current_time()} : Server Version: {server_version}')
        
        # ===== SEÇÃO PRINCIPAL DE MINERAÇÃO =====
        # Loop que permanece enquanto conectado ao servidor
        job_count = 0
        while True:
            job_count += 1
            
            # Solicita novo job (trabalho) ao servidor
            job_request = f"JOB,{username},LOW,{mining_key}"
            soc.send(bytes(job_request, encoding="utf8"))
            
            # Recebe o job do servidor no formato: hash_base,expected_hash,difficulty
            job_data = soc.recv(1024).decode().rstrip("\n")
            print(f'[JOB #{job_count}] Recebido: {job_data}')
            
            # Separa os componentes do job
            job_parts = job_data.split(",")
            if len(job_parts) < 3:
                print(f'{current_time()} : Formato de job inválido: {job_data}')
                break
            
            message_hash = job_parts[0]      # Hash da mensagem
            expected_hash = job_parts[1]     # Hash esperado
            difficulty = job_parts[2]        # Dificuldade
            
            if (int(difficulty) > 90000): # minerador fpga v1 só irá funcionar com dificuldade até 90000
                break
            
            # Combina mensagem + hash esperado (80 bytes total: 40+40)
            payload = (message_hash + expected_hash).encode('ascii')
            
            if len(payload) != 80:
                print(f'{current_time()} : Payload inválido ({len(payload)} bytes, esperado 80)')
                break
            
            print(f'[MINERANDO] Difficulty: {difficulty}')
            
            # Marca o tempo de início do cálculo de hash
            hashingStartTime = time.time()
            
            # Envia para FPGA e recebe resultado (nonce)
            nonce = send_to_fpga(payload)
            
            if nonce is None:
                print(f'{current_time()} : Timeout na FPGA, solicitando novo job')
                break
            
            # Hash encontrado! Calcula estatísticas
            hashingStopTime = time.time()
            timeDifference = hashingStopTime - hashingStartTime
            
            # Se nonce é válido (não zero), calcula hashrate
            if nonce > 0:
                hashrate = nonce / timeDifference  # Hashes por segundo
            else:
                hashrate = 0
            
            # Envia resultado para o servidor: nonce,hashrate,nome_do_software
            result_msg = f"{nonce},{int(hashrate)},fpga_tang_miner"
            soc.send(bytes(result_msg, encoding="utf8"))
            
            # Aguarda feedback do servidor
            feedback = soc.recv(1024).decode().rstrip("\n").upper()
            print(f'[FEEDBACK] {feedback}')
            
            # Se a resposta foi aceita
            if feedback == "GOOD":
                print(f'{current_time()} : ✓ Share ACEITA | '
                      f'Nonce: {nonce} | '
                      f'Hashrate: {int(hashrate/1000)} kH/s | '
                      f'Difficulty: {difficulty}')
                
            # Se a resposta foi rejeitada
            elif feedback == "BAD":
                print(f'{current_time()} : ✗ Share REJEITADA | '
                      f'Nonce: {nonce} | '
                      f'Hashrate: {int(hashrate/1000)} kH/s | '
                      f'Difficulty: {difficulty}')
            else:
                print(f'{current_time()} : ? Resposta desconhecida: {feedback}')
                break
    
    # ===== TRATAMENTO DE ERROS =====
    except KeyboardInterrupt:
        print(f'\n{current_time()} : Mineração interrompida pelo usuário')
        if soc is not None:
            try:
                soc.close()
            except:
                pass
        break  # Sai do loop principal
    
    except Exception as e:
        print(f'{current_time()} : ✗ ERRO: {str(e)}')
        
        # Fechamento seguro do socket
        if soc is not None:
            try:
                print(f'{current_time()} : Fechando socket...')
                soc.close()
                print(f'{current_time()} : Socket fechado com sucesso')
            except Exception as close_error:
                print(f'{current_time()} : Erro ao fechar socket: {close_error}')
        
        # Aguarda antes de reconectar
        print(f'{current_time()} : Tentativa #{attempt} falhou. Reconectando em 5s...')
        time.sleep(5)
        # NÃO usa os.execl(), apenas continua o loop (mais limpo)