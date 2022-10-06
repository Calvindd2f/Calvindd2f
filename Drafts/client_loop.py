import socket
from typing import Counter

host = '192.168.xx.68'
port = 2000


ClientSocket = socket.socket()
print('Waiting for connection')
try:
    ClientSocket.connect((host, port))
except socket.error as e:
    print(str(e))


Counter = 0
while Counter < 12:
    msg = ClientSocket.recv(1024)
    print(msg.decode('utf-8'))
    ClientSocket.send(msg)
    print(msg.decode('utf-8'))
    Counter += 1


ClientSocket.close()
