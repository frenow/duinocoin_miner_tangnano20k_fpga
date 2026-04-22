# Importações necessárias para o minerador
import hashlib  # Para calcular SHA-1
import os  # Para executar operações do sistema
from socket import socket  # Para comunicação TCP/IP com o servidor
import sys  # Para argumentos do sistema
import time  # Para temporização e timestamps
from urllib.request import Request, urlopen  # Para requisições HTTP (não utilizado neste código)
from json import loads  # Para parsear JSON (não utilizado neste código)


# Socket global para manter conexão com o servidor
soc = socket()


def current_time():
    """Retorna a hora atual formatada como HH:MM:SS"""
    t = time.localtime()
    current_time = time.strftime("%H:%M:%S", t)
    return current_time

# Configurações do minerador
username = 'frenow'  # Nome de usuário na rede DuinoCoin
mining_key = 'None'  # Chave de mineração (None = mineração anônima)

# Loop infinito para reconectação automática em caso de falha
while True:
    try:
        # Busca conexão com o servidor DuinoCoin
        print(f'{current_time()} : Searching for fastest connection to the server')
        NODE_ADDRESS = '92.246.129.145'  # IP do servidor DuinoCoin
        NODE_PORT    = '5089'  # Porta do servidor
        soc.connect((str(NODE_ADDRESS), int(NODE_PORT)))
        print(f'{current_time()} : Fastest connection found')
        
        # Recebe versão do servidor
        server_version = soc.recv(100).decode()
        print (f'{current_time()} : Server Version: '+ server_version)
        
        # ===== SEÇÃO PRINCIPAL DE MINERAÇÃO =====
        # Loop que permanece enquanto conectado ao servidor
        while True:
            # Solicita novo job (trabalho) ao servidor
            soc.send(bytes(
                    "JOB,"
                    + str(username)
                    + ",LOW,"
                    + str(mining_key),
                    encoding="utf8"))

            # Recebe o job do servidor no formato: hash_base,expected_hash,dificuldade
            # Exemplo: 62d68d64f6402637c713d5dbc4f3a8c2b09cd311,7d8c8b6362301942f5938a52b823c1fe58b7ec6c,20000
            job = soc.recv(1024).decode().rstrip("\n")
            print(f'{job} : Recebe o job')
            
            # Separa os componentes do job
            job = job.split(",")
            difficulty = job[2]  # Dificuldade: 20000 (número de iterações = 100 * 20000 = 2.000.000)

            # Marca o tempo de início do cálculo de hash
            hashingStartTime = time.time()
            
            # Cria um objeto SHA-1 com o hash base (job[0])
            # Este é o valor que será incrementado
            # Exemplo: job[0] = "62d68d64f6402637c713d5dbc4f3a8c2b09cd311"
            base_hash = hashlib.sha1(str(job[0]).encode('ascii'))
            #print(f'{base_hash} : base hash sha-1')
            temp_hash = None

            # ===== LOOP PRINCIPAL DE PROVA DE TRABALHO =====
            # Itera até encontrar um hash que combine com o esperado (job[1])
            # Número de iterações = 100 * dificuldade + 1 = 100 * 20000 + 1 = 2.000.001
            for result in range(100 * int(difficulty) + 1):
                # Cria uma cópia do hash base para não perder o original
                temp_hash = base_hash.copy()
                
                # Concatena o número da iteração ao hash base
                # Ex: SHA1("62d68d64f6402637c713d5dbc4f3a8c2b09cd311" + "0")
                #     SHA1("62d68d64f6402637c713d5dbc4f3a8c2b09cd311" + "1")
                #     ... até encontrar um que coincida com job[1]
                temp_hash.update(str(result).encode('ascii'))

                # Obtém o valor hexadecimal do hash SHA-1
                ducos1 = temp_hash.hexdigest()

                # Verifica se o hash calculado coincide com o esperado
                # Procura por: 7d8c8b6362301942f5938a52b823c1fe58b7ec6c
                if job[1] == ducos1:
                    # Hash encontrado! Calcula estatísticas
                    # Exemplo: se result = 1234567, então a solução foi encontrada no 1.234.567º hash testado
                    hashingStopTime = time.time()
                    timeDifference = hashingStopTime - hashingStartTime
                    hashrate = result / timeDifference  # Hashes por segundo (1.234.567 / tempo)

                    # Envia resultado para o servidor: iteração_encontrada,hashrate,nome_do_software
                    soc.send(bytes(
                        str(result)
                        + ","
                        + str(hashrate)
                        + ",Minimal_PC_Miner",
                        encoding="utf8"))

                    # Aguarda feedback do servidor
                    feedback = soc.recv(1024).decode().rstrip("\n")
                    print(f'{feedback} : Get feedback about the result')
                    
                    # Se a resposta foi aceita
                    if feedback == "GOOD":
                        print(f'{current_time()} : Accepted share',
                              result,
                              "Hashrate",
                              int(hashrate/1000),
                              "kH/s",
                              "Difficulty",
                              difficulty)
                        break  # Sai do loop de iterações e solicita novo job
                    
                    # Se a resposta foi rejeitada
                    elif feedback == "BAD":
                        print(f'{current_time()} : Rejected share',
                              result,
                              "Hashrate",
                              int(hashrate/1000),
                              "kH/s",
                              "Difficulty",
                              difficulty)
                        break  # Sai do loop de iterações e solicita novo job

    # Tratamento de erros (conexão perdida, timeout, etc)
    except Exception as e:
        print(f'{current_time()} : Error occured: ' + str(e) + ", restarting in 5s.")
        time.sleep(5)  # Aguarda 5 segundos
        os.execl(sys.executable, sys.executable, *sys.argv)  # Reinicia o script