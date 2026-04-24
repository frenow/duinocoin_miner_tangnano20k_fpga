# Importações necessárias para o minerador
import hashlib  # Para calcular SHA-1
import os  # Para executar operações do sistema
from socket import socket, SOL_SOCKET, SO_REUSEADDR  # Socket com opções
import sys  # Para argumentos do sistema
import time  # Para temporização e timestamps
import serial

# ===== DEFINIÇÕES DE CORES ANSI =====
class Colors:
    """Cores ANSI para terminal"""
    RESET = '\033[0m'
    BOLD = '\033[1m'
    DIM = '\033[2m'
    
    # Cores de Texto
    BLACK = '\033[30m'
    RED = '\033[31m'
    GREEN = '\033[32m'
    YELLOW = '\033[33m'
    BLUE = '\033[34m'
    MAGENTA = '\033[35m'
    CYAN = '\033[36m'
    WHITE = '\033[37m'
    
    # Cores de Fundo
    BG_RED = '\033[41m'
    BG_GREEN = '\033[42m'
    BG_YELLOW = '\033[43m'
    BG_BLUE = '\033[44m'
    BG_MAGENTA = '\033[45m'
    BG_CYAN = '\033[46m'
    
    # Estilos
    SUCCESS = f'{BOLD}{GREEN}'
    ERROR = f'{BOLD}{RED}'
    WARNING = f'{BOLD}{YELLOW}'
    INFO = f'{BOLD}{CYAN}'
    DEBUG = f'{BOLD}{MAGENTA}'

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
            print(f"{Colors.INFO}📤 [ENVIO]{Colors.RESET} {data.decode('ascii', errors='ignore')} (80 bytes)")
            
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
        print(f"{Colors.ERROR}❌ [ERRO FPGA]{Colors.RESET} {e}")
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
        print(f"{Colors.ERROR}❌ [ERRO]{Colors.RESET} Falha ao criar socket: {e}")
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
        print(f"{Colors.BOLD}{Colors.CYAN}⛏️  MINERADOR duinoCoin FPGA TANGNANO 20K v2{Colors.RESET} {Colors.YELLOW}by @frenow{Colors.RESET}")
        print(f'{Colors.INFO}🔗 [{current_time()}]{Colors.RESET} Conectando ao servidor {Colors.YELLOW}{NODE_ADDRESS}:{NODE_PORT}{Colors.RESET}...')
        soc.connect((NODE_ADDRESS, NODE_PORT))
        print(f'{Colors.SUCCESS}✓ [{current_time()}]{Colors.RESET} Conexão estabelecida com sucesso')
        return True
    except Exception as e:
        print(f'{Colors.ERROR}✗ [{current_time()}]{Colors.RESET} Falha na conexão: {e}')
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
        print(f'{Colors.SUCCESS}✓ [{current_time()}]{Colors.RESET} Server Version: {Colors.YELLOW}{server_version}{Colors.RESET}')
        
        # ===== SEÇÃO PRINCIPAL DE MINERAÇÃO =====
        # Loop que permanece enquanto conectado ao servidor
        job_count = 0
        while True:
            job_count += 1
            
            # Solicita novo job (trabalho) ao servidor
            job_request = f"JOB,{username},MEDIUM,{mining_key}"
            soc.send(bytes(job_request, encoding="utf8"))
            
            # Recebe o job do servidor no formato: hash_base,expected_hash,difficulty
            job_data = soc.recv(1024).decode().rstrip("\n")
            print(f'{Colors.INFO}📦 [JOB #{job_count}]{Colors.RESET} Recebido: {Colors.YELLOW}{job_data}{Colors.RESET}')
            
            # Separa os componentes do job
            job_parts = job_data.split(",")
            if len(job_parts) < 3:
                print(f'{Colors.ERROR}✗ [{current_time()}]{Colors.RESET} Formato de job inválido: {job_data}')
                break
            
            message_hash = job_parts[0]      # Hash da mensagem
            expected_hash = job_parts[1]     # Hash esperado
            difficulty = job_parts[2]        # Dificuldade
            
            if (int(difficulty) > 3200000): # minerador fpga v1 só irá funcionar com dificuldade até 3200000
                print(f'{Colors.WARNING}⚠️  [{current_time()}]{Colors.RESET} Dificuldade muito alta: {difficulty} (máximo suportado: 3.2M)')
                break
            
            # Combina mensagem + hash esperado (80 bytes total: 40+40)
            payload = (message_hash + expected_hash).encode('ascii')
            
            if len(payload) != 80:
                print(f'{Colors.ERROR}✗ [{current_time()}]{Colors.RESET} Payload inválido ({len(payload)} bytes, esperado 80)')
                break
            
            print(f'{Colors.DEBUG}⚙️  [MINERANDO]{Colors.RESET} Dificuldade: {Colors.YELLOW}{difficulty}{Colors.RESET}')
            
            # Marca o tempo de início do cálculo de hash
            hashingStartTime = time.time()
            
            # Envia para FPGA e recebe resultado (nonce)
            nonce = send_to_fpga(payload)
            
            if nonce is None:
                print(f'{Colors.ERROR}✗ [{current_time()}]{Colors.RESET} Timeout na FPGA, solicitando novo job')
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
            
            # Se a resposta foi aceita
            if feedback == "GOOD":
                print(f'{Colors.SUCCESS}✓ [{current_time()}]{Colors.RESET} Share {Colors.GREEN}ACEITA{Colors.RESET} | '
                      f'💰 Nonce: {Colors.YELLOW}{nonce}{Colors.RESET} | '
                      f'⚡ Hashrate: {Colors.CYAN}{int(hashrate/1000)}{Colors.RESET} kH/s | '
                      f'🎯 Dificuldade: {Colors.YELLOW}{difficulty}{Colors.RESET}')
                
            # Se a resposta foi rejeitada
            elif feedback == "BAD":
                print(f'{Colors.ERROR}✗ [{current_time()}]{Colors.RESET} Share {Colors.RED}REJEITADA{Colors.RESET} | '
                      f'💰 Nonce: {Colors.YELLOW}{nonce}{Colors.RESET} | '
                      f'⚡ Hashrate: {Colors.CYAN}{int(hashrate/1000)}{Colors.RESET} kH/s | '
                      f'🎯 Dificuldade: {Colors.YELLOW}{difficulty}{Colors.RESET}')
            else:
                print(f'{Colors.WARNING}⚠️  [{current_time()}]{Colors.RESET} Resposta desconhecida: {Colors.YELLOW}{feedback}{Colors.RESET}')
                print(f'{Colors.ERROR}✗ [{current_time()}]{Colors.RESET} Share {Colors.RED}REJEITADA{Colors.RESET} | '
                      f'💰 Nonce: {Colors.YELLOW}{nonce}{Colors.RESET} | '
                      f'⚡ Hashrate: {Colors.CYAN}{int(hashrate/1000)}{Colors.RESET} kH/s | '
                      f'🎯 Dificuldade: {Colors.YELLOW}{difficulty}{Colors.RESET}')
                break
    
    # ===== TRATAMENTO DE ERROS =====
    except KeyboardInterrupt:
        print(f'\n{Colors.WARNING}⏹️  [{current_time()}]{Colors.RESET} Mineração interrompida pelo usuário')
        if soc is not None:
            try:
                soc.close()
            except:
                pass
        break  # Sai do loop principal
    
    except Exception as e:
        print(f'{Colors.ERROR}❌ [{current_time()}]{Colors.RESET} ERRO: {str(e)}')
        
        # Fechamento seguro do socket
        if soc is not None:
            try:
                print(f'{Colors.INFO}🔌 [{current_time()}]{Colors.RESET} Fechando socket...')
                soc.close()
                print(f'{Colors.SUCCESS}✓ [{current_time()}]{Colors.RESET} Socket fechado com sucesso')
            except Exception as close_error:
                print(f'{Colors.ERROR}❌ [{current_time()}]{Colors.RESET} Erro ao fechar socket: {close_error}')
        
        # Aguarda antes de reconectar
        print(f'{Colors.WARNING}⚠️  [{current_time()}]{Colors.RESET} Tentativa #{attempt} falhou. Reconectando em 5s...')
        time.sleep(5)
        # NÃO usa os.execl(), apenas continua o loop (mais limpo)