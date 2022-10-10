#!/usr/bin/python3
import socket
import sys
#2002.py
 
sock = socket.socket(socket.AF_INET,socket.SOCK_STREAM)
sock.connect(('192.168.62.68',2002))
 
payload = b''
i =0
while True:
        data = sock.recv(1024)
        if data:
                payload += data
                #print("Chunk %d recived" % i)
                i = i+1
        else:
                print("No data received")
                break
print(len(payload))
imageArray = payload.split(b'\r\n\r\n')
for i in range(0,len(imageArray)-1):
        pos =imageArray[i].find(b'\r\n')
        fileName = b'fetched' +imageArray[i][0:pos]
        print(fileName)
        fileContent = imageArray[i][pos+2:-2]
        print(fileContent)
        with open(fileName,'wb+') as f:
                f.write(fileContent)
