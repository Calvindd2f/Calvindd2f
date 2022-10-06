#!/usr/bin/python3
#interactive-client.py

import socket
import telnetlib

def interact(socket):
    t = telnetlib.Telnet(host, port)
    t.interact()

client = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
host = '192.168.92.68'
port = 2003

client.connect((host, port)) # Connect to our client
msg = client.recv(1024)
print (msg.decode('ascii'))

interact(client)
client.close()
